import QtQuick
import QtQuick.Layouts

Item {
    id: root
    clip: true

    required property QtObject dateTime
    required property QtObject theme
    property bool smoothHands: false

    readonly property real minWidth: 120
    readonly property real minHeight: 120
    readonly property bool isStacked: (width / height) < 1.25

    Rectangle {
        id: bgContainer
        anchors.fill: parent
        color: root.theme.surfaceVariant ?? root.theme.surface0
        radius: root.theme.borderRadius
        antialiasing: true

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Math.min(parent.width, parent.height) * 0.08
            width: Math.min(parent.width, parent.height) * 0.55
            height: width
            radius: width * 0.4
            color: root.theme.primaryContainer ?? root.theme.surface1
            opacity: 0.45
            antialiasing: true
        }

        Item {
            anchors.fill: parent
            anchors.margins: Math.min(parent.width, parent.height) * 0.12

            ColumnLayout {
                visible: root.isStacked
                anchors.fill: parent
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.dateTime.hour
                    font.family: root.theme.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Normal
                    color: root.theme.onSurface ?? root.theme.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.dateTime.minute
                    font.family: root.theme.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Black
                    color: root.theme.primary ?? root.theme.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    implicitWidth: Math.max(dateLabelStacked.implicitWidth + 16, 40)
                    implicitHeight: Math.max(dateLabelStacked.implicitHeight + 8, 20)
                    radius: height / 2
                    color: root.theme.secondaryContainer ?? root.theme.surface2

                    Text {
                        id: dateLabelStacked
                        anchors.centerIn: parent
                        text: root.dateTime.dateBadge
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                        color: root.theme.onSecondaryContainer ?? root.theme.subtext0
                    }
                }
            }

            RowLayout {
                visible: !root.isStacked
                anchors.fill: parent
                spacing: Math.min(parent.width, parent.height) * 0.04

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.dateTime.time
                    font.family: root.theme.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Black
                    color: root.theme.primary ?? root.theme.text
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.max(dateLabelWide.implicitWidth + 20, 48)
                    implicitHeight: Math.max(dateLabelWide.implicitHeight + 10, 26)
                    radius: height / 2
                    color: root.theme.secondaryContainer ?? root.theme.surface2

                    Text {
                        id: dateLabelWide
                        anchors.centerIn: parent
                        text: root.dateTime.dateBadge
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        color: root.theme.onSecondaryContainer ?? root.theme.subtext0
                    }
                }
            }
        }
    }
}
