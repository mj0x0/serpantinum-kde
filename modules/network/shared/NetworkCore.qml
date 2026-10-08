// The centre disc every Network tab shares: one of four state plates, scan rings,
// and serpantinum v2's hold-to-disconnect water line.

import "../../../services/audio"
import "../../../services/theme"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: core

    property var popup: null
    property bool powered: true
    property bool connected: false
    property bool busy: false
    property bool absent: false
    property bool scanning: false
    property bool holdEnabled: false
    // A tab lowers this while a sheet is open so the disc stops eating clicks.
    property bool interactive: true
    property string glyph: ""
    property string offGlyph: ""
    property string name: ""
    property string statusText: ""
    property string absentText: ""
    property string offText: ""
    property color accentColor: popup ? popup.accent : "white"

    signal disconnectRequested()
    signal tapped()

    // Sheets and overlays a tab drops on top of the disc.
    default property alias content: overlay.data

    // Exactly one plate at a time; `off` doubles as the idle/disconnected plate and
    // the tab supplies its wording.
    readonly property bool showAbsent: core.absent
    readonly property bool showConnected: !core.absent && core.connected
    readonly property bool showScan: !core.absent && !core.connected && core.powered && core.scanning
    readonly property bool showOff: !core.absent && !core.connected && !core.showScan

    readonly property bool hoverDisconnect: core.holdEnabled && core.connected && !core.busy
                                            && core.interactive && coreMa.containsMouse
    readonly property string liveStatus: core.holdFill > 0.01 ? "Hold…"
                                       : core.busy ? "Disconnecting…" : core.statusText

    readonly property color topColor: {
        if (!core.popup) return "transparent";
        if (core.absent || !core.powered) return core.popup.crust;
        if (core.connected)
            return core.hoverDisconnect
                 ? Qt.tint(Qt.lighter(core.accentColor, 1.15), Qt.alpha(core.popup.red, 0.75))
                 : Qt.lighter(core.accentColor, 1.15);
        return core.popup.surface0;
    }
    readonly property color bottomColor: {
        if (!core.popup) return "transparent";
        if (core.absent || !core.powered) return core.popup.crust;
        if (core.connected)
            return core.hoverDisconnect ? Qt.tint(core.accentColor, Qt.alpha(core.popup.red, 0.75))
                                        : core.accentColor;
        return core.popup.base;
    }

    // Animation-written: NEVER give these a binding, or the first write kills it for good.
    property real holdFill: 0.0
    property real bumpScale: 1.0
    property bool holdConsumed: false

    width: popup ? popup.s(core.connected ? 200 : 160) : 160
    height: width
    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }
    scale: core.bumpScale

    function bump() { coreBump.restart(); }
    onConnectedChanged: coreBump.restart()

    function releaseHold() {
        fillUp.stop();
        if (core.holdFill <= 0) return;
        fillDown.duration = Math.max(1, 1500 * core.holdFill);
        fillDown.start();
    }

    function completeHold() {
        if (!coreMa.pressed) {
            core.holdFill = 0;
            return;
        }
        core.holdConsumed = true;
        flash.opacity = 0.6;
        flashFade.restart();
        coreBump.restart();
        Sounds.playSfx("network/disconnect.wav");
        core.disconnectRequested();
        core.holdFill = 0;
    }

    SequentialAnimation {
        id: coreBump
        running: false
        NumberAnimation { target: core; property: "bumpScale"; to: 1.15; duration: 200; easing.type: Easing.OutBack }
        NumberAnimation { target: core; property: "bumpScale"; to: 1.0; duration: 600; easing.type: Easing.OutQuint }
    }
    NumberAnimation {
        id: fillUp
        target: core; property: "holdFill"; to: 1.0; easing.type: Easing.InSine
        onFinished: core.completeHold()
    }
    NumberAnimation { id: fillDown; target: core; property: "holdFill"; to: 0.0; easing.type: Easing.OutQuad }

    // --- decoration ---------------------------------------------------------

    Rectangle {
        id: pulseRing
        anchors.centerIn: parent
        width: core.width + (core.popup ? core.popup.s(12) : 12)
        height: width
        radius: width / 2
        z: -2
        color: "transparent"
        border.width: core.popup ? core.popup.s(2) : 2
        border.color: (core.hoverDisconnect && core.popup) ? core.popup.red : core.accentColor
        Behavior on border.color { ColorAnimation { duration: 200 } }
        visible: core.showConnected

        // Timer-written opacity/scale: neither may carry a binding.
        Timer {
            interval: 45
            repeat: true
            running: pulseRing.visible
            onTriggered: {
                var t = Date.now() / 1000;
                pulseRing.opacity = 0.3 + Math.sin(t * 2.5) * 0.15;
                pulseRing.scale = 1.02 + Math.cos(t * 3.0) * 0.02;
            }
        }
    }

    Rectangle {
        id: glowRing
        anchors.centerIn: parent
        width: core.width + (core.popup ? core.popup.s(30) : 30)
        height: width
        radius: width / 2
        z: -1
        color: (core.hoverDisconnect && core.popup) ? core.popup.red : core.accentColor
        Behavior on color { ColorAnimation { duration: 200 } }
        opacity: core.showConnected ? (core.hoverDisconnect ? 0.45 : 0.15) : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 400 } }

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: glowRing.visible
            NumberAnimation { from: 1.0; to: 1.1; duration: 2000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.1; to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
        }
    }

    Repeater {
        model: 3
        delegate: Rectangle {
            id: scanRing
            required property int index
            anchors.centerIn: parent
            width: core.width * 0.4
            height: width
            radius: width / 2
            z: -1
            color: "transparent"
            border.width: core.popup ? core.popup.s(2) : 2
            border.color: core.accentColor
            visible: core.showScan

            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: scanRing.visible
                PauseAnimation { duration: scanRing.index * 400 }
                NumberAnimation { from: 1.0; to: 2.5; duration: 2000; easing.type: Easing.OutSine }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: scanRing.visible
                PauseAnimation { duration: scanRing.index * 400 }
                NumberAnimation { from: 0.8; to: 0.0; duration: 2000; easing.type: Easing.OutSine }
            }
        }
    }

    // Shadow as a SIBLING with source:, not layer.enabled - avoids rasterising the disc.
    MultiEffect {
        source: disc
        anchors.fill: disc
        z: -1
        shadowEnabled: true
        shadowColor: "#000000"
        shadowBlur: 1.2
        shadowVerticalOffset: core.popup ? core.popup.s(5) : 5
        shadowOpacity: (core.powered && !core.absent) ? 0.5 : 0.0
        Behavior on shadowOpacity { NumberAnimation { duration: 600 } }
    }

    // --- the disc -----------------------------------------------------------

    Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        border.width: core.popup ? core.popup.s(2) : 2
        border.color: !core.popup ? "transparent"
                    : core.hoverDisconnect ? Qt.tint(Qt.lighter(core.accentColor, 1.1), Qt.alpha(core.popup.red, 0.45))
                    : core.connected ? Qt.lighter(core.accentColor, 1.1)
                    : Qt.alpha(core.popup.overlay0, 0.6)
        Behavior on border.color { ColorAnimation { duration: 300 } }

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: core.topColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            GradientStop {
                position: 1.0
                color: core.bottomColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }

        PlateLabel {
            anchors.centerIn: parent
            width: parent.width * 0.8
            pop: core.popup
            glyph: core.glyph
            title: core.absentText
            fg: core.popup ? core.popup.overlay0 : "white"
            opacity: core.showAbsent ? 0.55 : 0.0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        PlateLabel {
            anchors.centerIn: parent
            width: parent.width * 0.8
            pop: core.popup
            glyph: core.offGlyph
            title: core.offText
            fg: core.popup ? core.popup.overlay0 : "white"
            opacity: core.showOff ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Text {
            id: scanGlyph
            anchors.centerIn: parent
            text: core.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: core.popup ? core.popup.s(40) : 40
            color: core.accentColor
            visible: core.showScan

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: scanGlyph.visible
                NumberAnimation { from: 1.0; to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.5; to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
            }
        }

        CoreLabel {
            anchors.centerIn: parent
            width: parent.width * 0.78
            pop: core.popup
            glyph: core.hoverDisconnect ? core.offGlyph : core.glyph
            title: core.name
            status: core.liveStatus
            fg: core.popup ? core.popup.crust : "white"
            subFg: core.popup ? Qt.alpha(core.popup.crust, 0.75) : "white"
            opacity: core.showConnected ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }

    // --- hold-to-disconnect water line --------------------------------------

    Canvas {
        id: water
        anchors.fill: parent
        opacity: 0.95
        visible: core.holdFill > 0

        property real wavePhase: 0
        NumberAnimation on wavePhase {
            from: 0; to: Math.PI * 2
            duration: 800
            loops: Animation.Infinite
            running: core.holdFill > 0 && core.holdFill < 1
        }
        onWavePhaseChanged: water.requestPaint()

        Connections {
            target: core
            function onHoldFillChanged() { water.requestPaint(); }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            if (core.holdFill <= 0 || !core.popup) return;

            var r = width / 2;
            ctx.save();
            ctx.beginPath();
            ctx.arc(r, r, r, 0, Math.PI * 2);
            ctx.clip();

            var fillY = height * (1 - core.holdFill);
            ctx.beginPath();
            ctx.moveTo(0, fillY);
            if (core.holdFill < 0.99) {
                var waveAmp = core.popup.s(10) * Math.sin(core.holdFill * Math.PI);
                var cp1y = fillY + Math.sin(water.wavePhase) * waveAmp;
                var cp2y = fillY + Math.cos(water.wavePhase + Math.PI) * waveAmp;
                ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
            } else {
                ctx.lineTo(width, fillY);
            }
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();

            var g = ctx.createLinearGradient(0, height, 0, fillY);
            g.addColorStop(0, String(core.popup.crust));
            g.addColorStop(1, String(core.popup.surface2));
            ctx.fillStyle = g;
            ctx.fill();
            ctx.restore();
        }
    }

    // The wording inverts as the water rises: same label, clipped to the water line.
    Item {
        id: clipItem
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        visible: core.holdFill > 0.01 && core.showConnected

        readonly property real clipWaveAmp: core.popup ? core.popup.s(10) * Math.sin(core.holdFill * Math.PI) : 0
        readonly property real clipPhaseOffset: Math.sin(water.wavePhase) - Math.cos(water.wavePhase)
        readonly property real centerOffset: (core.holdFill > 0.01 && core.holdFill < 0.99)
                                           ? 0.375 * clipWaveAmp * clipPhaseOffset : 0
        height: Math.max(0, Math.min(core.height, core.height * core.holdFill + centerOffset))

        CoreLabel {
            id: invertedLabel
            width: core.width * 0.78
            x: (core.width - width) / 2
            y: (core.height / 2) - (height / 2) - (core.height - clipItem.height)
            pop: core.popup
            glyph: core.hoverDisconnect ? core.offGlyph : core.glyph
            title: core.name
            status: core.liveStatus
            fg: core.popup ? core.popup.text : "white"
            subFg: core.popup ? core.popup.overlay0 : "white"
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        radius: width / 2
        color: core.popup ? core.popup.text : "transparent"
        opacity: 0
        NumberAnimation { id: flashFade; target: flash; property: "opacity"; to: 0; duration: 500; easing.type: Easing.OutExpo }
    }

    MouseArea {
        id: coreMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: core.interactive
        cursorShape: (core.holdEnabled && core.connected && !core.busy) ? Qt.PointingHandCursor
                                                                       : Qt.ArrowCursor
        onPressed: {
            if (!core.holdEnabled || !core.connected || core.busy) return;
            core.holdConsumed = false;
            fillDown.stop();
            fillUp.duration = Math.max(1, 800 * (1.0 - core.holdFill));
            fillUp.start();
        }
        onReleased: core.releaseHold()
        onCanceled: core.releaseHold()
        onClicked: if (!core.holdConsumed) core.tapped()
    }

    Item {
        id: overlay
        anchors.fill: parent
        z: 10
    }

    // --- labels -------------------------------------------------------------

    component CoreLabel: ColumnLayout {
        id: lbl
        property var pop: null
        property string glyph: ""
        property string title: ""
        property string status: ""
        property color fg: "white"
        property color subFg: "white"
        spacing: lbl.pop ? lbl.pop.s(1) : 1

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: lbl.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: lbl.pop ? lbl.pop.s(36) : 36
            color: lbl.fg
            Behavior on color { ColorAnimation { duration: 400 } }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: lbl.title
            font.family: Fonts.ui
            font.weight: Font.Black
            font.pixelSize: lbl.pop ? lbl.pop.s(16) : 16
            color: lbl.fg
            Behavior on color { ColorAnimation { duration: 400 } }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: lbl.status
            font.family: Fonts.ui
            font.pixelSize: lbl.pop ? lbl.pop.s(11) : 11
            color: lbl.subFg
        }
    }

    component PlateLabel: ColumnLayout {
        id: plate
        property var pop: null
        property string glyph: ""
        property string title: ""
        property color fg: "white"
        spacing: plate.pop ? plate.pop.s(8) : 8

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: plate.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: plate.pop ? plate.pop.s(40) : 40
            color: plate.fg
            Behavior on color { ColorAnimation { duration: 300 } }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: plate.title
            font.family: Fonts.ui
            font.weight: Font.Bold
            font.pixelSize: plate.pop ? plate.pop.s(13) : 13
            color: plate.fg
        }
    }
}
