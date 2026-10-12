import "../../../../services/reusables"
import "../../../../services/shims"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 90
    property real minHeight: 90
    property real maxWidth: 600
    property real maxHeight: 600
    property real minAspect: 0.7
    property real maxAspect: 2.2

    property real dynMargin: Math.max(6, Math.min(16, Math.min(root.width, root.height) * 0.08))
    property real dynSpacing: Math.max(2, Math.min(8, Math.min(root.width, root.height) * 0.04))

    property var weatherData: WeatherBridge.data
    property bool hasLoadedOnce: WeatherBridge.isReady
    property bool isLoading: WeatherBridge.isLoading || !WeatherBridge.isReady

    property string currentHex: WeatherBridge.currentHex
    property color accentColor: (currentHex && currentHex.length === 7) ? currentHex : ThemeBackend.mauve

    Rectangle {
        anchors.fill: parent
        color: ThemeBackend.surface0
        radius: ThemeBackend.borderRadius * 2
    }

    LoaderIcon {
        anchors.centerIn: parent
        width: Math.max(20, Math.min(44, Math.min(root.width, root.height) * 0.4))
        height: width
        accentColor: ThemeBackend.mauve
        running: root.isLoading
        visible: root.isLoading
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.dynMargin
        property bool isHorizontal: root.width > root.height * 1.15
        columns: isHorizontal ? 2 : 1
        rows: isHorizontal ? 1 : 2
        columnSpacing: root.dynSpacing
        rowSpacing: root.dynSpacing
        visible: !root.isLoading

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.isHorizontal ? parent.width * 0.5 : parent.width
            Layout.preferredHeight: parent.isHorizontal ? parent.height : parent.height * 0.5

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -6
                text: WeatherBridge.currentIcon !== "" ? WeatherBridge.currentIcon : ""
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.min(parent.width, parent.height) * 0.65
                color: root.accentColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.isHorizontal ? parent.width * 0.5 : parent.width
            Layout.preferredHeight: parent.isHorizontal ? parent.height : parent.height * 0.5

            Text {
                anchors.centerIn: parent
                text: WeatherBridge.currentTemp !== "" ? Math.round(parseFloat(WeatherBridge.currentTemp)) + "°" : "--°"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.min(parent.width, parent.height) * 0.45
                font.weight: Font.Black
                color: ThemeBackend.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
