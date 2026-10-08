// Value/label card orbiting a core, in serpantinum's float-card geometry. Shared by
// the Bluetooth and Network panels. `emphasised` tints the value with accentColor.

import "../../services/layout"
import "../../services/theme"
import QtQuick

Item {
    id: node

    property var popup: null
    property string value: ""
    property string label: ""
    property string glyph: ""
    property bool actionable: false
    property bool emphasised: false
    property color accentColor: popup ? popup.accent : "white"

    signal triggered()

    width: popup ? popup.s(170) : 170
    height: popup ? popup.s(52) : 52

    Rectangle {
        anchors.fill: parent
        radius: Radius.outer(popup.s(14))
        color: Qt.alpha(popup.surface0, 0.92)
        border.width: 1
        border.color: node.emphasised ? Qt.alpha(node.accentColor, 0.45)
                    : (node.actionable && ma.containsMouse ? popup.accent
                                                           : Qt.alpha(popup.overlay0, 0.5))
        Behavior on border.color { ColorAnimation { duration: 180 } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: popup.s(12)
            anchors.rightMargin: popup.s(10)
            spacing: popup.s(9)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: node.glyph
                font.family: "Iosevka Nerd Font"
                font.pixelSize: popup.s(16)
                color: node.emphasised ? node.accentColor
                     : (node.actionable && ma.containsMouse ? popup.accent : popup.subtext0)
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - popup.s(34)
                spacing: 0

                Text {
                    width: parent.width
                    text: node.value
                    font.family: Fonts.ui
                    font.weight: Font.Bold
                    // Shrink-to-fit, not elide: a truncated endpoint is worse than a slightly smaller one.
                    fontSizeMode: Text.HorizontalFit
                    font.pixelSize: popup.s(13)
                    minimumPixelSize: popup.s(9)
                    color: node.emphasised ? node.accentColor : popup.text
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Text {
                    width: parent.width
                    text: node.label
                    font.family: Fonts.ui
                    font.pixelSize: popup.s(10)
                    color: popup.overlay0
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: node.actionable
            cursorShape: node.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (node.actionable) node.triggered()
        }
    }

    // Multiplied in rather than overridden, so a caller can animate the node
    // arriving without replacing the hover binding and silently losing it.
    property real entryScale: 1.0

    scale: ((node.actionable && ma.containsMouse) ? 1.05 : 1.0) * node.entryScale
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
}
