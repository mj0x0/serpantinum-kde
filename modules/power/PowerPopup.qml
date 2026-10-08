// Power panel: the profile at the core, the apps keeping the machine awake orbiting it.
// Serpantinum's orbital chassis, as in BluetoothPopup.

import "../../services/audio"
import "../bluetooth"
import "../components"
import "../../services/keepawake"
import "../../services/layout"
import "../../services/power"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

Item {
    id: window

    // --- Scaling + theme (same idiom as the other popups) -------------------
    Scaler {
        id: scaler
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

    width: s(860)
    height: s(620)

    // --- Profiles -----------------------------------------------------------
    readonly property var profiles: [
        { key: "performance", label: "Performance", glyph: "\u{f04c5}" },   // md-speedometer
        { key: "balanced",    label: "Balanced",    glyph: "\u{f05d1}" },   // md-scale_balance
        { key: "power-saver", label: "Power saver", glyph: "\u{f032a}" }    // md-leaf
    ]
    readonly property var shownProfiles: profiles.filter(
        p => PowerInfo.choices.length === 0 || PowerInfo.choices.indexOf(p.key) !== -1)
    readonly property int profileIndex: {
        for (var i = 0; i < shownProfiles.length; i++)
            if (shownProfiles[i].key === PowerInfo.profile) return i;
        return -1;
    }
    readonly property var currentProfile: profileIndex >= 0 ? shownProfiles[profileIndex] : null

    function cycleProfile() {
        if (!PowerInfo.available || shownProfiles.length === 0) return;
        PowerInfo.setProfile(shownProfiles[(profileIndex + 1) % shownProfiles.length].key);
    }

    // --- Views --- status nodes or the app ring, switched like Bluetooth's info and scan views.
    property bool showApps: false
    Component.onCompleted: showApps = PowerInfo.activeCount > 0

    // Escape steps back from the app ring before it closes the panel.
    function handleEscape() {
        if (!showApps) return false;
        showApps = false;
        return true;
    }

    // Keys while open, as in the music and volume popups: Tab flips the view, Shift+1-3 picks a profile.
    function pickProfile(i) {
        if (PowerInfo.available && i < shownProfiles.length) PowerInfo.setProfile(shownProfiles[i].key);
    }
    Shortcut { sequence: "Tab"; onActivated: window.showApps = !window.showApps }
    Shortcut { sequence: "Shift+1"; onActivated: window.pickProfile(0) }
    Shortcut { sequence: "Shift+2"; onActivated: window.pickProfile(1) }
    Shortcut { sequence: "Shift+3"; onActivated: window.pickProfile(2) }

    readonly property var orbitItems: PowerInfo.inhibitions.slice(0, 8)

    // Fixed compass slots — top, left, right, bottom.
    readonly property var slotAngles: [-Math.PI / 2, Math.PI, 0, Math.PI / 2]
    readonly property var infoNodes: [
        { value: PowerInfo.screenBlocked ? "Kept on" : "Can blank", label: "Screen",
          glyph: PowerInfo.screenBlocked ? "\u{f0379}" : "\u{f0d90}", hot: PowerInfo.screenBlocked, action: "" },
        { value: PowerInfo.sleepBlocked ? "Blocked" : "Allowed", label: "Sleep",
          glyph: PowerInfo.sleepBlocked ? "\u{f04b3}" : "\u{f04b2}", hot: PowerInfo.sleepBlocked, action: "" },
        { value: PowerInfo.degraded !== "" ? PowerInfo.degraded : "None", label: "Throttling",
          glyph: "\u{f050f}", hot: PowerInfo.degraded !== "", action: "" },
        { value: PowerInfo.activeCount + " holding · " + PowerInfo.blockedCount + " blocked", label: "Show apps",
          glyph: "\u{f08c6}", hot: PowerInfo.activeCount > 0, action: "apps" }
    ]

    // --- Ambient + intro (matches the rice's other popups) ------------------
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1; duration: 600; easing.type: Easing.OutExpo; running: true
    }

    // `clip` is a square clip, so the rounded card is a mask.
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
                    text: "\u{f0426}"   // md-power_settings
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(22)
                    color: PowerInfo.available ? window.accent : window.overlay0
                }
                Text {
                    text: "POWER"
                    font.family: Fonts.ui
                    font.weight: Font.Black
                    font.pixelSize: window.s(16)
                    color: window.text
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    visible: window.showApps
                    text: "Click an app to block or allow it · blocks persist"
                    font.family: Fonts.ui
                    font.pixelSize: window.s(10)
                    color: window.overlay0
                    elide: Text.ElideLeft
                }
                Item { Layout.fillWidth: true; visible: !window.showApps }

                // Keep-awake lives here too: it is one more thing holding the machine awake.
                Rectangle {
                    Layout.preferredWidth: window.s(38)
                    Layout.preferredHeight: window.s(38)
                    radius: width / 2
                    color: awakeMa.containsMouse ? Qt.alpha(window.accent, 0.18) : Qt.alpha(window.surface0, 0.85)
                    border.width: 1
                    border.color: KeepAwakeState.active ? Qt.alpha(window.accent, 0.55) : Qt.alpha(window.overlay0, 0.5)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    Text {
                        anchors.centerIn: parent
                        text: KeepAwakeState.active ? "\u{f0176}" : "\u{f0faa}"   // md-coffee / md-coffee_off
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.s(18)
                        color: KeepAwakeState.active ? window.accent : window.overlay0
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    MouseArea {
                        id: awakeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Sounds.playSfx("system/quick_click.wav"); KeepAwakeState.toggle(); }
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

                readonly property real coreSize: window.s(190)

                // Plasma strands from the core to every node or card.
                Canvas {
                    id: nodeLinesCanvas
                    anchors.fill: parent
                    opacity: PowerInfo.available ? 1.0 : 0.0
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

                        var time = Date.now() / 1000;
                        var tWave1 = time * 2.5;
                        var tWave2 = time * -1.5;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";

                        var targets = [];
                        for (var n = 0; n < infoRepeater.count; n++) {
                            var nd = infoRepeater.itemAt(n);
                            if (nd && nd.width > 0) targets.push(nd);
                        }
                        for (var o = 0; o < orbitRepeater.count; o++) {
                            var od = orbitRepeater.itemAt(o);
                            if (od && od.width > 0) targets.push(od);
                        }

                        var startX = width / 2;
                        var startY = height / 2;
                        for (var i = 0; i < targets.length; i++) {
                            var targetX = targets[i].x + targets[i].width / 2;
                            var targetY = targets[i].y + targets[i].height / 2;
                            var dx = targetX - startX;
                            var dy = targetY - startY;
                            var fullDist = Math.sqrt(dx * dx + dy * dy);
                            if (fullDist < S(10)) continue;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);
                            var perpX = -sinA;
                            var perpY = cosA;

                            var startOffset = orbitContainer.coreSize / 2 + S(5);
                            var drawDist = fullDist - startOffset - S(35);
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
                                var off = Math.sin(tWave1 + t * 6) * S(6) * Math.sin(t * Math.PI)
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

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var k = 1; k <= steps; k++) {
                                var tk = k / steps;
                                var offK = Math.cos(tWave2 + tk * 8) * S(12) * Math.sin(tk * Math.PI)
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

                // Faint concentric rings behind the core.
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: orbitContainer.coreSize + window.s(70) * (index + 1)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: window.accent
                        opacity: PowerInfo.available ? (0.06 - index * 0.012) : 0.02
                    }
                }

                // --- Core: the active profile ---
                Rectangle {
                    id: core
                    anchors.centerIn: parent
                    width: orbitContainer.coreSize
                    height: width
                    radius: width / 2
                    color: PowerInfo.available ? window.accent : Qt.alpha(window.surface0, 0.85)
                    border.width: PowerInfo.available ? 0 : 2
                    border.color: Qt.alpha(window.overlay0, 0.6)
                    Behavior on color { ColorAnimation { duration: 400 } }

                    // A knock when the profile changes.
                    property real knock: 1.0
                    scale: knock * (coreMa.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    Timer { id: knockBack; interval: 120; onTriggered: core.knock = 1.0 }
                    Connections {
                        target: PowerInfo
                        function onProfileChanged() { core.knock = 0.9; knockBack.restart(); }
                    }

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
                        opacity: PowerInfo.available ? 0.10 : 0.0
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width * 0.66
                        spacing: window.s(1)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.currentProfile ? window.currentProfile.glyph : "\u{f0426}"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: window.s(32)
                            color: PowerInfo.available ? window.crust : window.overlay0
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: !PowerInfo.available ? "Unavailable"
                                : window.currentProfile ? window.currentProfile.label : PowerInfo.profile
                            elide: Text.ElideRight
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: window.s(15)
                            color: PowerInfo.available ? window.crust : window.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: PowerInfo.available
                            text: PowerInfo.activeCount === 0 ? "Nothing holding"
                                : PowerInfo.activeCount === 1 ? "1 app holding" : PowerInfo.activeCount + " apps holding"
                            font.family: Fonts.ui
                            font.pixelSize: window.s(11)
                            color: Qt.alpha(window.crust, 0.75)
                        }
                    }

                    MouseArea {
                        id: coreMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: PowerInfo.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { Sounds.playSfx("system/quick_click.wav"); window.cycleProfile(); }
                    }
                }

                // --- Status nodes ---
                Repeater {
                    id: infoRepeater
                    // A count, not the array: new data updates nodes in place instead of rebuilding them.
                    model: window.showApps ? 0 : window.infoNodes.length

                    delegate: InfoNode {
                        required property int index
                        readonly property var nd: window.infoNodes[index]
                        popup: window

                        value: nd.value
                        label: nd.label
                        glyph: nd.glyph
                        emphasised: nd.hot
                        actionable: nd.action !== ""
                        onTriggered: if (nd.action === "apps") window.showApps = true

                        readonly property real nodeAngle: window.slotAngles[index]
                        x: Math.max(0, Math.min(orbitContainer.width / 2 + Math.cos(nodeAngle) * window.s(280) - width / 2,
                                                orbitContainer.width - width))
                        y: Math.max(0, Math.min(orbitContainer.height / 2 + Math.sin(nodeAngle) * window.s(180) - height / 2,
                                                orbitContainer.height - height))

                        property real entryAnim: 0.0
                        Component.onCompleted: entryAnim = 1.0
                        Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
                        entryScale: 0.6 + 0.4 * entryAnim
                        opacity: entryAnim
                    }
                }

                // --- App ring ---
                Repeater {
                    id: orbitRepeater
                    // A count too, so toggling an app morphs its card rather than rebuilding it.
                    model: window.showApps ? window.orbitItems.length : 0

                    delegate: InhibitorCard {
                        required property int index
                        inhibition: window.orbitItems[index] || null
                        popup: window

                        // Animate the angle and bind x/y: a Behavior on x/y chasing the rotating ring starves.
                        readonly property real targetSlotAngle: -Math.PI / 2 + (index / Math.max(1, orbitRepeater.count)) * Math.PI * 2
                        property real slotAngle: targetSlotAngle
                        Behavior on slotAngle { NumberAnimation { duration: 600; easing.type: Easing.InOutExpo } }
                        readonly property real ringAngle: slotAngle + window.globalOrbitAngle * 0.15

                        x: Math.max(0, Math.min(orbitContainer.width / 2 + Math.cos(ringAngle) * window.s(300) - width / 2,
                                                orbitContainer.width - width))
                        y: Math.max(0, Math.min(orbitContainer.height / 2 + Math.sin(ringAngle) * window.s(190) - height / 2,
                                                orbitContainer.height - height))

                        property real entryAnim: 0.0
                        Component.onCompleted: entryAnim = 1.0
                        Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
                        opacity: entryAnim
                    }
                }

                // The common case: nothing holds the machine awake.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: window.s(8)
                    visible: window.showApps && orbitRepeater.count === 0
                    text: "No app is keeping this machine awake"
                    font.family: Fonts.ui
                    font.pixelSize: window.s(11)
                    color: window.overlay0
                }
            }

            // --- Footer ----------------------------------------------------
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
                    glyph: "\u{f0379}"   // md-monitor
                    label: "Status"
                    active: !window.showApps
                    onTriggered: window.showApps = false
                }
                BluetoothActionButton {
                    popup: window
                    glyph: "\u{f08c6}"   // md-application
                    label: "Apps"
                    active: window.showApps
                    onTriggered: window.showApps = true
                }

                Item { Layout.fillWidth: true }

                // Serpantinum v2's segmented profile switch.
                Rectangle {
                    id: profileSwitch
                    Layout.preferredWidth: window.s(360)
                    Layout.preferredHeight: window.s(40)
                    radius: Radius.outer(window.s(14))
                    color: Qt.alpha(window.surface1, 0.8)
                    border.width: 1
                    border.color: Qt.alpha(window.overlay0, 0.35)
                    opacity: PowerInfo.available ? 1.0 : 0.4
                    readonly property real seg: width / Math.max(1, window.shownProfiles.length)
                    readonly property real inner: window.s(4)

                    Rectangle {
                        visible: window.profileIndex >= 0
                        x: Math.max(0, window.profileIndex) * profileSwitch.seg
                        width: profileSwitch.seg
                        height: parent.height
                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        readonly property bool first: window.profileIndex === 0
                        readonly property bool last: window.profileIndex === window.shownProfiles.length - 1
                        topLeftRadius: first ? profileSwitch.radius : profileSwitch.inner
                        bottomLeftRadius: first ? profileSwitch.radius : profileSwitch.inner
                        topRightRadius: last ? profileSwitch.radius : profileSwitch.inner
                        bottomRightRadius: last ? profileSwitch.radius : profileSwitch.inner
                        color: window.accent
                    }

                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: window.shownProfiles
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === window.profileIndex
                                width: profileSwitch.seg
                                height: profileSwitch.height

                                Row {
                                    anchors.centerIn: parent
                                    spacing: window.s(6)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.modelData.glyph
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(15)
                                        color: parent.parent.selected ? window.crust : window.subtext0
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.modelData.label
                                        font.family: Fonts.ui
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(11)
                                        color: parent.parent.selected ? window.crust : window.text
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: PowerInfo.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (PowerInfo.available && !parent.selected) { Sounds.playSfx("system/quick_click.wav"); PowerInfo.setProfile(parent.modelData.key); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
