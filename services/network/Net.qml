// The only Quickshell.Networking surface in the shell. Everything in that module is empty
// for the first 1-3s of startup, so every read here is a binding and nothing latches state.
pragma Singleton

import "../../modules/popups"
import "../audio"
import "Profiles.js" as Profiles
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    // --- devices ---------------------------------------------------------------

    // Nothing ever populated `devices` unless something was attached to the model.
    Instantiator {
        model: Networking.devices
        delegate: QtObject {}
    }

    readonly property var deviceList: Networking.devices ? (Networking.devices.values || []) : []

    readonly property var wifiDevice: {
        var l = root.deviceList;
        for (var i = 0; i < l.length; i++)
            if (l[i] && l[i].type === DeviceType.Wifi)
                return l[i];
        return null;
    }
    readonly property var wiredDevice: {
        var l = root.deviceList;
        for (var i = 0; i < l.length; i++)
            if (l[i] && l[i].type === DeviceType.Wired)
                return l[i];
        return null;
    }

    // Presence is the device, never Networking.wifiEnabled: that is NM's global rfkill
    // flag and reads true on a box with no adapter at all.
    readonly property bool wifiPresent: root.wifiDevice !== null
    readonly property bool wiredPresent: root.wiredDevice !== null

    property bool graceDone: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root.graceDone = true
    }
    readonly property bool ready: Networking.backend !== NetworkBackendType.None && (root.deviceList.length > 0 || root.graceDone)

    readonly property int connectivity: Networking.connectivity

    // --- radio -----------------------------------------------------------------

    property bool radioPending: false
    property bool expectedRadio: false
    readonly property bool radioOn: root.radioPending ? root.expectedRadio : Networking.wifiEnabled
    readonly property bool radioHwBlocked: !Networking.wifiHardwareEnabled

    Timer {
        id: radioFailsafe
        interval: 8000
        onTriggered: root.radioPending = false
    }

    function setRadio(on) {
        root.expectedRadio = on === true;
        root.radioPending = true;
        radioFailsafe.restart();
        Sounds.playSfx(on ? "network/power_on.wav" : "network/power_off.wav");
        Networking.wifiEnabled = on === true;
        // The toast helpers/network-fetch.sh used to raise; dropping it would be a regression.
        Quickshell.execDetached(["notify-send", "-u", "low", "-i", on ? "network-wireless-enabled" : "network-wireless-disabled", "WiFi", on ? "Enabled" : "Disabled"]);
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (Networking.wifiEnabled === root.expectedRadio)
                root.radioPending = false;
        }
    }

    // --- status ----------------------------------------------------------------

    // Bumped by the per-network watchers: a model's valuesChanged fires on insert/remove only.
    property int connRev: 0

    readonly property var wifiNetwork: {
        void root.connRev;
        var d = root.wifiDevice;
        if (!d || !d.networks)
            return null;
        var v = d.networks.values || [];
        for (var i = 0; i < v.length; i++)
            if (v[i] && v[i].connected)
                return v[i];
        return null;
    }

    readonly property string wifiSsid: root.wifiNetwork ? ("" + root.wifiNetwork.name) : ""

    property int signalStore: 0
    readonly property int wifiSignal: root.signalStore

    readonly property bool ethLink: root.wiredDevice !== null && root.wiredDevice.hasLink === true
    readonly property bool ethConnected: root.wiredDevice !== null && root.wiredDevice.connected === true
    readonly property int ethSpeed: root.wiredDevice ? (root.wiredDevice.linkSpeed || 0) : 0
    readonly property string ethStatus: (!root.ready || !root.wiredPresent) ? "Ethernet" : (root.ethConnected ? "Connected" : "Disconnected")

    readonly property string status: {
        if (!root.ready)
            return "unknown";
        if (root.ethConnected)
            return "enabled";
        if (!root.wifiPresent)
            return "unavailable";
        return root.radioOn ? "enabled" : "disabled";
    }

    function normSignal(s) {
        var v = Number(s);
        if (!isFinite(v))
            return 0;
        return v <= 1 ? v * 100 : v;
    }

    function signalGlyph(pct) {
        if (pct >= 75)
            return "\u{f0928}";
        if (pct >= 50)
            return "\u{f0925}";
        if (pct >= 25)
            return "\u{f0922}";
        return "\u{f091f}";
    }

    // Codepoints lifted verbatim from helpers/network-fetch.sh so the bar pill looks unchanged.
    readonly property string radioIcon: {
        if (!root.wifiPresent)
            return "\u{f0202}";
        if (!root.radioOn)
            return "\u{f092e}";
        if (!root.wifiNetwork)
            return "\u{f092f}";
        return root.signalGlyph(root.wifiSignal);
    }
    readonly property string linkIcon: root.ethConnected ? "\u{f0200}" : root.radioIcon

    function refreshSignal() {
        var n = root.wifiNetwork;
        root.signalStore = n ? Math.round(root.normSignal(n.signalStrength)) : 0;
    }
    onWifiNetworkChanged: {
        root.refreshSignal();
        ipSettle.restart();
    }

    // --- the Wi-Fi list, debounced ---------------------------------------------

    readonly property var rawNetworks: {
        var d = root.wifiDevice;
        return (d && d.networks) ? (d.networks.values || []) : [];
    }
    onRawNetworksChanged: root.markDirty()

    property var listStore: []
    readonly property var wifiNetworks: root.listStore
    property int listRev: 0
    property bool listLocked: false
    property bool pendingCommit: false

    property double lastCommit: 0

    Timer {
        id: rebuildTimer
        interval: 900
        onTriggered: root.commitList()
    }

    // restart() alone starves forever in a busy RF environment, so age out at 2s.
    function markDirty() {
        if (Date.now() - root.lastCommit >= 2000)
            root.commitList();
        else
            rebuildTimer.restart();
    }

    function commitList() {
        // Live values are never gated by the hover lock; only membership is.
        root.refreshSignal();
        if (root.listLocked) {
            root.pendingCommit = true;
            return;
        }
        rebuildTimer.stop();
        root.lastCommit = Date.now();
        root.pendingCommit = false;
        var src = root.rawNetworks;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i])
                out.push(src[i]);
        // Bucketed, so a 1% drift can never reshuffle the ring.
        out.sort(function (a, b) {
            var ba = Math.floor(root.normSignal(a.signalStrength) / 20);
            var bb = Math.floor(root.normSignal(b.signalStrength) / 20);
            if (ba !== bb)
                return bb - ba;
            return ("" + a.name).localeCompare("" + b.name);
        });
        root.listStore = out;
        root.listRev++;
    }

    onListLockedChanged: {
        if (!root.listLocked && root.pendingCommit)
            root.commitList();
    }

    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks : null
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onSignalStrengthChanged() {
                // The bar pill must not freeze while a card is hovered.
                if (modelData === root.wifiNetwork)
                    root.refreshSignal();
                root.markDirty();
            }
            function onKnownChanged() {
                root.markDirty();
            }
            function onConnectedChanged() {
                root.connRev++;
                root.refreshSignal();
                root.markDirty();
            }
            function onStateChangingChanged() {
                root.connRev++;
            }
        }
    }

    // --- scanner, refcounted ----------------------------------------------------

    property int scanHolders: 0
    function acquireScan() {
        root.scanHolders++;
    }
    function releaseScan() {
        if (root.scanHolders > 0)
            root.scanHolders--;
    }

    // Folded into the binding rather than written imperatively: an imperative write would
    // destroy the binding and the scanner would never come back.
    property bool scanKick: true

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.scanHolders > 0 && root.radioOn && root.scanKick
        when: root.wifiDevice !== null
        restoreMode: Binding.RestoreNone
    }

    Timer {
        id: rescanKick
        interval: 150
        onTriggered: root.scanKick = true
    }

    // There is no scan() method; false -> true as a rescan trigger is an inference, not API.
    function rescan() {
        if (!root.wifiDevice)
            return;
        root.scanKick = false;
        rescanKick.restart();
    }

    // --- connect state machine (every mutating call is fire-and-forget) ---------

    property string attemptSsid: ""
    property string attemptPhase: "idle"
    property string attemptReason: ""
    property bool attemptWrongPassword: false
    property var attemptTarget: null

    readonly property string errorSfx: ""   // network/error.wav is not shipped

    // Never cache a Network: one with no APs and no settings is destroyed under you.
    function resolveNetwork(ssid) {
        var src = root.rawNetworks;
        for (var i = 0; i < src.length; i++)
            if (src[i] && src[i].name === ssid)
                return src[i];
        return null;
    }

    function pskSecurity(sec) {
        return sec === WifiSecurityType.Sae || sec === WifiSecurityType.Wpa2Psk || sec === WifiSecurityType.WpaPsk;
    }

    // A plain Network has no `security` at all; a WifiNetwork with no AP reports Unknown.
    function knownSecurity(sec) {
        return sec !== undefined && sec !== null && sec !== WifiSecurityType.Unknown;
    }

    function secLabel(sec) {
        return root.knownSecurity(sec) ? WifiSecurityType.toString(sec) : "This network";
    }

    function failAttempt(reason) {
        attemptTimeout.stop();
        root.clearPending();
        root.attemptReason = reason;
        root.attemptPhase = "failed";
        failClear.restart();
    }

    // A profile with no AP in range — a freshly created hidden one above all — reports
    // security Unknown, and connectWithPsk refuses that. Hold the PSK until the directed
    // probe answers and the real security type lands, then connect for real.
    property string pendingPsk: ""
    property int pendingTicks: 0
    property bool pendingHeldScan: false

    Timer {
        id: pendingWait
        interval: 1000
        repeat: true
        onTriggered: root.retryPending()
    }

    function clearPending() {
        pendingWait.stop();
        root.pendingPsk = "";
        root.pendingTicks = 0;
        if (root.pendingHeldScan) {
            root.pendingHeldScan = false;
            root.releaseScan();
        }
    }

    function retryPending() {
        if (root.pendingPsk === "" || root.attemptPhase !== "connecting") {
            root.clearPending();
            return;
        }
        var net = root.resolveNetwork(root.attemptSsid);
        if (net && root.pskSecurity(net.security)) {
            var psk = root.pendingPsk;
            root.clearPending();
            root.attemptTarget = net;
            attemptTimeout.restart();
            net.connectWithPsk(psk);
            return;
        }
        root.pendingTicks++;
        if (root.pendingTicks % 6 === 2)
            root.rescan();
        if (root.pendingTicks >= 20) {
            root.clearPending();
            root.failAttempt("The access point never answered — check the name, the security type and that it is in range.");
        }
    }

    function connectWifi(ssid, psk) {
        var net = root.resolveNetwork(ssid);
        root.clearPending();
        root.attemptSsid = ssid;
        root.attemptReason = "";
        if (!net) {
            root.attemptTarget = null;
            root.failAttempt("Network not found");
            return;
        }
        root.attemptWrongPassword = false;
        root.attemptTarget = net;
        root.attemptPhase = "connecting";
        attemptTimeout.restart();

        if (psk && ("" + psk).length > 0) {
            if (net.connected) {
                root.failAttempt("Already connected");
                return;
            }
            // Outside this set connectWithPsk logs and returns with no signal at all.
            if (root.pskSecurity(net.security)) {
                net.connectWithPsk(psk);
                return;
            }
            // The directed probe needs the scanner, which the panel may stop closing behind us.
            if (net.known && !root.knownSecurity(net.security)) {
                root.pendingPsk = "" + psk;
                root.pendingHeldScan = true;
                root.acquireScan();
                pendingWait.restart();
                root.rescan();
                return;
            }
            root.failAttempt(root.secLabel(net.security) + " needs a profile Quickshell.Networking cannot create");
            return;
        }

        // Known networks always try connect() first, so a stale stored PSK answers NoSecrets.
        if (net.known || net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe) {
            net.connect();
            return;
        }
        if (root.pskSecurity(net.security)) {
            attemptTimeout.stop();
            root.attemptPhase = "needsSecret";
            return;
        }
        root.failAttempt(root.secLabel(net.security) + " needs a profile Quickshell.Networking cannot create");
    }

    function disconnectWifi() {
        root.clearPending();
        if (root.wifiNetwork)
            root.wifiNetwork.disconnect();
        else if (root.wifiDevice)
            root.wifiDevice.disconnect();
    }

    // WiredDevice.network is null whenever hasLink is false.
    function connectWired() {
        if (root.wiredDevice && root.wiredDevice.network)
            root.wiredDevice.network.connect();
    }
    function disconnectWired() {
        if (root.wiredDevice)
            root.wiredDevice.disconnect();
    }

    // forget() deletes EVERY saved profile attached to that network.
    function forgetNetwork(net) {
        if (net)
            net.forget();
    }

    Connections {
        target: root.attemptTarget
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) {
            if (root.attemptPhase !== "connecting")
                return;
            attemptTimeout.stop();
            if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout) {
                root.clearPending();
                root.attemptWrongPassword = true;
                root.attemptPhase = "needsSecret";
                return;
            }
            root.failAttempt(ConnectionFailReason.toString(reason));
        }
        function onConnectedChanged() {
            if (!root.attemptTarget || !root.attemptTarget.connected)
                return;
            attemptTimeout.stop();
            root.clearPending();
            root.attemptWrongPassword = false;
            root.attemptPhase = "done";
            Sounds.playSfx("network/connect.wav");
            failClear.restart();
        }
    }

    // NM's own auth timeout is around 25s, so anything shorter races it.
    Timer {
        id: attemptTimeout
        interval: 30000
        onTriggered: root.failAttempt("Timed out")
    }

    Timer {
        id: failClear
        interval: 5000
        onTriggered: {
            if (root.attemptPhase !== "failed" && root.attemptPhase !== "done")
                return;
            root.attemptPhase = "idle";
            root.attemptReason = "";
            root.attemptSsid = "";
            root.attemptWrongPassword = false;
            root.attemptTarget = null;
        }
    }

    // --- IP addresses -----------------------------------------------------------

    // `ip -4 -j addr show` is a read-only query, not nmcli; the module exposes no IP at all.
    readonly property bool showIp: true
    // Only the Network panel reads an IP, so nothing shells out behind a closed panel.
    readonly property bool ipWanted: root.showIp && Popups.current === "network"

    property string wifiIpStore: ""
    property string ethIpStore: ""
    readonly property string wifiIp: root.wifiIpStore
    readonly property string ethIp: root.ethIpStore

    Process {
        id: ipProc
        command: ["ip", "-4", "-j", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.parseIp(this.text)
        }
    }

    function refreshIp() {
        if (!root.ipWanted)
            return;
        ipProc.running = false;
        ipProc.running = true;
    }

    function parseIp(txt) {
        var wName = root.wifiDevice ? root.wifiDevice.name : "";
        var eName = root.wiredDevice ? root.wiredDevice.name : "";
        var w = "";
        var e = "";
        try {
            var arr = JSON.parse(("" + txt).trim() || "[]");
            for (var i = 0; i < arr.length; i++) {
                var it = arr[i];
                if (!it || !it.addr_info || it.addr_info.length === 0)
                    continue;
                var a = "" + (it.addr_info[0].local || "");
                if (wName && it.ifname === wName)
                    w = a;
                else if (eName && it.ifname === eName)
                    e = a;
            }
        } catch (err) {
            w = "";
            e = "";
        }
        root.wifiIpStore = w;
        root.ethIpStore = e;
    }

    // DHCP lands a moment after the link does.
    Timer {
        id: ipSettle
        interval: 1500
        onTriggered: root.refreshIp()
    }
    onEthConnectedChanged: ipSettle.restart()

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: root.ipWanted && (root.ethConnected || root.wifiNetwork !== null)
        onTriggered: root.refreshIp()
    }

    // --- VPN --------------------------------------------------------------------

    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    property bool vpnStore: false
    readonly property bool vpnActive: root.vpnStore

    // NM does not manage wireguard/tun devices and DeviceType is only None/Wifi/Wired,
    // so the interface poll stays. A singleton runs one copy however many screens exist.
    Process {
        id: vpnProc
        command: ["bash", root.helpersDir + "/vpn-check.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.vpnStore = ("" + (this.text || "")).trim() !== ""
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            vpnProc.running = false;
            vpnProc.running = true;
        }
    }

    // --- profile helper runner --------------------------------------------------

    // The helper is fire-and-forget, so its failure has to surface somewhere a sheet can bind.
    property string profilePhase: "idle"   // idle | running | done | failed
    property string profileError: ""
    property string profileStderr: ""

    Process {
        id: profileProc
        stdout: StdioCollector {}   // drained, not read: errors come back on stderr
        stderr: StdioCollector {
            onStreamFinished: {
                var t = ("" + (this.text || "")).trim();
                root.profileStderr = t;
                if (t)
                    console.warn("[Net] profile helper:", t);
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.profilePhase = exitCode === 0 ? "done" : "failed";
            root.profileError = exitCode === 0 ? "" : (root.profileStderr || "The helper exited with code " + exitCode + ".");
        }
    }

    // Profiles.js is a pragma library and cannot reach Quickshell, so it hands the call here.
    function runProfileHelper(script, args) {
        var argv = ["python3", root.helpersDir + "/" + script];
        for (var i = 0; i < args.length; i++)
            argv.push("" + args[i]);
        root.profilePhase = "running";
        root.profileError = "";
        root.profileStderr = "";
        profileProc.running = false;
        profileProc.command = argv;
        profileProc.running = true;
        return true;
    }

    Component.onCompleted: Profiles.setRunner(root.runProfileHelper)
}
