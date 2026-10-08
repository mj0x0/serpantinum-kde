// serpantinum v2's FillButton: hold to fill, or click twice (remote input cannot hold).
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property real sf: 1.0
    function s(v) { return Math.round(v * sf) }
    implicitWidth: root.s(200)
    implicitHeight: root.s(56)

    property int cornerRadius: 12
    readonly property real effectiveRadius: Math.max(0, Math.min(root.cornerRadius, Math.min(width, height) / 2))
    property string buttonText: ""
    property string buttonIcon: ""
    property int iconFontSize: root.s(20)
    property int textFontSize: root.s(16)
    property string fontFamily: "JetBrainsMono Nerd Font"

    property color accentColor: "white"
    property color baseColor: Qt.rgba(0, 0, 0, 0.3)
    property color hoverColor: Qt.rgba(0, 0, 0, 0.2)
    property color textColor: "white"
    property color filledTextColor: "black"
    property int fillDuration: 800
    property int autoResetTimeout: 1200

    signal triggered()

    property real fillLevel: 0.0
    property bool isTriggered: false
    property bool armed: false
    property bool committing: false
    property double pressedAt: 0
    property real flashOpacity: 0.0
    property real popScale: 1.0
    readonly property bool isHoveredOrHighlighted: btnMa.containsMouse && !root.isTriggered

    function reset() {
        resetTimer.stop();
        root.isTriggered = false;
        root.armed = false;
        root.committing = false;
        fillAnim.stop();
        armAnim.stop();
        drainAnim.start();
    }

    Timer { id: resetTimer; interval: root.autoResetTimeout; onTriggered: root.reset() }
    Timer { id: disarmTimer; interval: 3000; onTriggered: root.disarm() }

    function disarm() {
        root.armed = false;
        if (root.committing || root.isTriggered) return;
        armAnim.stop();
        drainAnim.start();
    }

    // Icon + staggered-in characters; drawn twice, the second copy clipped to the fill.
    component ButtonContent : Item {
        id: bRoot
        property color contentTextColor: root.accentColor
        property real currentFill: 0.0
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: root.s(12)

            Text {
                id: iconText
                visible: root.buttonIcon !== ""
                text: root.buttonIcon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.iconFontSize
                color: bRoot.contentTextColor
                Behavior on color { ColorAnimation { duration: 150 } }
                readonly property real charNorm: bRoot.width > 0 ? (contentRow.x + x + width / 2) / bRoot.width : 0
                readonly property real bump: bRoot.currentFill > 0.001 && bRoot.currentFill < 0.999
                                             ? Math.exp(-Math.pow((bRoot.currentFill - charNorm) * 9, 2)) : 0.0
                transform: [
                    Translate { y: -iconText.bump },
                    Scale { origin.x: iconText.width / 2; origin.y: iconText.height / 2; xScale: 1.0 + iconText.bump * 0.03; yScale: 1.0 + iconText.bump * 0.03 }
                ]
            }

            Row {
                id: charRow
                spacing: 0
                Repeater {
                    model: Array.from(root.buttonText)
                    Item {
                        id: charSlot
                        required property string modelData
                        required property int index
                        width: charText.implicitWidth
                        height: charText.implicitHeight

                        readonly property real charNorm: bRoot.width > 0 ? (contentRow.x + charRow.x + x + width / 2) / bRoot.width : 0
                        readonly property real bump: bRoot.currentFill > 0.001 && bRoot.currentFill < 0.999
                                                     ? Math.exp(-Math.pow((bRoot.currentFill - charNorm) * 9, 2)) : 0.0
                        property real animScale: 1.0
                        property real animY: 0.0
                        property real animRotation: 0.0

                        Component.onCompleted: entranceAnim.restart()
                        SequentialAnimation {
                            id: entranceAnim
                            PauseAnimation { duration: charSlot.index * 20 }
                            ParallelAnimation {
                                NumberAnimation { target: charSlot; property: "animScale"; from: 0.55; to: 1.0; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
                                NumberAnimation { target: charSlot; property: "animY"; from: 4; to: 0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.25 }
                                NumberAnimation { target: charSlot; property: "animRotation"; from: (charSlot.index % 2 === 0 ? -10 : 10); to: 0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: charSlot; property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }

                        Text {
                            id: charText
                            anchors.centerIn: parent
                            text: charSlot.modelData === " " ? " " : charSlot.modelData
                            font.family: root.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: root.textFontSize
                            color: bRoot.contentTextColor
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        transform: [
                            Translate { y: charSlot.animY - charSlot.bump * 3.5 },
                            Scale { origin.x: charSlot.width / 2; origin.y: charSlot.height / 2; xScale: charSlot.animScale * (1.0 + charSlot.bump * 0.12); yScale: charSlot.animScale * (1.0 + charSlot.bump * 0.12) },
                            Rotation { origin.x: charSlot.width / 2; origin.y: charSlot.height / 2; angle: charSlot.animRotation + charSlot.bump * (charSlot.index % 2 === 0 ? -7 : 7) }
                        ]
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.s(2)
        anchors.bottomMargin: -root.s(2)
        radius: root.effectiveRadius
        color: Qt.rgba(0, 0, 0, 0.14)
        scale: btnShape.scale
        opacity: root.isTriggered ? 0.06 : (root.isHoveredOrHighlighted ? 0.24 : 0.14)
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.s(2)
        anchors.bottomMargin: -root.s(2)
        radius: Math.min(root.effectiveRadius + 2, Math.min(width, height) / 2)
        color: root.accentColor
        scale: btnShape.scale
        opacity: root.isHoveredOrHighlighted && !root.isTriggered ? 0.18 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Rectangle {
        id: btnShape
        anchors.fill: parent
        radius: root.effectiveRadius
        clip: true
        color: root.isHoveredOrHighlighted ? root.hoverColor : root.baseColor
        Behavior on color { ColorAnimation { duration: 180 } }

        scale: (btnMa.pressed && !root.isTriggered ? 0.96 : (root.isHoveredOrHighlighted ? 1.02 : 1.0)) * root.popScale
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: root; property: "popScale"; to: 0.95; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "popScale"; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
        }

        Canvas {
            id: waveCanvas
            anchors.fill: parent
            property real wavePhase: 0.0
            NumberAnimation on wavePhase {
                running: root.fillLevel > 0.0 && root.fillLevel < 1.0
                loops: Animation.Infinite
                from: 0; to: Math.PI * 2; duration: 800
            }
            onWavePhaseChanged: requestPaint()
            Connections { target: root; function onFillLevelChanged() { waveCanvas.requestPaint() } }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (root.fillLevel <= 0.001) return;
                var r = root.effectiveRadius;
                var currentW = width * root.fillLevel;

                ctx.save();
                ctx.beginPath();
                ctx.moveTo(0, 0);
                if (root.fillLevel < 0.99) {
                    var maxAmp = Math.min(root.s(10), Math.min(currentW, width - currentW));
                    var waveAmp = maxAmp * Math.sin(root.fillLevel * Math.PI);
                    var cp1x = Math.max(0, Math.min(width, currentW + Math.sin(wavePhase) * waveAmp));
                    var cp2x = Math.max(0, Math.min(width, currentW + Math.cos(wavePhase + Math.PI) * waveAmp));
                    ctx.lineTo(currentW, 0);
                    ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, currentW, height);
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
                var grad = ctx.createLinearGradient(0, 0, currentW, 0);
                grad.addColorStop(0, Qt.darker(root.accentColor, 1.15).toString());
                grad.addColorStop(1, root.accentColor.toString());
                ctx.fillStyle = grad;
                ctx.fill();
                ctx.restore();
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.effectiveRadius
            color: "white"
            opacity: root.flashOpacity
            PropertyAnimation on opacity { id: flashAnim; to: 0; duration: 400; easing.type: Easing.OutExpo }
        }

        ButtonContent {
            width: btnShape.width
            height: btnShape.height
            contentTextColor: root.isHoveredOrHighlighted ? root.textColor : root.accentColor
            currentFill: root.fillLevel
        }

        Item {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            readonly property real maxAmp: Math.min(root.s(10), Math.min(parent.width * root.fillLevel, parent.width * (1.0 - root.fillLevel)))
            readonly property real waveAmp: maxAmp * Math.sin(root.fillLevel * Math.PI)
            readonly property real phaseOffset: Math.sin(waveCanvas.wavePhase) - Math.cos(waveCanvas.wavePhase)
            readonly property real centerOffset: root.fillLevel > 0.01 && root.fillLevel < 0.99 ? 0.375 * waveAmp * phaseOffset : 0
            width: Math.max(0, Math.min(parent.width, parent.width * root.fillLevel + centerOffset))
            clip: true

            ButtonContent {
                width: btnShape.width
                height: btnShape.height
                contentTextColor: root.filledTextColor
                currentFill: root.fillLevel
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.s(4)
            text: "Click again"
            font.family: root.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(9)
            color: root.filledTextColor
            opacity: root.armed ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.isTriggered
            cursorShape: root.isTriggered ? Qt.ArrowCursor : Qt.PointingHandCursor
            onPressed: {
                if (root.isTriggered || root.committing) return;
                drainAnim.stop();
                armAnim.stop();
                if (root.armed) {
                    disarmTimer.stop();
                    root.armed = false;
                    root.committing = true;
                    fillAnim.duration = 200;
                    fillAnim.start();
                    return;
                }
                root.pressedAt = Date.now();
                fillAnim.duration = root.fillDuration * (1.0 - root.fillLevel);
                fillAnim.start();
            }
            function letGo() {
                if (root.isTriggered || root.committing || root.fillLevel >= 1.0) return;
                fillAnim.stop();
                // A quick tap arms instead of draining; a second click confirms.
                if (Date.now() - root.pressedAt < 300) {
                    root.armed = true;
                    armAnim.start();
                    disarmTimer.restart();
                    return;
                }
                drainAnim.start();
            }
            onReleased: letGo()
            onCanceled: letGo()
        }

        NumberAnimation {
            id: fillAnim
            target: root
            property: "fillLevel"
            to: 1.0
            duration: root.fillDuration
            easing.type: Easing.InSine
            onFinished: {
                root.isTriggered = true;
                root.committing = false;
                root.flashOpacity = 0.5;
                popAnim.start();
                flashAnim.start();
                root.triggered();
                resetTimer.restart();
            }
        }

        NumberAnimation { id: armAnim; target: root; property: "fillLevel"; to: 0.5; duration: 220; easing.type: Easing.OutCubic }

        NumberAnimation {
            id: drainAnim
            target: root
            property: "fillLevel"
            to: 0.0
            duration: 260 * root.fillLevel
            easing.type: Easing.OutCubic
        }
    }
}
