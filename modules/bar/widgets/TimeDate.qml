// Clock and typed-in date (bar.time.format); opens the calendar.
import "../../../services/audio"
import "../../calendar"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: timedate
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    property bool isHovered: clockMouse.containsMouse

    // Measured on the full date, so the typewriter never shifts the neighbours.
    readonly property real textColWidth: Math.max(timeMeasure.implicitWidth, dateMeasure.implicitWidth)
    readonly property real targetWidth: (placed && !vertical) ? textColWidth + barWindow.s(28) : 0
    readonly property real targetHeight: (placed && vertical) ? vClock.implicitHeight + barWindow.s(20) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !timedate.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && timedate.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !timedate.vertical; NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
    visible: placed && (vertical ? height : width) > 0

    color: grouped ? "transparent" : (isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : barWindow.pillBg)
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 * barWindow.pillBorderAlpha : 0.05 * barWindow.pillBorderAlpha)
    Behavior on color { ColorAnimation { duration: 250 } }
    scale: isHovered ? 1.03 : 1.0
    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady; interval: 150; onTriggered: timedate.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: timedate.showLayout ? 0 : barWindow.s(-30)
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    }

    MouseArea { id: clockMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); CalendarState.toggle(); } }

    Text { id: timeMeasure; visible: false; text: barWindow.timeStr; font.family: Fonts.ui; font.pixelSize: barWindow.s(16); font.weight: Font.Black }
    Text { id: dateMeasure; visible: false; text: barWindow.fullDateStr; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold }

    // Re-read once a minute via minuteStr, which is enough for the date.
    readonly property string dayStr: { barWindow.minuteStr; return Qt.formatDateTime(new Date(), "dd"); }
    readonly property string monthStr: { barWindow.minuteStr; return Qt.formatDateTime(new Date(), "MMM").toUpperCase(); }

    // v2's side clock: hour, minute, a short rule, then day and month.
    Column {
        id: vClock
        visible: timedate.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(1)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: barWindow.hourStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Black
            color: mocha.blue
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: barWindow.minuteStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Black
            color: mocha.sapphire
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: barWindow.s(16)
            height: barWindow.s(12)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: 2; radius: 1; color: mocha.surface2 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: timedate.dayStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(12); font.weight: Font.Bold
            color: mocha.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: timedate.monthStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(10); font.weight: Font.Bold
            color: mocha.subtext0
        }
    }

    ColumnLayout {
        visible: !timedate.vertical
        anchors.centerIn: parent
        spacing: -2
        Text { text: barWindow.timeStr; Layout.alignment: Qt.AlignLeft; Layout.preferredWidth: timedate.textColWidth; font.family: Fonts.ui; font.pixelSize: barWindow.s(16); font.weight: Font.Black; color: mocha.blue }
        Text { text: barWindow.dateStr; Layout.alignment: Qt.AlignLeft; Layout.preferredWidth: timedate.textColWidth; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.subtext0 }
    }
}
