// Ethernet tab: a pinned core and a fixed ring of info nodes — no scan, no card list.
// The header "power" button is a connect/disconnect toggle for the wired device, not a radio.

import "shared"
import "../components"
import "../../services/audio"
import "../../services/network"
import QtQuick
import Quickshell
import Quickshell.Networking
import "../../services/network/Profiles.js" as Profiles
import "../../services/layout/Orbit.js" as Orbit

Item {
    id: tab

    property var popup: null
    property bool active: false

    // --- tab contract -------------------------------------------------------
    readonly property string headerGlyph: Net.ethLink ? "\u{f0200}" : "\u{f0202}"
    readonly property bool headerLit: Net.ethConnected
    readonly property string headerStatus: Net.wiredDevice ? ("" + Net.wiredDevice.name) : "No wired device"
    readonly property string footerText: Net.ethSpeed > 0 ? (Net.ethSpeed + " Mbps") : ""
    readonly property bool textFocus: false

    readonly property bool hasPower: true
    readonly property string powerGlyph: "\u{f0425}"
    readonly property bool powerOn: Net.ethConnected
    readonly property bool powerEnabled: Net.wiredPresent && Net.ethLink

    function togglePower() {
        Sounds.playSfx(Net.ethConnected ? "network/power_off.wav" : "network/power_on.wav");
        if (Net.ethConnected)
            Net.disconnectWired();
        else
            Net.connectWired();
    }

    // --- device state -------------------------------------------------------
    // WiredDevice.network is null whenever hasLink is false; every read below guards.
    readonly property var wiredNet: Net.wiredDevice ? Net.wiredDevice.network : null
    readonly property int profileCount: (tab.wiredNet && tab.wiredNet.nmSettings) ? tab.wiredNet.nmSettings.length : 0
    readonly property int devState: Net.wiredDevice ? Net.wiredDevice.state : ConnectionState.Unknown
    readonly property bool ethBusy: tab.devState === ConnectionState.Connecting || tab.devState === ConnectionState.Disconnecting
    readonly property bool nicAuto: Net.wiredDevice ? Net.wiredDevice.autoconnect === true : false

    // NMSettings.read() is a synchronous cache read, not a property, so it is polled
    // rather than bound: nothing notifies QML when NM updates the stored profile.
    property bool profileAuto: true
    property string profileName: ""

    function refreshProfile() {
        var net = tab.wiredNet;
        tab.profileAuto = net ? Profiles.autoconnect(net) : true;
        tab.profileName = net ? Profiles.profileId(net, 0) : "";
    }
    onProfileCountChanged: tab.refreshProfile()
    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: tab.active && Net.wiredPresent
        onTriggered: tab.refreshProfile()
    }
    Timer {
        id: profileSettle
        interval: 600
        onTriggered: tab.refreshProfile()
    }

    function toggleProfileAuto() {
        var net = tab.wiredNet;
        if (!net || tab.profileCount === 0)
            return;
        var next = !tab.profileAuto;
        if (!Profiles.setAutoconnect(net, next))
            return;
        tab.profileAuto = next;
        Sounds.playSfx("network/switch.wav");
        profileSettle.restart();
    }

    function toggleNicAuto() {
        if (!Net.wiredDevice)
            return;
        Sounds.playSfx("network/switch.wav");
        Net.wiredDevice.autoconnect = !tab.nicAuto;
    }

    // --- info nodes ---------------------------------------------------------
    // Keys only: values live in the delegate bindings, so a changing IP or speed
    // never rebuilds the ring and restarts its entry animation.
    readonly property var ethNodes: {
        if (!Net.wiredPresent)
            return [];
        var n = [];
        if (Net.showIp && Net.ethConnected)
            n.push("ip");
        n.push("mac");
        n.push("speed");
        if (tab.wiredNet)
            n.push("autoconn");
        n.push("nicauto");
        if (tab.wiredNet)
            n.push("profile");
        n.push("state");
        return n;
    }

    function nodeGlyph(k) {
        if (k === "ip")
            return "\u{f0a5f}";
        if (k === "mac")
            return "\u{f048b}";
        if (k === "speed")
            return "\u{f04c5}";
        if (k === "autoconn")
            return "\u{f18f2}";
        if (k === "nicauto")
            return "\u{f0318}";
        if (k === "profile")
            return "\u{f0493}";
        return "\u{f0318}";
    }

    function nodeLabel(k) {
        if (k === "ip")
            return "IP Address";
        if (k === "mac")
            return "MAC Address";
        if (k === "speed")
            return "Link Speed";
        if (k === "autoconn")
            return "Connect Automatically";
        // NM's Device.Autoconnect, NOT the per-profile flag above it.
        if (k === "nicauto")
            return "Auto-activate NIC";
        if (k === "profile")
            return "Profile";
        return "State";
    }

    function nodeValue(k) {
        if (k === "ip")
            return Net.ethIp !== "" ? Net.ethIp : "Unknown";
        if (k === "mac")
            return (Net.wiredDevice && Net.wiredDevice.address) ? ("" + Net.wiredDevice.address) : "Unknown";
        if (k === "speed")
            return Net.ethSpeed > 0 ? (Net.ethSpeed + " Mbps") : "Unknown";
        if (k === "autoconn")
            return tab.profileCount === 0 ? "—" : (tab.profileAuto ? "On" : "Off");
        if (k === "nicauto")
            return tab.nicAuto ? "On" : "Off";
        if (k === "profile")
            return tab.profileName !== "" ? tab.profileName : "None";
        return Net.wiredDevice ? ConnectionState.toString(Net.wiredDevice.state) : "Unknown";
    }

    function nodeActionable(k) {
        if (k === "ip")
            return Net.ethIp !== "";
        if (k === "autoconn")
            return tab.profileCount > 0;
        if (k === "nicauto")
            return Net.wiredPresent;
        return false;
    }

    function activateNode(k) {
        if (k === "ip")
            tab.copyValue(Net.ethIp, "ip");
        else if (k === "autoconn")
            tab.toggleProfileAuto();
        else if (k === "nicauto")
            tab.toggleNicAuto();
    }

    property string copiedLabel: ""
    Timer {
        id: copiedReset
        interval: 1400
        onTriggered: tab.copiedLabel = ""
    }
    function copyValue(text, key) {
        if (!text || ("" + text).length === 0)
            return;
        Quickshell.execDetached(["wl-copy", "" + text]);
        tab.copiedLabel = key;
        copiedReset.restart();
    }

    // Evenly spread from the top: eight fixed slots left a hole whenever a node was absent.
    function slotAngle(i, count) {
        return -Math.PI / 2 + (i / Math.max(1, count)) * Math.PI * 2;
    }
    readonly property real radX: tab.popup ? tab.popup.s(280) : 280
    readonly property real radY: tab.popup ? tab.popup.s(180) : 180
    readonly property real stepX: tab.popup ? tab.popup.s(6) : 6
    readonly property real stepY: tab.popup ? tab.popup.s(4) : 4

    // The ring widens with what it holds, smoothed so the conditional IP and profile
    // nodes appearing reflows it instead of snapping every node a slot over.
    // While the eased count runs, the nodes ride it directly: a Behavior on x/y chasing a
    // per-frame value retargets every frame and stalls.
    property bool countSettling: false
    onEthNodesChanged: {
        tab.countSettling = true;
        settleTimer.restart();
    }
    Timer {
        id: settleTimer
        interval: 1050
        onTriggered: tab.countSettling = false
    }

    property real smoothedNodeCount: tab.ethNodes.length
    Behavior on smoothedNodeCount {
        NumberAnimation {
            duration: 1000
            easing.type: Easing.InOutExpo
        }
    }

    // --- ambience -----------------------------------------------------------
    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            anchors.centerIn: parent
            width: ethCore.width + tab.popup.s(70) * (index + 1)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: tab.popup.accent
            opacity: (tab.active && Net.ethConnected) ? (0.06 - index * 0.012) : 0.02
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
        id: ethCore
        anchors.centerIn: parent
        opacity: tab.coreHidden ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
        popup: tab.popup

        absent: Net.ready && !Net.wiredPresent
        powered: Net.ethLink
        connected: Net.ethConnected
        busy: tab.ethBusy
        holdEnabled: true

        glyph: Net.wiredPresent ? "\u{f0200}" : "\u{f0202}"
        offGlyph: "\u{f0202}"
        name: Net.wiredDevice ? ("" + Net.wiredDevice.name) : ""
        statusText: "Connected"
        absentText: "No wired device"
        offText: !Net.ready ? "Checking…" : (Net.ethLink ? "Disconnected" : "Cable unplugged")

        onDisconnectRequested: Net.disconnectWired()
        // The disc is the large target for the same action the header button offers.
        onTapped: if (tab.powerEnabled && !Net.ethConnected)
            tab.togglePower()
    }

    NodeStrands {
        host: tab.popup
        nodes: nodeRepeater
        coreWidth: ethCore.width
        lit: tab.active && Net.wiredPresent && !tab.coreHidden
    }

    Repeater {
        id: nodeRepeater
        model: tab.ethNodes

        delegate: InfoNode {
            id: node
            required property var modelData
            required property int index
            popup: tab.popup

            glyph: tab.nodeGlyph(modelData)
            value: tab.nodeValue(modelData)
            label: tab.copiedLabel === modelData ? "Copied!" : tab.nodeLabel(modelData)
            actionable: tab.nodeActionable(modelData)
            emphasised: modelData === "ip"
            onTriggered: tab.activateNode(modelData)

            readonly property real nodeAngle: tab.slotAngle(index, tab.smoothedNodeCount)
            readonly property var radii: Orbit.ringRadii({
                x: tab.radX,
                y: tab.radY
            }, 0, tab.smoothedNodeCount, {
                x: tab.stepX,
                y: tab.stepY
            })
            readonly property var spot: Orbit.clampIn(Orbit.pos(tab.width, tab.height, node.nodeAngle, node.radii.x, node.radii.y, node.width, node.height), node.width, node.height, tab.width, tab.height)
            x: node.spot.x
            y: node.spot.y

            property bool placed: false
            Component.onCompleted: node.placed = true
            Behavior on x {
                enabled: node.placed && !tab.countSettling
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutQuint
                }
            }
            Behavior on y {
                enabled: node.placed && !tab.countSettling
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutQuint
                }
            }

            // Animation-written, so it carries no binding; the stagger is v2's Ethernet timing.
            property real entryAnim: 0.0
            SequentialAnimation on entryAnim {
                running: true
                PauseAnimation {
                    duration: 400 + 60 * node.index
                }
                NumberAnimation {
                    from: 0.0
                    to: 1.0
                    duration: 600
                    easing.type: Easing.OutBack
                }
            }
            entryScale: 0.6 + 0.4 * node.entryAnim
            opacity: node.entryAnim
        }
    }
}
