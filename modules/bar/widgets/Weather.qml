// OpenWeather icon and temperature from the weather.sh cache; spinner until it lands.
import "../../../services/audio"
import "../../calendar"
import "../../../services/theme"
import QtQuick

Rectangle {
    id: weather
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    property bool isHovered: weatherMouse.containsMouse
    readonly property bool loading: barWindow.weatherIcon === "" || barWindow.weatherTemp === "--°"

    readonly property real targetWidth: (placed && !vertical) ? hRow.implicitWidth + barWindow.s(24) : 0
    readonly property real targetHeight: (placed && vertical) ? vCol.implicitHeight + barWindow.s(20) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !weather.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && weather.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !weather.vertical; NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
    visible: placed && (vertical ? height : width) > 0

    color: grouped ? "transparent" : (isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : barWindow.pillBg)
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 * barWindow.pillBorderAlpha : 0.05 * barWindow.pillBorderAlpha)
    Behavior on color { ColorAnimation { duration: 250 } }
    scale: isHovered ? 1.03 : 1.0
    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady; interval: 200; onTriggered: weather.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: weather.showLayout ? 0 : barWindow.s(-30)
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    }

    MouseArea { id: weatherMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); CalendarState.toggle(); } }

    component Spinner : Text {
        text: "\u{f0450}"
        font.family: "Iosevka Nerd Font"
        color: mocha.subtext0
        NumberAnimation on rotation { from: 0; to: 360; duration: 1200; loops: Animation.Infinite; running: weather.loading && weather.visible }
    }

    Row {
        id: hRow
        visible: !weather.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(8)
        Spinner { anchors.verticalCenter: parent.verticalCenter; visible: weather.loading; font.pixelSize: barWindow.s(20) }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: !weather.loading; text: barWindow.weatherIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(24); color: mocha.text }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: !weather.loading; text: barWindow.weatherTemp; font.family: Fonts.ui; font.pixelSize: barWindow.s(17); font.weight: Font.Black; color: Colors.md3.tertiary }
    }

    Column {
        id: vCol
        visible: weather.vertical
        anchors.centerIn: parent
        spacing: 0
        Spinner { anchors.horizontalCenter: parent.horizontalCenter; visible: weather.loading; font.pixelSize: barWindow.s(18) }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: !weather.loading; text: barWindow.weatherIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(18); color: mocha.text }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: !weather.loading; text: barWindow.weatherTemp; font.family: Fonts.ui; font.pixelSize: barWindow.s(10); font.weight: Font.Black; color: Colors.md3.tertiary }
    }
}
