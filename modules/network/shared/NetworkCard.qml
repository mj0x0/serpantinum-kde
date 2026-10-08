// One orbiting network pill: v2's 600ms fill button. Hold to act — the accent sweeps
// across and the label re-draws in crust inside the filled region. Right click forgets.

import "../../../services/audio"
import "../../../services/layout"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts

Item {
    id: card

    property var popup: null
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool emphasised: false
    property bool busy: false
    property bool forgettable: false
    // Optional trailing badge (e.g. autoconnect) with its own click.
    property string pip: ""
    property bool pipOn: false
    property int fillDuration: 600

    signal triggered()
    signal forgetRequested()
    signal pipToggled()
    signal hoverChanged(bool hovered)

    // The caller multiplies this into the orbit radii so cards fly out from the centre.
    property real entryAnim: 0.0
    Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
    // Step values only: a Behavior chasing a per-frame value would starve.
    property bool loaded: false
    property real baseScale: 1.0

    // Animation-written: NEVER give these a binding.
    property real holdFill: 0.0
    property real popScale: 1.0
    property real marqueeX: 0
    property bool holdConsumed: false

    readonly property real marqueeStep: baseBody.titleWidth + (card.popup ? card.popup.s(30) : 30)
    readonly property bool marqueeOn: baseBody.titleRoom > 0 && baseBody.titleWidth > baseBody.titleRoom

    // ORBIT: bind x/y as plain expressions and animate the slot ANGLE instead — a
    // Behavior chasing a per-frame orbit angle retargets every frame and freezes.
    width: popup ? popup.s(150) : 150
    height: popup ? popup.s(52) : 52

    scale: (!card.loaded ? 0.0 : (cardMa.containsMouse ? card.baseScale * 1.025 : card.baseScale))
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

    function releaseHold() {
        fillUp.stop();
        if (card.holdFill <= 0) return;
        fillDown.duration = Math.max(1, card.fillDuration * 1.875 * card.holdFill);
        fillDown.start();
    }

    function completeHold() {
        if (!cardMa.pressed) {
            card.holdFill = 0;
            return;
        }
        card.holdConsumed = true;
        fillFlash.opacity = 0.5;
        flashFade.restart();
        popAnim.restart();
        Sounds.playSfx("reusables/fillbutton/button.wav");
        card.triggered();
        card.holdFill = 0;
    }

    NumberAnimation {
        id: fillUp
        target: card; property: "holdFill"; to: 1.0; easing.type: Easing.InSine
        onFinished: card.completeHold()
    }
    NumberAnimation { id: fillDown; target: card; property: "holdFill"; to: 0.0; easing.type: Easing.OutQuad }

    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: card; property: "popScale"; to: 0.95; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "popScale"; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
    }

    SequentialAnimation {
        id: marqueeAnim
        loops: Animation.Infinite
        running: card.marqueeOn
        PauseAnimation { duration: 3000 }
        NumberAnimation { target: card; property: "marqueeX"; from: 0; to: -card.marqueeStep; duration: card.marqueeStep * 25 }
        PropertyAction { target: card; property: "marqueeX"; value: 0 }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Radius.outer(card.popup ? card.popup.s(14) : 14)
        color: card.popup ? Qt.alpha(card.popup.surface0, 0.9) : "transparent"
        border.width: 1
        border.color: !card.popup ? "transparent"
                    : cardMa.containsMouse ? card.popup.accent
                    : card.emphasised ? Qt.alpha(card.popup.accent, 0.45)
                    : Qt.alpha(card.popup.overlay0, 0.5)
        Behavior on border.color { ColorAnimation { duration: 200 } }
        clip: true
        scale: card.popScale

        Rectangle {
            height: parent.height
            width: card.busy ? parent.width : 0
            radius: parent.radius
            color: card.popup ? Qt.alpha(card.popup.accent, 0.28) : "transparent"
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        }

        // The hold fill, clipped to the wave edge then to the card's rounded rect.
        Canvas {
            id: fillCanvas
            anchors.fill: parent
            visible: card.holdFill > 0

            property real wavePhase: 0
            NumberAnimation on wavePhase {
                from: 0; to: Math.PI * 2
                duration: 800
                loops: Animation.Infinite
                running: card.holdFill > 0 && card.holdFill < 1
            }
            onWavePhaseChanged: fillCanvas.requestPaint()

            Connections {
                target: card
                function onHoldFillChanged() { fillCanvas.requestPaint(); }
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                if (card.holdFill <= 0.001 || !card.popup) return;

                var r = Math.min(bg.radius, Math.min(width, height) / 2);
                var cw = width * card.holdFill;

                ctx.save();
                ctx.beginPath();
                ctx.moveTo(0, 0);
                if (card.holdFill < 0.99) {
                    var maxAmp = Math.min(card.popup.s(10), Math.min(cw, width - cw));
                    var amp = maxAmp * Math.sin(card.holdFill * Math.PI);
                    var cp1x = Math.max(0, Math.min(width, cw + Math.sin(fillCanvas.wavePhase) * amp));
                    var cp2x = Math.max(0, Math.min(width, cw + Math.cos(fillCanvas.wavePhase + Math.PI) * amp));
                    ctx.lineTo(cw, 0);
                    ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, cw, height);
                    ctx.lineTo(0, height);
                } else {
                    ctx.lineTo(width, 0);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                }
                ctx.closePath();
                ctx.clip();

                ctx.beginPath();
                ctx.moveTo(r, 0);
                ctx.lineTo(width - r, 0);
                ctx.arcTo(width, 0, width, r, r);
                ctx.lineTo(width, height - r);
                ctx.arcTo(width, height, width - r, height, r);
                ctx.lineTo(r, height);
                ctx.arcTo(0, height, 0, height - r, r);
                ctx.lineTo(0, r);
                ctx.arcTo(0, 0, r, 0, r);
                ctx.closePath();

                var g = ctx.createLinearGradient(0, 0, Math.max(1, cw), 0);
                g.addColorStop(0, String(Qt.darker(card.popup.accent, 1.15)));
                g.addColorStop(1, String(card.popup.accent));
                ctx.fillStyle = g;
                ctx.fill();
                ctx.restore();
            }
        }

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: card.hoverChanged(true)
            onExited: card.hoverChanged(false)
            onPressed: mouse => {
                if (mouse.button !== Qt.LeftButton) return;
                card.holdConsumed = false;
                fillDown.stop();
                fillUp.duration = Math.max(1, card.fillDuration * (1.0 - card.holdFill));
                fillUp.start();
            }
            onReleased: card.releaseHold()
            onCanceled: card.releaseHold()
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && card.forgettable)
                    card.forgetRequested();
            }
        }

        CardBody {
            id: baseBody
            anchors.fill: parent
            glyphCol: !card.popup ? "white" : (card.emphasised ? card.popup.accent : card.popup.subtext0)
            titleCol: card.popup ? card.popup.text : "white"
            subCol: card.popup ? card.popup.overlay0 : "white"
        }

        // The wording inverts as the fill sweeps: same label, clipped to the wave edge.
        Item {
            id: filledClip
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            visible: card.holdFill > 0.01

            readonly property real maxAmp: card.popup ? Math.min(card.popup.s(10), Math.min(card.width * card.holdFill, card.width * (1.0 - card.holdFill))) : 0
            readonly property real waveAmp: filledClip.maxAmp * Math.sin(card.holdFill * Math.PI)
            readonly property real phaseOffset: Math.sin(fillCanvas.wavePhase) - Math.cos(fillCanvas.wavePhase)
            readonly property real centerOffset: (card.holdFill > 0.01 && card.holdFill < 0.99) ? 0.375 * filledClip.waveAmp * filledClip.phaseOffset : 0
            width: Math.max(0, Math.min(card.width, card.width * card.holdFill + filledClip.centerOffset))

            CardBody {
                ghost: true
                width: card.width
                height: card.height
                glyphCol: card.popup ? card.popup.crust : "white"
                titleCol: card.popup ? card.popup.crust : "white"
                subCol: card.popup ? Qt.alpha(card.popup.crust, 0.75) : "white"
            }
        }

        Rectangle {
            id: fillFlash
            anchors.fill: parent
            radius: parent.radius
            color: card.popup ? card.popup.text : "transparent"
            opacity: 0
            NumberAnimation { id: flashFade; target: fillFlash; property: "opacity"; to: 0; duration: 400; easing.type: Easing.OutExpo }
        }
    }

    component CardBody: Item {
        id: body
        // The clipped copy must not take the pointer away from the card underneath.
        property bool ghost: false
        property color glyphCol: "white"
        property color titleCol: "white"
        property color subCol: "white"

        readonly property real titleWidth: titleMain.implicitWidth
        readonly property real titleRoom: titleClip.width

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: card.popup ? card.popup.s(10) : 10
            anchors.rightMargin: card.popup ? card.popup.s(10) : 10
            spacing: card.popup ? card.popup.s(6) : 6

            Text {
                text: card.glyph
                font.family: "Iosevka Nerd Font"
                font.pixelSize: card.popup ? card.popup.s(18) : 18
                color: body.glyphCol
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Item {
                    id: titleClip
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleMain.implicitHeight
                    clip: true

                    Row {
                        x: card.marqueeX
                        spacing: card.popup ? card.popup.s(30) : 30

                        Text {
                            id: titleMain
                            text: card.title
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: card.popup ? card.popup.s(12) : 12
                            color: body.titleCol
                        }
                        Text {
                            visible: card.marqueeOn
                            text: card.title
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: card.popup ? card.popup.s(12) : 12
                            color: body.titleCol
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: card.subtitle
                    font.family: Fonts.ui
                    font.pixelSize: card.popup ? card.popup.s(9) : 9
                    color: body.subCol
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: card.pip !== ""
                Layout.preferredWidth: card.popup ? card.popup.s(18) : 18
                Layout.preferredHeight: card.popup ? card.popup.s(18) : 18
                radius: width / 2
                color: !card.popup ? "transparent"
                     : (card.pipOn ? Qt.alpha(body.glyphCol, 0.25) : "transparent")
                border.width: 1
                border.color: !card.popup ? "transparent"
                            : (card.pipOn ? body.glyphCol : Qt.alpha(body.subCol, 0.6))
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }

                Text {
                    anchors.centerIn: parent
                    text: card.pip
                    font.family: Fonts.ui
                    font.weight: Font.Bold
                    font.pixelSize: card.popup ? card.popup.s(9) : 9
                    color: card.pipOn ? body.glyphCol : body.subCol
                }

                // Hover stays with the card so the tab's hover-lock counter keeps working.
                MouseArea {
                    anchors.fill: parent
                    enabled: !body.ghost
                    hoverEnabled: false
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.pipToggled()
                }
            }
        }
    }
}
