// Recording dot with elapsed time (any PipeWire screencast) and the quick-action timer;
// nothing on screen while neither runs. serpantinum v2's InfoWidget on our sources.
import "../../../services/timer"
import "../../../services/theme"
import QtQuick

Rectangle {
    id: info
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    property bool isHovered: infoMouse.containsMouse

    readonly property bool recording: barWindow.isRecording
    readonly property int recSeconds: recording ? Math.max(0, Math.floor((barWindow.nowTick - barWindow.recStartEpoch) / 1000)) : 0
    readonly property string recText: String(Math.floor(recSeconds / 60)).padStart(2, "0") + ":" + String(recSeconds % 60).padStart(2, "0")
    readonly property bool timerOn: TimerState.active
    readonly property color timerColor: mocha[TimerState.tone] !== undefined ? mocha[TimerState.tone] : mocha.blue
    readonly property bool hasContent: recording || timerOn

    readonly property real targetWidth: (placed && !vertical && hasContent) ? hRow.implicitWidth + barWindow.s(24) : 0
    readonly property real targetHeight: (placed && vertical && hasContent) ? vCol.implicitHeight + barWindow.s(20) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !info.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && info.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !info.vertical; NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    Behavior on height { enabled: info.vertical; NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    visible: placed && ((vertical ? height : width) > 0 || opacity > 0)
    clip: true

    color: grouped ? "transparent" : (isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : barWindow.pillBg)
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 * barWindow.pillBorderAlpha : 0.05 * barWindow.pillBorderAlpha)
    Behavior on color { ColorAnimation { duration: 200 } }
    opacity: hasContent ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    MouseArea { id: infoMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    component RecDot : Rectangle {
        width: barWindow.s(10); height: width; radius: width / 2
        color: mocha.red
        SequentialAnimation on opacity {
            running: info.recording && !info.isHovered
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
        }
    }

    Row {
        id: hRow
        visible: !info.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(12)
        Row {
            visible: info.recording
            spacing: barWindow.s(6)
            RecDot { anchors.verticalCenter: parent.verticalCenter }
            Text { anchors.verticalCenter: parent.verticalCenter; text: info.recText; font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Bold; color: mocha.red }
        }
        Row {
            visible: info.timerOn
            spacing: barWindow.s(6)
            Text { anchors.verticalCenter: parent.verticalCenter; text: TimerState.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: info.timerColor; Behavior on color { ColorAnimation { duration: 250 } } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: TimerState.text; font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Bold; color: info.timerColor; Behavior on color { ColorAnimation { duration: 250 } } }
        }
    }

    Column {
        id: vCol
        visible: info.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(6)
        Column {
            visible: info.recording
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: barWindow.s(2)
            RecDot { anchors.horizontalCenter: parent.horizontalCenter }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(Math.floor(info.recSeconds / 60)).padStart(2, "0"); font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.red }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(info.recSeconds % 60).padStart(2, "0"); font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.red }
        }
        Column {
            visible: info.timerOn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: barWindow.s(2)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: TimerState.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: info.timerColor }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: TimerState.text.split(":").slice(-2)[0]; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: info.timerColor }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: TimerState.text.split(":").slice(-1)[0]; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: info.timerColor }
        }
    }
}
