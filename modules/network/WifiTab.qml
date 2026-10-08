// Wi-Fi tab: v2's orbit and hold-to-disconnect core, on Quickshell.Networking via Net.
// The dongle is often absent, so every binding tolerates Net.wifiDevice === null and the
// no-adapter plate is a first-class state rather than an inferred one.

import "shared"
import "wifi"
import "../components"
import "../../services/audio"
import "../../services/network"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import "../../services/layout/Orbit.js" as Orbit
import "../../services/network/Profiles.js" as Profiles

Item {
    id: tab

    property var popup: null
    property bool active: false

    // --- tab contract -------------------------------------------------------
    readonly property string headerGlyph: Net.radioIcon
    readonly property bool headerLit: Net.wifiPresent && Net.radioOn
    readonly property string headerStatus: Net.wifiSsid ? Net.wifiSsid : !Net.wifiPresent ? "No adapter" : Net.radioHwBlocked ? "Blocked" : !Net.radioOn ? "Radio off" : ""
    readonly property string footerText: Net.wifiSsid ? (Net.wifiSignal + "%") : ""
    readonly property bool textFocus: pwSheet.focused || hiddenSheet.focused
    readonly property bool hasPower: true
    readonly property string powerGlyph: "\u{f0425}"
    readonly property bool powerOn: Net.wifiPresent && Net.radioOn
    readonly property bool powerEnabled: Net.wifiPresent && !Net.radioHwBlocked

    // Net owns the sound and the notify-send toast for this.
    function togglePower() {
        Net.setRadio(!Net.radioOn);
    }

    function handleEscape() {
        if (tab.hiddenOpen) {
            tab.hiddenOpen = false;
            return true;
        }
        if (tab.pwOpen) {
            tab.pwDismissed = true;
            return true;
        }
        if (tab.savedMode) {
            tab.setSaved(false);
            return true;
        }
        return false;
    }

    // --- attempt state ------------------------------------------------------
    readonly property bool connecting: Net.attemptPhase === "connecting"
    readonly property bool failed: Net.attemptPhase === "failed"

    property bool pwDismissed: false
    property bool hiddenOpen: false
    readonly property bool pwOpen: Net.attemptPhase === "needsSecret" && !tab.pwDismissed
    readonly property bool sheetOpen: tab.pwOpen || tab.hiddenOpen

    // Re-arm the prompt whenever a fresh attempt starts, so a dismissed sheet reopens.
    Connections {
        target: Net
        function onAttemptPhaseChanged() {
            if (Net.attemptPhase !== "needsSecret")
                tab.pwDismissed = false;
            if (Net.attemptPhase === "failed")
                tab.pendingAutoSsid = "";
        }
        function onWifiNetworkChanged() {
            tab.refreshInfoAuto();
            tab.applyPendingAuto();
            if (!Net.wifiNetwork)
                tab.disconnecting = false;
        }
    }

    // Bound, not cached: resolveNetwork reads Net.rawNetworks so this re-runs on churn.
    readonly property var pwNetwork: Net.attemptSsid ? Net.resolveNetwork(Net.attemptSsid) : null

    // The profile does not exist until the connect lands, so the flag is applied after.
    property string pendingAutoSsid: ""
    function applyPendingAuto() {
        if (tab.pendingAutoSsid === "" || Net.wifiSsid !== tab.pendingAutoSsid)
            return;
        var net = Net.resolveNetwork(tab.pendingAutoSsid);
        if (!net)
            return;
        // Clear only once a profile actually took the write; the watcher below retries.
        if (Profiles.setAutoconnect(net, false)) {
            tab.pendingAutoSsid = "";
            tab.refreshInfoAuto();
        }
    }
    onPendingAutoSsidChanged: {
        if (tab.pendingAutoSsid === "")
            pendingAutoGiveUp.stop();
        else
            pendingAutoGiveUp.restart();
    }
    // A profile that never registers must not disarm a later, unrelated connect.
    Timer {
        id: pendingAutoGiveUp
        interval: 20000
        onTriggered: tab.pendingAutoSsid = ""
    }

    // Net's disconnect is fire-and-forget, so the core's "Disconnecting…" is latched here.
    property bool disconnecting: false
    onDisconnectingChanged: if (tab.disconnecting)
        disconnectClear.restart()
    Timer {
        id: disconnectClear
        interval: 4000
        onTriggered: tab.disconnecting = false
    }

    // --- views --------------------------------------------------------------
    readonly property bool hasLink: Net.wifiNetwork !== null
    property bool listRequested: false
    property bool savedMode: false
    readonly property string view: tab.savedMode ? "saved" : (tab.hasLink && !tab.listRequested) ? "info" : "list"

    onHasLinkChanged: tab.listRequested = false
    onViewChanged: {
        tab.hoverCount = 0;
        tab.syncScan();
        tab.rebuildCards();
    }

    function setSaved(on) {
        if (tab.savedMode === on)
            return;
        Sounds.playSfx("network/switch.wav");
        tab.savedMode = on;
    }

    // --- scanner lifetime ---------------------------------------------------
    // PopupHost destroys the popup on close, so onDestruction is the reliable release.
    property bool scanHeld: false
    function syncScan() {
        var want = tab.active && tab.view !== "saved";
        if (want === tab.scanHeld)
            return;
        tab.scanHeld = want;
        if (want)
            Net.acquireScan();
        else
            Net.releaseScan();
    }
    onActiveChanged: {
        if (!tab.active)
            tab.hoverCount = 0;
        tab.syncScan();
    }
    Component.onCompleted: {
        tab.syncScan();
        tab.rebuildCards();
        tab.refreshInfoAuto();
    }
    Component.onDestruction: {
        if (tab.scanHeld) {
            tab.scanHeld = false;
            Net.releaseScan();
        }
        Net.listLocked = false;
    }

    // --- card model ---------------------------------------------------------
    // Rebuilt only on Net's debounced commit; live per-network values bind directly.
    property var cardModel: []
    property int hoverCount: 0
    onHoverCountChanged: Net.listLocked = tab.hoverCount > 0

    Connections {
        target: Net
        function onListRevChanged() {
            tab.rebuildCards();
        }
    }

    function rebuildCards() {
        var src = Net.wifiNetworks || [];
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var n = src[i];
            if (!n)
                continue;
            if (tab.savedMode) {
                if (n.known !== true)
                    continue;
            } else if (n.connected === true) {
                continue;
            }
            out.push(n);
        }
        // Survivors keep their slots and new APs append, so a commit updates the cards
        // instead of destroying the ring and replaying every entry animation.
        var prev = tab.cardModel, merged = [];
        for (var p = 0; p < prev.length; p++)
            if (out.indexOf(prev[p]) !== -1)
                merged.push(prev[p]);
        for (var q = 0; q < out.length; q++)
            if (merged.indexOf(out[q]) === -1)
                merged.push(out[q]);
        var same = merged.length === prev.length;
        for (var r = 0; same && r < merged.length; r++)
            same = merged[r] === prev[r];
        if (same)
            return;
        tab.cardModel = merged;
        tab.syncSlotMap();
    }

    function dropCard(net) {
        var out = [];
        for (var i = 0; i < tab.cardModel.length; i++)
            if (tab.cardModel[i] !== net)
                out.push(tab.cardModel[i]);
        tab.cardModel = out;
    }

    // Stable slot per SSID, so the ring does not reshuffle when a scan result changes.
    // It only orders the cards — the angle itself comes from the live count.
    readonly property var slotOrder: [0, 5, 2, 7, 4, 9, 1, 6, 3, 8]
    property var slotMap: ({})
    property var ringPos: ({})
    // v2 shrinks the cards past ten rather than dropping any.
    readonly property real dynamicScale: Math.min(1.0, Math.max(0.6, 12.0 / Math.max(1, tab.cardModel.length)))

    function syncSlotMap() {
        var next = {};
        var used = {};
        var waiting = [];
        for (var i = 0; i < tab.cardModel.length; i++) {
            var key = "" + tab.cardModel[i].name;
            var cur = tab.slotMap[key];
            if (cur !== undefined && !used[cur]) {
                next[key] = cur;
                used[cur] = true;
            } else {
                waiting.push(key);
            }
        }
        for (var w = 0; w < waiting.length; w++) {
            var sl = -1;
            for (var j = 0; j < tab.slotOrder.length && sl < 0; j++)
                if (!used[tab.slotOrder[j]])
                    sl = tab.slotOrder[j];
            // Past the fixed ten, take the next free rank so nothing is dropped.
            if (sl < 0) {
                sl = tab.slotOrder.length;
                while (used[sl])
                    sl++;
            }
            next[waiting[w]] = sl;
            used[sl] = true;
        }
        // Fresh objects: mutating a var property emits no change signal.
        tab.slotMap = next;

        var keys = Object.keys(next);
        keys.sort(function (a, b) {
            return next[a] - next[b];
        });
        var pos = {};
        for (var k = 0; k < keys.length; k++)
            pos[keys[k]] = k;
        tab.ringPos = pos;
    }

    // --- info ring ----------------------------------------------------------
    property bool infoAuto: true
    function refreshInfoAuto() {
        tab.infoAuto = Profiles.autoconnect(Net.wifiNetwork);
    }
    Instantiator {
        model: Profiles.profiles(Net.wifiNetwork)
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            // The cached settings map may not be loaded when the profile first registers.
            Component.onCompleted: {
                tab.refreshInfoAuto();
                tab.applyPendingAuto();
            }
            function onSettingsChanged() {
                tab.refreshInfoAuto();
                tab.applyPendingAuto();
            }
        }
    }

    // Evenly spread from the top: eight fixed slots left holes whenever a node was absent.
    function slotAngle(i, count) {
        return -Math.PI / 2 + (i / Math.max(1, count)) * Math.PI * 2;
    }

    // Keys only: values live in the delegate bindings, so a ticking signal or a fresh IP
    // updates a node instead of rebuilding the ring and replaying every entry animation.
    readonly property var infoNodes: {
        if (!Net.wifiNetwork)
            return [];
        var out = ["signal", "security"];
        if (Net.showIp && Net.wifiIp)
            out.push("ip");
        out.push("auto");
        out.push("list");
        out.push("forget");
        return out;
    }

    function nodeValue(k) {
        if (k === "signal")
            return Net.wifiSignal + "%";
        if (k === "security")
            return Net.wifiNetwork ? WifiSecurityType.toString(Net.wifiNetwork.security) : "";
        if (k === "ip")
            return Net.wifiIp;
        if (k === "auto")
            return tab.infoAuto ? "On" : "Off";
        if (k === "list")
            return "Networks";
        return "Forget";
    }

    function nodeLabel(k) {
        if (k === "signal")
            return "Signal";
        if (k === "security")
            return "Security";
        if (k === "ip")
            return tab.copiedLabel === "ip" ? "Copied!" : "IP address";
        if (k === "auto")
            return "Connect automatically";
        if (k === "list")
            return "Show all in range";
        return "Delete saved profiles";
    }

    function nodeGlyph(k) {
        if (k === "signal")
            return "\u{f0928}";
        if (k === "security")
            return "\u{f099d}";
        if (k === "ip")
            return "\u{f0a5f}";
        if (k === "auto")
            return "\u{f18f2}";
        if (k === "list")
            return "\u{f0349}";
        return "\u{f01b4}";
    }

    property string copiedLabel: ""
    Timer {
        id: copiedReset
        interval: 1400
        onTriggered: tab.copiedLabel = ""
    }

    function runInfoAction(act) {
        var net = Net.wifiNetwork;
        if (act === "list") {
            tab.listRequested = true;
            return;
        }
        if (act === "ip") {
            if (Net.wifiIp) {
                Quickshell.execDetached(["wl-copy", "" + Net.wifiIp]);
                tab.copiedLabel = "ip";
                copiedReset.restart();
            }
            return;
        }
        if (!net)
            return;
        if (act === "auto") {
            var next = !tab.infoAuto;
            if (Profiles.setAutoconnect(net, next))
                tab.infoAuto = next;
            return;
        }
        if (act === "forget")
            Net.forgetNetwork(net);
    }

    // --- ambience -----------------------------------------------------------
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            anchors.centerIn: parent
            width: tab.popup.s(220) + index * tab.popup.s(130)
            height: width
            radius: width / 2
            z: -1
            color: "transparent"
            border.width: 1
            border.color: tab.popup.accent
            opacity: (tab.active && Net.radioOn) ? (Net.wifiNetwork ? 0.08 - index * 0.02 : 0.03) : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: 500
                }
            }
        }
    }

    // --- core ---------------------------------------------------------------
    // Raised by the chassis while its parked power disc covers the centre.
    property bool coreHidden: false

    NetworkCore {
        id: core
        anchors.centerIn: parent
        opacity: tab.coreHidden ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
        popup: tab.popup

        absent: Net.ready && !Net.wifiPresent
        powered: Net.radioOn
        connected: Net.wifiNetwork !== null
        busy: tab.connecting || tab.disconnecting
        scanning: tab.active && Net.wifiPresent && Net.radioOn && Net.wifiNetwork === null && !tab.connecting
        holdEnabled: true
        // A sheet's field must get the click, not the disc's hold gesture.
        interactive: !tab.sheetOpen

        // The sheets need more room than the idle disc has.
        width: tab.sheetOpen ? tab.popup.s(300) : tab.popup.s(core.connected ? 200 : 160)

        glyph: !Net.wifiPresent ? "\u{f0202}" : Net.wifiNetwork ? Net.signalGlyph(Net.wifiSignal) : "\u{f05a9}"
        offGlyph: Net.wifiNetwork ? "\u{f05aa}" : Net.radioOn ? "\u{f092f}" : "\u{f092e}"
        name: Net.wifiSsid
        statusText: "Connected"
        absentText: "No Wi-Fi adapter"
        offText: tab.connecting ? Net.attemptSsid : !Net.radioOn ? (Net.radioHwBlocked ? "Blocked by rfkill" : "Wi-Fi Off") : tab.failed ? "Couldn't connect" : "Disconnected"

        onDisconnectRequested: {
            tab.disconnecting = true;
            Net.disconnectWifi();
        }
        onTapped: {
            if (!Net.wifiNetwork && Net.wifiPresent && Net.radioOn)
                Net.rescan();
        }

        // Attempt extras sit over the off plate, which carries the wording.
        Item {
            anchors.fill: parent
            visible: tab.connecting || tab.failed

            LoadingDots {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + tab.popup.s(30)
                pop: tab.popup
                dotCol: tab.popup.overlay0
                visible: tab.connecting
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: tab.popup.s(26)
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: tab.failed
                text: Net.attemptReason
                font.family: Fonts.ui
                font.pixelSize: tab.popup.s(9)
                color: tab.popup.red
            }
        }

        // The sheets are drawn in crust, so give them the accent plate to sit on.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            opacity: tab.sheetOpen ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                }
            }
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.lighter(tab.popup.accent, 1.15)
                }
                GradientStop {
                    position: 1.0
                    color: tab.popup.accent
                }
            }
        }

        WifiPasswordSheet {
            id: pwSheet
            popup: tab.popup
            open: tab.pwOpen
            ssid: Net.attemptSsid
            security: tab.pwNetwork ? tab.pwNetwork.security : WifiSecurityType.Unknown
            wrongPassword: Net.attemptWrongPassword
            onSubmitted: (psk, autoconnect) => {
                tab.pendingAutoSsid = autoconnect ? "" : Net.attemptSsid;
                Net.connectWifi(Net.attemptSsid, psk);
            }
        }

        HiddenNetworkSheet {
            id: hiddenSheet
            popup: tab.popup
            open: tab.hiddenOpen
            onJoined: (ssid, psk, autoconnect) => {
                tab.hiddenOpen = false;
                tab.pendingAutoSsid = autoconnect ? "" : ssid;
                Net.connectWifi(ssid, psk);
            }
        }
    }

    NodeStrands {
        host: tab.popup
        nodes: nodeRepeater
        coreWidth: core.width
        lit: tab.active && tab.view === "info" && !tab.coreHidden
    }

    // --- info nodes ---------------------------------------------------------
    Repeater {
        id: nodeRepeater
        model: (tab.active && tab.view === "info") ? tab.infoNodes : []

        delegate: InfoNode {
            id: node
            required property var modelData
            required property int index
            popup: tab.popup

            value: tab.nodeValue(modelData)
            label: tab.nodeLabel(modelData)
            glyph: tab.nodeGlyph(modelData)
            actionable: modelData === "ip" || modelData === "auto" || modelData === "list" || modelData === "forget"
            emphasised: modelData === "auto" && tab.infoAuto
            accentColor: modelData === "forget" ? tab.popup.red : tab.popup.accent
            onTriggered: tab.runInfoAction(modelData)

            readonly property real nodeAngle: tab.slotAngle(index, tab.infoNodes.length)
            readonly property var spot: Orbit.clampIn(Orbit.pos(tab.width, tab.height, node.nodeAngle, tab.popup.s(280), tab.popup.s(180), node.width, node.height), node.width, node.height, tab.width, tab.height)
            x: node.spot.x
            y: node.spot.y

            property real entryAnim: 0.0
            Behavior on entryAnim {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutBack
                }
            }
            entryScale: 0.6 + 0.4 * node.entryAnim
            opacity: node.entryAnim

            Timer {
                interval: 40 + node.index * 30
                running: true
                onTriggered: node.entryAnim = 1.0
            }
        }
    }

    // --- orbiting network cards ---------------------------------------------
    Repeater {
        id: cardRepeater
        model: (tab.active && tab.view !== "info") ? tab.cardModel : []

        delegate: WifiNetworkCard {
            id: wc
            required property var modelData
            required property int index

            popup: tab.popup
            network: modelData
            savedView: tab.savedMode
            baseScale: tab.dynamicScale
            z: wc.hovered ? 10 : index

            // A card destroyed mid-hover would otherwise leave the list locked forever.
            property bool hovered: false
            onHoverChanged: h => {
                wc.hovered = h;
                tab.hoverCount = Math.max(0, tab.hoverCount + (h ? 1 : -1));
            }
            Component.onDestruction: if (wc.hovered)
                tab.hoverCount = Math.max(0, tab.hoverCount - 1)
            // Deferred: dropping it here destroys the delegate mid-signal.
            onForgotten: Qt.callLater(tab.dropCard, wc.network)

            // The stable slot only breaks ties; the angle comes from the live count.
            readonly property int ringPos: {
                var v = tab.ringPos["" + modelData.name];
                return v === undefined ? index : v;
            }
            // Two rings, the odd one pushed out so the cards interleave radially.
            readonly property bool outerRing: (wc.ringPos % 2) === 1
            readonly property real targetSlotAngle: (wc.ringPos / Math.max(1, tab.cardModel.length)) * Math.PI * 2

            // Animate the ANGLE: a Behavior on x/y chasing the per-frame orbit starves.
            property real slotAngle: wc.targetSlotAngle
            Behavior on slotAngle {
                NumberAnimation {
                    duration: 800
                    easing.type: Easing.OutExpo
                }
            }
            readonly property real ringAngle: wc.slotAngle + tab.popup.globalOrbitAngle * 0.15

            readonly property real ringOffset: wc.outerRing ? tab.popup.s(32) : 0
            readonly property real radX: (tab.popup.s(260) + wc.ringOffset) * wc.entryAnim
            readonly property real radY: (tab.popup.s(160) + wc.ringOffset) * wc.entryAnim
            readonly property var spot: Orbit.clampIn(Orbit.pos(tab.width, tab.height, wc.ringAngle, wc.radX, wc.radY, wc.width, wc.height), wc.width, wc.height, tab.width, tab.height)
            x: wc.spot.x
            y: wc.spot.y

            Timer {
                interval: 40 + wc.index * 30
                running: true
                onTriggered: {
                    wc.entryAnim = 1.0;
                    wc.loaded = true;
                }
            }
        }
    }

    // --- empty state --------------------------------------------------------
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tab.popup.s(8)
        visible: tab.view !== "info" && cardRepeater.count === 0
        text: !Net.wifiPresent ? "Plug in a Wi-Fi adapter" : !Net.radioOn ? "Wi-Fi is off" : tab.savedMode ? "No saved networks" : "Scanning for networks…"
        font.family: Fonts.ui
        font.pixelSize: tab.popup.s(11)
        color: tab.popup.overlay0
    }

    // --- tab-local actions --------------------------------------------------
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: tab.popup.s(4)
        spacing: tab.popup.s(6)
        visible: Net.wifiPresent

        NetworkActionButton {
            popup: tab.popup
            glyph: "\u{f00c0}"
            label: tab.savedMode ? "All" : "Saved"
            active: tab.savedMode
            onTriggered: tab.setSaved(!tab.savedMode)
        }
        NetworkActionButton {
            popup: tab.popup
            glyph: "\u{f0209}"
            label: "Hidden…"
            active: tab.hiddenOpen
            enabled: Net.radioOn
            onTriggered: tab.hiddenOpen = !tab.hiddenOpen
        }
    }

    component LoadingDots: Row {
        id: row
        property var pop: null
        property color dotCol: "white"
        spacing: row.pop ? row.pop.s(4) : 4

        Repeater {
            model: 3
            delegate: Rectangle {
                id: dot
                required property int index
                width: row.pop ? row.pop.s(5) : 5
                height: width
                radius: width / 2
                color: row.dotCol

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: row.visible
                    PauseAnimation {
                        duration: dot.index * 100
                    }
                    NumberAnimation {
                        from: 0
                        to: row.pop ? -row.pop.s(5) : -5
                        duration: 250
                        easing.type: Easing.OutSine
                    }
                    NumberAnimation {
                        from: row.pop ? -row.pop.s(5) : -5
                        to: 0
                        duration: 250
                        easing.type: Easing.InSine
                    }
                    PauseAnimation {
                        duration: (2 - dot.index) * 100
                    }
                }
            }
        }
    }
}
