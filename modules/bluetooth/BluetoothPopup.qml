// Bluetooth panel: serpantinum's orbital node graph, on Quickshell's native BT module.

import "../../services/audio"
import "../components"
import "../../services/layout"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth

Item {
    id: window

    // --- Scaling + theme (same idiom as the other popups) -------------------
    Scaler {
        id: scaler
        // Both dimensions: getScale() takes min(w/1920, h/1080), so width alone mis-scales.
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color accent:   _theme.blue      // md3 primary
    readonly property color red:      _theme.red
    readonly property color green:    _theme.green

    // Sized for serpantinum's node radii: info nodes sit at radX s(280),
    // device nodes at s(320) — a s(720) card clipped them.
    width: s(860)
    height: s(620)

    // --- Adapter + devices --- multi-adapter machines are normal; prefer the default.
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool adapterReady: adapter !== null && adapter !== undefined
    readonly property bool powered: adapterReady && adapter.enabled
    readonly property bool scanning: adapterReady && adapter.discovering

    // Devices split into connected (the core) and the rest (the orbit).
    readonly property var allDevices: adapterReady && adapter.devices ? adapter.devices.values : []

    readonly property var connectedDevices: {
        var out = [];
        for (var i = 0; i < allDevices.length; i++)
            if (allDevices[i] && allDevices[i].connected) out.push(allDevices[i]);
        return out;
    }
    readonly property var orbitDevices: {
        var out = [];
        for (var i = 0; i < allDevices.length; i++) {
            var d = allDevices[i];
            if (!d || d.connected) continue;
            out.push(d);
        }
        // Paired first, then the rest — mirrors how serpantinum ranks its ring.
        out.sort(function (a, b) {
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            return (a.deviceName || "").localeCompare(b.deviceName || "");
        });
        return out.slice(0, ringSlots);
    }

    // Stable ring slots: address -> slot, so a card keeps its angle as scans churn.
    // 8, not 10: at these radii 10 cards overlap once the 1.06 hover scale applies.
    readonly property int ringSlots: 8
    // Assignment order spreads sparse rings instead of clustering them.
    readonly property var slotOrder: [0, 4, 2, 6, 1, 5, 3, 7]
    property var slotMap: ({})

    onOrbitDevicesChanged: syncSlotMap()
    Component.onCompleted: syncSlotMap()

    function syncSlotMap() {
        var next = {};
        var used = {};
        var waiting = [];
        for (var i = 0; i < orbitDevices.length; i++) {
            var addr = orbitDevices[i].address;
            var cur = slotMap[addr];
            if (cur !== undefined && !used[cur]) {
                next[addr] = cur;
                used[cur] = true;
            } else {
                waiting.push(addr);
            }
        }
        for (var w = 0; w < waiting.length; w++) {
            for (var j = 0; j < slotOrder.length; j++) {
                var sl = slotOrder[j];
                if (!used[sl]) { next[waiting[w]] = sl; used[sl] = true; break; }
            }
        }
        // Fresh object each time: mutating a var property emits no change signal.
        slotMap = next;
    }

    readonly property bool hasCore: connectedDevices.length > 0

    // --- Multi-core --- up to five connected; they orbit and shrink as the count grows.
    readonly property int maxCores: 5
    readonly property var cores: connectedDevices.slice(0, maxCores)
    readonly property int coreCount: cores.length

    property real smoothedCoreCount: coreCount
    Behavior on smoothedCoreCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }
    onCoreCountChanged: smoothedCoreCount = coreCount

    // 0 while a single device is centred, 1 once they spread onto the orbit.
    property real multiShift: coreCount > 1 ? 1 : 0
    Behavior on multiShift { NumberAnimation { duration: 700; easing.type: Easing.InOutExpo } }

    function coreSize() {
        if (!powered) return s(160);
        return s(200) - s(30) * multiShift - s(15) * Math.max(0, smoothedCoreCount - 2);
    }
    // Derived from the SMOOTHED count: the raw value steps and made the ring jump.
    // s(170), not s(180): at s(180) an outward info node hits the container clamp.
    readonly property real coreOrbitX: s(170) + s(20) * Math.max(0, Math.min(1, smoothedCoreCount - 2))
    readonly property real coreOrbitY: s(110) + s(15) * Math.max(0, Math.min(1, smoothedCoreCount - 2))

    // --- Info nodes --- switch views (info / scan ring) rather than drawing both at once.
    property bool showInfoView: true
    onHasCoreChanged: showInfoView = hasCore

    readonly property bool infoMode: powered && hasCore && showInfoView

    // Glyphs lifted from the original: MAC F048B, Battery F0949, Scan F0349.
    function nodesFor(d) {
        var out = [];
        if (!d) return out;
        out.push({ value: d.address || "", label: "MAC Address", glyph: "\u{f048b}" });
        if (d.batteryAvailable)
            out.push({ value: Math.round(d.battery * 100) + "%", label: "Battery", glyph: "\u{f0949}" });
        // `trusted` decides whether BlueZ auto-reconnects; a paired-but-untrusted
        // (or trusted-but-unpaired) device silently drops and nothing else shows it.
        out.push({
            value: !d.paired ? "Not paired" : (d.trusted ? "Trusted" : "Untrusted"),
            label: "Link", glyph: "\u{f0134}", action: "trust", dev: d
        });
        return out;
    }

    // Fixed compass slots — top, left, right, bottom — like the original.
    readonly property var slotAngles: [-Math.PI / 2, Math.PI, 0, Math.PI / 2]

    readonly property var infoNodes: {
        var out = [];
        if (!infoMode) return out;
        // ONE scan node for the panel, centred between cores when several share the orbit.
        out.push({ coreIndex: cores.length > 1 ? -1 : 0, slot: 0, arcIndex: 0, arcCount: 1,
                   value: "Scan Devices", label: "Switch View", glyph: "\u{f0349}",
                   action: "scan", dev: null });
        for (var c = 0; c < cores.length; c++) {
            var ns = nodesFor(cores[c]);
            for (var i = 0; i < ns.length; i++) {
                var n = ns[i];
                out.push({ coreIndex: c, slot: i + 1, arcIndex: i, arcCount: ns.length,
                           value: n.value, label: n.label, glyph: n.glyph,
                           action: n.action || "", dev: n.dev || null });
            }
        }
        return out;
    }

    // Device glyph from BlueZ's `icon` hint (phone / audio-headset / input-mouse …).
    function iconGlyph(d) {
        var i = ("" + (d && d.icon ? d.icon : "")).toLowerCase();
        if (i.indexOf("phone") !== -1)     return "\u{f011c}";
        if (i.indexOf("audio-card") !== -1
            || i.indexOf("headset") !== -1
            || i.indexOf("headphone") !== -1) return "\u{f02cb}";
        if (i.indexOf("audio") !== -1)     return "\u{f057e}";
        if (i.indexOf("input-keyboard") !== -1) return "\u{f030c}";
        if (i.indexOf("input-mouse") !== -1)    return "\u{f037d}";
        if (i.indexOf("input-gaming") !== -1)   return "\u{f0eb5}";
        if (i.indexOf("computer") !== -1)  return "\u{f0322}";
        if (i.indexOf("watch") !== -1)     return "\u{f0b3a}";
        return "\u{f00b1}";   // generic bluetooth
    }

    // --- Ambient + intro (matches the rice's other popups) ------------------
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1; duration: 600; easing.type: Easing.OutExpo; running: true
    }

    // Rounded mask, same fix the Calendar needed: `clip` is a SQUARE clip, so the
    // ambient blobs would bleed into the corners past the rounded border.
    Rectangle {
        id: cardMask
        anchors.fill: parent
        radius: Radius.outer(s(20))
        color: "white"
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain

        Rectangle {
            anchors.fill: parent
            radius: Radius.outer(s(20))
            color: window.base
            border.color: window.surface0
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            // Ambient drifting blobs (serpantinum signature).
            Rectangle {
                width: parent.width * 0.6; height: width; radius: width / 2
                x: (parent.width * 0.5 - width / 2) + Math.cos(window.globalOrbitAngle) * window.s(120)
                y: (parent.height * 0.5 - height / 2) + Math.sin(window.globalOrbitAngle) * window.s(90)
                color: window.accent
                opacity: 0.05
            }

            // --- Header ---------------------------------------------------
            RowLayout {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: window.s(24)
                spacing: window.s(12)

                Text {
                    text: "\u{f00b1}"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(22)
                    color: window.powered ? window.accent : window.overlay0
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                Text {
                    Layout.fillWidth: true
                    text: "BLUETOOTH"
                    font.family: Fonts.ui
                    font.weight: Font.Black
                    font.pixelSize: window.s(16)
                    color: window.text
                }
                // Power control up here: the bottom-right corner already carries the device count.
                Rectangle {
                    id: powerBtn
                    Layout.preferredWidth: window.s(38)
                    Layout.preferredHeight: window.s(38)
                    radius: width / 2
                    color: powerMa.containsMouse ? Qt.alpha(window.accent, 0.18)
                         : Qt.alpha(window.surface0, 0.85)
                    border.width: 1
                    border.color: window.powered ? Qt.alpha(window.accent, 0.55)
                                                 : Qt.alpha(window.overlay0, 0.5)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }
                    opacity: window.adapterReady ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0425}"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.s(18)
                        color: window.powered ? window.accent : window.overlay0
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    MouseArea {
                        id: powerMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: window.adapterReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (window.adapterReady) { Sounds.playSfx(window.adapter.enabled ? "network/power_off.wav" : "network/power_on.wav"); window.adapter.enabled = !window.adapter.enabled; }
                    }
                }
            }

            // --- Orbital graph -------------------------------------------
            Item {
                id: orbitContainer
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.margins: window.s(12)

                // Plasma strands: two waves per link, pinched by sin(t*PI), redrawn every 45ms.
                Canvas {
                    id: nodeLinesCanvas
                    anchors.fill: parent
                    z: 0
                    opacity: window.powered ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 500 } }

                    Timer {
                        interval: 45; repeat: true
                        running: nodeLinesCanvas.opacity > 0.01
                        onTriggered: nodeLinesCanvas.requestPaint()
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        var S = window.s;
                        ctx.clearRect(0, 0, width, height);
                        if (!window.powered) return;

                        var coreSizeFallback = window.coreSize();
                        var time = Date.now() / 1000;
                        var tWave1 = time * 2.5;
                        var tWave2 = time * -1.5;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";

                        // Info nodes hang off their own core; scannable devices radiate from the centre.
                        var links = [];
                        for (var n = 0; n < infoRepeater.count; n++) {
                            var nd = infoRepeater.itemAt(n);
                            if (!nd || nd.width <= 0) continue;
                            links.push({
                                sx: nd.ownerCx, sy: nd.ownerCy, sw: coreSizeFallback,
                                tx: nd.x + nd.width / 2,
                                ty: nd.y + nd.height / 2
                            });
                        }
                        for (var o = 0; o < orbitRepeater.count; o++) {
                            var od = orbitRepeater.itemAt(o);
                            if (!od || od.width <= 0) continue;
                            links.push({
                                sx: width / 2, sy: height / 2, sw: coreSizeFallback,
                                tx: od.x + od.width / 2, ty: od.y + od.height / 2
                            });
                        }

                        for (var i = 0; i < links.length; i++) {
                            var L = links[i];
                            var startX = L.sx;
                            var startY = L.sy;
                            var coreW = L.sw;
                            var targetX = L.tx;
                            var targetY = L.ty;
                            if (targetX < 0 || targetY < 0 || targetX > width || targetY > height) continue;
                            if (startX < 0 || startY < 0 || startX > width || startY > height) continue;

                            var dx = targetX - startX;
                            var dy = targetY - startY;
                            var fullDist = Math.sqrt(dx * dx + dy * dy);
                            if (fullDist < S(10)) continue;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);
                            var perpX = -sinA;
                            var perpY = cosA;

                            var startOffset = coreW / 2 + S(5);
                            var endOffset = S(35);
                            var drawDist = fullDist - startOffset - endOffset;
                            if (drawDist <= 0) continue;

                            var sX = startX + cosA * startOffset;
                            var sY = startY + sinA * startOffset;

                            var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                            var wCore = S(1.0) + (distanceFactor * S(2.0));
                            var wGlow = S(4.0) + (distanceFactor * S(4.0));
                            var a = 0.2 + (distanceFactor * 0.7);
                            var steps = 8;

                            // Strand 1 — drawn twice: soft accent glow, then a bright core.
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
                            ctx.strokeStyle = window.accent;
                            ctx.globalAlpha = a * 0.15;
                            ctx.stroke();

                            ctx.lineWidth = wCore;
                            ctx.strokeStyle = "#ffffff";
                            ctx.globalAlpha = a;
                            ctx.stroke();

                            // Strand 2 — wider, slower, counter-phase.
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
                            ctx.strokeStyle = window.accent;
                            ctx.globalAlpha = a * 0.3;
                            ctx.stroke();
                        }
                        ctx.globalAlpha = 1.0;
                    }
                }

                // Faint concentric rings behind the cores (serpantinum's backdrop).
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: window.coreSize() + window.s(70) * (index + 1)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: window.accent
                        opacity: window.powered ? (0.06 - index * 0.012) : 0.02
                        Behavior on opacity { NumberAnimation { duration: 500 } }
                    }
                }

                // Connected devices. One centred core, or several on their own
                // orbit — each shrinking as the count grows.
                Repeater {
                    id: coreRepeater
                    model: window.powered ? window.cores : []

                    delegate: Rectangle {
                        id: coreItem
                        required property var modelData
                        required property int index

                        // Animate the ANGLE, not x/y - x/y cuts a core straight across the middle.
                        // No -PI/2 offset: two cores then sit on the wide axis, not the short one.
                        readonly property real targetAngle:
                            (index / Math.max(1, window.coreCount)) * Math.PI * 2
                        property real baseAngle: targetAngle
                        Behavior on baseAngle {
                            NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo }
                        }

                        width: window.coreSize()
                        height: width
                        radius: width / 2
                        Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }

                        x: orbitContainer.width / 2 - width / 2
                           + Math.cos(baseAngle) * window.coreOrbitX * window.multiShift
                        y: orbitContainer.height / 2 - height / 2
                           + Math.sin(baseAngle) * window.coreOrbitY * window.multiShift
                        // No Behavior on x/y: every input animates already, and it would straighten the arc.

                        color: window.accent
                        Behavior on color { ColorAnimation { duration: 400 } }

                        // Upstream's `entryAnim`: a core arrives rather than appears.
                        property real entryAnim: 0.0
                        Component.onCompleted: entryAnim = 1.0
                        Behavior on entryAnim {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                        scale: 0.5 + 0.5 * entryAnim
                        opacity: entryAnim

                        // Soft halo.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(24)
                            height: width
                            radius: width / 2
                            z: -1
                            color: "transparent"
                            border.width: window.s(12)
                            border.color: window.accent
                            opacity: 0.10
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width * 0.78
                            spacing: window.s(1)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: window.iconGlyph(coreItem.modelData)
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.max(window.s(18), coreItem.width * 0.19)
                                color: window.crust
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                text: coreItem.modelData.deviceName || "Device"
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: Fonts.ui
                                font.weight: Font.Black
                                font.pixelSize: Math.max(window.s(9), coreItem.width * 0.075)
                                color: window.crust
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Connected"
                                visible: window.coreCount <= 2
                                font.family: Fonts.ui
                                font.pixelSize: window.s(11)
                                color: Qt.alpha(window.crust, 0.75)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // Scan view: click returns to info nodes. Info view: right-click disconnects.
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) { Sounds.playSfx("network/disconnect.wav"); coreItem.modelData.disconnect(); }
                                else if (!window.showInfoView) window.showInfoView = true;
                                else coreItem.modelData.disconnect();
                            }
                        }
                    }
                }

                // Idle core (nothing connected) — keeps the panel from looking empty.
                Rectangle {
                    id: idleCore
                    anchors.centerIn: parent
                    visible: !window.hasCore
                    width: window.coreSize()
                    height: width
                    radius: width / 2
                    color: Qt.alpha(window.surface0, 0.85)
                    border.width: 2
                    border.color: Qt.alpha(window.overlay0, 0.6)

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + window.s(30) * pulse
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: window.accent
                        opacity: window.scanning ? 0.55 * (1 - pulse) : 0
                        property real pulse: 0
                        NumberAnimation on pulse {
                            from: 0; to: 1; duration: 1600
                            loops: Animation.Infinite
                            running: window.scanning
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: window.s(1)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\u{f00b1}"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: window.s(38)
                            color: window.overlay0
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.powered ? "Not connected" : "Bluetooth off"
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: window.s(15)
                            color: window.text
                        }
                    }
                }

                // Info nodes — each belongs to a core and is laid out around it.
                Repeater {
                    id: infoRepeater
                    model: window.infoNodes

                    delegate: InfoNode {
                        required property var modelData
                        popup: window

                        value: modelData.value
                        label: modelData.label
                        glyph: modelData.glyph
                        actionable: modelData.action !== ""
                        onTriggered: {
                            if (modelData.action === "trust" && modelData.dev)
                                modelData.dev.trusted = !modelData.dev.trusted;
                            else if (modelData.action === "scan") {
                                window.showInfoView = false;
                                if (window.powered && !window.adapter.discovering)
                                    window.adapter.discovering = true;
                            }
                        }

                        // Same math the core uses - never coreRepeater.itemAt(): a method call tracks no
                        // dependencies, so it evaluates once (null) and every fan collapses to the centre.
                        readonly property bool hasOwner: modelData.coreIndex >= 0
                        readonly property real ownerAngle: hasOwner
                            ? (modelData.coreIndex / Math.max(1, window.coreCount)) * Math.PI * 2
                            : 0
                        readonly property real ownerCx: orbitContainer.width / 2
                            + (hasOwner ? Math.cos(ownerAngle) * window.coreOrbitX * window.multiShift : 0)
                        readonly property real ownerCy: orbitContainer.height / 2
                            + (hasOwner ? Math.sin(ownerAngle) * window.coreOrbitY * window.multiShift : 0)

                        // One core: fixed compass slots. Several: each fans its nodes across an outward
                        // arc on its own orbit angle. A full PI, not 0.8, or edge nodes sit 18 degrees off.
                        readonly property real arcOffset: modelData.arcCount > 1
                            ? ((modelData.arcIndex / (modelData.arcCount - 1)) - 0.5) * Math.PI
                            : 0
                        readonly property real nodeAngle: window.coreCount > 1
                            ? ownerAngle + arcOffset
                            : window.slotAngles[modelData.slot % 4]

                        // Interpolate on the smoothed count so the ring contracts; the scan node sits at 0.
                        readonly property real tightness: Math.max(0, Math.min(1, window.smoothedCoreCount - 1))
                        readonly property real spread: Math.max(0, Math.min(1, window.smoothedCoreCount - 2))
                        readonly property real radX: modelData.coreIndex < 0 ? 0
                                                     : window.s(280)
                                                     + (window.s(160) - window.s(280)) * tightness
                                                     + window.s(20) * spread
                        readonly property real radY: modelData.coreIndex < 0 ? 0
                                                     : window.s(180)
                                                     + (window.s(160) - window.s(180)) * tightness
                                                     + window.s(20) * spread

                        property real rawX: ownerCx + Math.cos(nodeAngle) * radX - width / 2
                        property real rawY: ownerCy + Math.sin(nodeAngle) * radY - height / 2
                        x: Math.max(0, Math.min(rawX, orbitContainer.width - width))
                        y: Math.max(0, Math.min(rawY, orbitContainer.height - height))

                        property bool placed: false
                        Component.onCompleted: { placed = true; entryAnim = 1.0; }
                        Behavior on x { enabled: placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                        Behavior on y { enabled: placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                        // Upstream's dynamicScale: nodes shrink as cores multiply.
                        readonly property real shrink: window.coreCount > 2 ? 0.7
                                                     : window.coreCount > 1 ? 0.8 : 1.0

                        property real entryAnim: 0.0
                        Behavior on entryAnim {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                        entryScale: (0.6 + 0.4 * entryAnim) * shrink
                        opacity: entryAnim
                    }
                }

                // Orbiting devices.
                Repeater {
                    id: orbitRepeater
                    model: (window.powered && !window.infoMode) ? window.orbitDevices : []

                    delegate: BluetoothDeviceCard {
                        required property var modelData
                        required property int index

                        device: modelData
                        popup: window

                        // Angle comes from the device's STABLE slot, not its index, so
                        // the ring doesn't reshuffle every time a scan result changes.
                        readonly property int slot: {
                            var v = window.slotMap[modelData.address];
                            return v === undefined ? index : v;
                        }
                        // Animate the ANGLE and bind x/y: a Behavior on x/y chasing the rotating ring
                        // retargets every frame and starves, freezing the cards one frame out of place.
                        readonly property real targetSlotAngle: (slot / window.ringSlots) * Math.PI * 2
                        property real slotAngle: targetSlotAngle
                        Behavior on slotAngle {
                            NumberAnimation { duration: 600; easing.type: Easing.InOutExpo }
                        }
                        readonly property real ringAngle: slotAngle + window.globalOrbitAngle * 0.15
                        property real radX: window.s(320)
                        property real radY: window.s(200)

                        // Clamped into the container, or the connector Canvas draws a line out of the widget.
                        property real rawX: orbitContainer.width / 2 + Math.cos(ringAngle) * radX - width / 2
                        property real rawY: orbitContainer.height / 2 + Math.sin(ringAngle) * radY - height / 2
                        x: Math.max(0, Math.min(rawX, orbitContainer.width - width))
                        y: Math.max(0, Math.min(rawY, orbitContainer.height - height))

                        property real entryAnim: 0.0
                        Component.onCompleted: entryAnim = 1.0
                        Behavior on entryAnim {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                        opacity: entryAnim
                    }
                }

                // Empty state.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: window.s(8)
                    visible: window.powered && !window.infoMode && orbitRepeater.count === 0
                    text: window.scanning ? "Scanning..." : "No devices found - press Scan"
                    font.family: Fonts.ui
                    font.pixelSize: window.s(11)
                    color: window.overlay0
                }
            }

            // --- Footer controls -----------------------------------------
            RowLayout {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: window.s(20)
                height: window.s(40)
                spacing: window.s(10)

                BluetoothActionButton {
                    popup: window
                    // Hidden in info view — the "Scan Devices" node covers that case,
                    // and two controls labelled Scan on one panel is just confusing.
                    visible: !window.infoMode
                    glyph: "\u{f0349}"
                    label: window.scanning ? "Stop" : "Scan"
                    active: window.scanning
                    enabled: window.powered
                    onTriggered: if (window.powered) window.adapter.discovering = !window.adapter.discovering
                }
                BluetoothActionButton {
                    popup: window
                    glyph: "\u{f06d0}"
                    label: "Visible"
                    active: window.adapterReady && window.adapter.discoverable
                    enabled: window.powered
                    onTriggered: if (window.powered) window.adapter.discoverable = !window.adapter.discoverable
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: window.allDevices.length + " known"
                    font.family: Fonts.ui
                    font.pixelSize: window.s(10)
                    color: window.overlay0
                }
            }
        }
    }
}
