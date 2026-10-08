// VPN tab: the plasma-strand orbit, lifted out of NetworkPopup unchanged.
// All VPN data is LOCAL (helpers/vpn-info.sh): routing and DNS answer it on-box, and
// Quickshell.Networking cannot see tunnel devices at all (DeviceType is None/Wifi/Wired).

import "shared"
import "../components"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../services/layout/Orbit.js" as Orbit

Item {
    id: tab

    property var popup: null
    property bool active: false

    // --- tab contract -------------------------------------------------------
    readonly property string headerGlyph: "\u{f0582}"
    readonly property bool headerLit: tab.vpnUp
    readonly property string headerStatus: tab.vpnUp ? tab.titleCase(tab.vpn.type || "") : ""
    readonly property string footerText: tab.vpnUp
        ? (tab.fmtBytes(tab.vpn.rx) + " ↓  " + tab.fmtBytes(tab.vpn.tx) + " ↑") : ""
    readonly property bool textFocus: false
    readonly property bool hasPower: false

    // --- VPN state ----------------------------------------------------------
    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"
    property var vpn: ({ up: false })
    readonly property bool vpnUp: vpn.up === true

    Process {
        id: vpnFetcher
        command: ["bash", tab.helpersDir + "/vpn-info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { tab.vpn = JSON.parse((this.text || "").trim() || '{"up":false}'); }
                catch (e) { tab.vpn = ({ up: false }); }
            }
        }
    }
    function refreshVpn() { vpnFetcher.running = false; vpnFetcher.running = true; }
    Timer {
        interval: 5000; repeat: true; running: tab.active; triggeredOnStart: true
        onTriggered: tab.refreshVpn()
    }

    function titleCase(t) {
        return t.length === 0 ? "" : t.charAt(0).toUpperCase() + t.slice(1);
    }

    function fmtBytes(b) {
        if (!b || b <= 0) return "0 B";
        var u = ["B", "KB", "MB", "GB", "TB"], i = 0, v = b;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }
    function fmtSince(ts) {
        if (!ts || ts <= 0) return "unknown";
        var secs = Math.max(0, Math.floor(Date.now() / 1000) - ts);
        var d = Math.floor(secs / 86400), h = Math.floor((secs % 86400) / 3600),
            m = Math.floor((secs % 3600) / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // Info nodes for the tunnel. Kill switch and DNS lead: they're the two things
    // that silently protect you and are invisible everywhere else in the desktop.
    readonly property var vpnNodes: {
        if (!vpnUp) return [];
        var v = tab.vpn;
        return [
            { value: v.killswitch ? "On" : "Off", label: "Kill Switch",
              glyph: "\u{f0483}", good: v.killswitch === true },
            { value: v.dns || "unknown", label: "Tunnel DNS",
              glyph: "\u{f1063}", good: (v.dns || "") !== "" },
            { value: v.routed ? (v.fullTunnel ? "All traffic" : "Split") : "BYPASSED",
              label: "Routing", glyph: "\u{f0641}", good: v.routed === true },
            { value: v.endpoint || "unknown", label: "Endpoint", glyph: "\u{f06f3}" },
            // None is the normal case (P2P servers only), so it is not flagged. Click copies it.
            { value: v.port ? v.port : "None", label: "Forwarded Port",
              glyph: "\u{f0200}", copy: v.port ? ("" + v.port) : "" },
            // WireGuard shrinks MTU below 1500 for its headers; a wrong value here
            // is the usual cause of "some sites hang while others are fine".
            { value: v.mtu ? v.mtu : "unknown", label: "Tunnel MTU", glyph: "\u{f0a0c}" },
            { value: v.addr || "unknown", label: "Tunnel IP", glyph: "\u{f0a5f}" },
            { value: tab.fmtSince(v.since), label: "Connected", glyph: "\u{f0954}" }
        ];
    }

    // Off-state drift: the ring expands so state reads in the LAYOUT, not only in colour.
    // NOT readonly - a Behavior animates by WRITING, and readonly fails the whole file.
    property real vpnDrift: vpnUp ? 0 : (popup ? popup.s(34) : 34)
    Behavior on vpnDrift { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

    // Their `smoothedActiveCoreCount` idea: the ring grows with how much it holds,
    // interpolated so adding or losing a node reflows instead of jumping.
    readonly property int nodeCount: vpnNodes.length
    property real smoothedNodeCount: nodeCount
    Behavior on smoothedNodeCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    // Evenly spread from the top, so a node count under eight leaves no hole in the ring.
    function slotAngle(i, count) {
        return -Math.PI / 2 + (i / Math.max(1, count)) * Math.PI * 2;
    }

    // Brief "Copied!" feedback on the node that was clicked.
    property string copiedLabel: ""
    Timer { id: copiedReset; interval: 1400; onTriggered: tab.copiedLabel = "" }
    function copyValue(text, label) {
        if (!text || text === "None" || text === "unknown")
            return;
        Quickshell.execDetached(["wl-copy", "" + text]);
        tab.copiedLabel = label;
        copiedReset.restart();
    }

    // Plasma strands, same as the Bluetooth panel.
    Canvas {
        id: nodeLinesCanvas
        anchors.fill: parent
        z: 0
        opacity: (tab.active && tab.vpnUp) ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 500 } }

        Timer {
            interval: 45; repeat: true
            running: nodeLinesCanvas.opacity > 0.01
            onTriggered: nodeLinesCanvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d");
            var S = tab.popup.s;
            ctx.clearRect(0, 0, width, height);
            if (!tab.active || !tab.vpnUp) return;

            var time = Date.now() / 1000;
            var tWave1 = time * 2.5;
            var tWave2 = time * -1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            var startX = width / 2, startY = height / 2;
            var coreW = vpnCore.width;

            for (var i = 0; i < nodeRepeater.count; i++) {
                var item = nodeRepeater.itemAt(i);
                if (!item || item.width <= 0) continue;
                var targetX = item.x + item.width / 2;
                var targetY = item.y + item.height / 2;
                if (targetX < 0 || targetY < 0 || targetX > width || targetY > height) continue;

                var dx = targetX - startX, dy = targetY - startY;
                var fullDist = Math.sqrt(dx * dx + dy * dy);
                if (fullDist < S(10)) continue;

                var alpha = Math.atan2(dy, dx);
                var cosA = Math.cos(alpha), sinA = Math.sin(alpha);
                var perpX = -sinA, perpY = cosA;
                var startOffset = coreW / 2 + S(5), endOffset = S(35);
                var drawDist = fullDist - startOffset - endOffset;
                if (drawDist <= 0) continue;

                var sX = startX + cosA * startOffset;
                var sY = startY + sinA * startOffset;
                var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                var wCore = S(1.0) + (distanceFactor * S(2.0));
                var wGlow = S(4.0) + (distanceFactor * S(4.0));
                var a = 0.2 + (distanceFactor * 0.7);
                var steps = 8;

                ctx.beginPath();
                ctx.moveTo(sX, sY);
                for (var j = 1; j <= steps; j++) {
                    var t = j / steps;
                    var env = Math.sin(t * Math.PI);
                    var off = Math.sin(tWave1 + t * 6) * S(6) * env
                            + ((Math.random() - 0.5) * S(5.0) * distanceFactor);
                    ctx.lineTo(sX + cosA * drawDist * t + perpX * off,
                               sY + sinA * drawDist * t + perpY * off);
                }
                ctx.lineWidth = wGlow;
                ctx.strokeStyle = tab.popup.accent;
                ctx.globalAlpha = a * 0.15;
                ctx.stroke();
                ctx.lineWidth = wCore;
                ctx.strokeStyle = "#ffffff";
                ctx.globalAlpha = a;
                ctx.stroke();

                ctx.beginPath();
                ctx.moveTo(sX, sY);
                for (var k = 1; k <= steps; k++) {
                    var tk = k / steps;
                    var envK = Math.sin(tk * Math.PI);
                    var offK = Math.cos(tWave2 + tk * 8) * S(12) * envK
                             + ((Math.random() - 0.5) * S(3.0) * distanceFactor);
                    ctx.lineTo(sX + cosA * drawDist * tk + perpX * offK,
                               sY + sinA * drawDist * tk + perpY * offK);
                }
                ctx.lineWidth = wCore * 1.5;
                ctx.strokeStyle = tab.popup.accent;
                ctx.globalAlpha = a * 0.3;
                ctx.stroke();
            }
            ctx.globalAlpha = 1.0;
        }
    }

    // Concentric backdrop rings.
    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            anchors.centerIn: parent
            width: vpnCore.width + tab.popup.s(70) * (index + 1)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: tab.popup.accent
            opacity: (tab.active && tab.vpnUp) ? (0.06 - index * 0.012) : 0.02
            Behavior on opacity { NumberAnimation { duration: 500 } }
        }
    }

    // --- VPN core -----------------------------------------------------------
    NetworkCore {
        id: vpnCore
        anchors.centerIn: parent
        popup: tab.popup

        connected: tab.vpnUp
        powered: true
        scanning: false
        holdEnabled: false
        interactive: false
        width: tab.popup.s(tab.vpnUp ? 200 : 160)

        glyph: "\u{f0582}"          // shield-lock
        offGlyph: "\u{f0582}"
        name: tab.vpnUp ? ((tab.vpn.country || "VPN") + " #" + (tab.vpn.server || "?")) : "No VPN"
        statusText: "Connected"
        offText: "Not connected"
    }

    // --- VPN info nodes -----------------------------------------------------
    Repeater {
        id: nodeRepeater
        // Built only once the tab has a size: laid out at zero width every node lands on
        // the origin, then visibly flies to its slot on the first open.
        model: (tab.width > 0 && tab.height > 0) ? tab.vpnNodes : []

        delegate: InfoNode {
            id: node
            required property var modelData
            required property int index
            popup: tab.popup

            value: modelData.value
            label: tab.copiedLabel === modelData.label ? "Copied!" : modelData.label
            glyph: modelData.glyph
            actionable: (modelData.copy || "") !== ""
            onTriggered: tab.copyValue(modelData.copy, modelData.label)
            // "Routing: BYPASSED" or a missing kill switch is the one
            // thing worth shouting about, so bad states go red.
            accentColor: (modelData.good === false) ? tab.popup.red : tab.popup.accent
            emphasised: modelData.good !== undefined

            readonly property real nodeAngle: tab.slotAngle(index, tab.nodeCount)

            // Radii follow the smoothed count and the drift, so the ring reflows rather than snaps.
            readonly property var radii: Orbit.ringRadii({ x: tab.popup.s(280), y: tab.popup.s(180) },
                                                         tab.vpnDrift, tab.smoothedNodeCount,
                                                         { x: tab.popup.s(6), y: tab.popup.s(4) })
            readonly property var spot: Orbit.clampIn(
                Orbit.pos(tab.width, tab.height, node.nodeAngle, node.radii.x, node.radii.y,
                          node.width, node.height),
                node.width, node.height, tab.width, tab.height)
            x: node.spot.x
            y: node.spot.y

            // Safe here ONLY because the slot angles are fixed; never do this on a spinning ring.
            property bool placed: false
            Component.onCompleted: { placed = true; entryAnim = 1.0; }
            Behavior on x { enabled: node.placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
            Behavior on y { enabled: node.placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

            // Nodes scale in from nothing; OutBack overshoots so it reads as arriving.
            property real entryAnim: 0.0
            Behavior on entryAnim {
                NumberAnimation { duration: 600; easing.type: Easing.OutBack }
            }
            entryScale: 0.6 + 0.4 * entryAnim
            opacity: entryAnim
        }
    }
}
