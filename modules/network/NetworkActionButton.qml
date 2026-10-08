// Footer control in the Network panel: tinted when active, dimmed when unavailable.

import "../../services/layout"
import "../../services/theme"
import QtQuick

Item {
    id: btn

    property var popup: null
    property string glyph: ""
    property string label: ""
    property bool active: false
    property bool enabled: true

    signal triggered()

    implicitWidth: row.implicitWidth + popup.s(22)
    implicitHeight: popup.s(34)
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1.0 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: Radius.outer(popup.s(10))
        color: btn.active ? Qt.alpha(popup.accent, 0.18)
             : (ma.containsMouse && btn.enabled ? popup.surface1 : "transparent")
        border.width: 1
        border.color: btn.active ? popup.accent : Qt.alpha(popup.overlay0, 0.45)
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: popup.s(7)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: popup.s(15)
            color: btn.active ? popup.accent : popup.subtext0
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            font.family: Fonts.ui
            font.weight: Font.Bold
            font.pixelSize: popup.s(11)
            color: btn.active ? popup.accent : popup.text
            Behavior on color { ColorAnimation { duration: 180 } }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (btn.enabled) btn.triggered()
    }
}
