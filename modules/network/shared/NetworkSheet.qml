// The modal drawn over the core: chrome only, the tab supplies the body.
// `NetworkSheet.Field` is the matching input frame — give it Layout sizing from outside.

import "../../../services/layout"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts

Item {
    id: sheet

    property var popup: null
    property bool open: false
    property string glyph: ""
    property string title: ""

    default property alias body: bodySlot.data

    anchors.fill: parent
    opacity: sheet.open ? 1.0 : 0.0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutSine } }
    scale: sheet.open ? 1.0 : 0.8
    Behavior on scale {
        NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width
        spacing: sheet.popup ? sheet.popup.s(6) : 6

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: sheet.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: sheet.popup ? sheet.popup.s(28) : 28
            color: sheet.popup ? sheet.popup.crust : "white"
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - (sheet.popup ? sheet.popup.s(30) : 30)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: sheet.title
            font.family: Fonts.ui
            font.weight: Font.Bold
            font.pixelSize: sheet.popup ? sheet.popup.s(12) : 12
            color: sheet.popup ? sheet.popup.crust : "white"
        }

        Item {
            id: bodySlot
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
        }
    }

    component Field: Rectangle {
        id: field
        property var pop: null
        property bool focused: false

        implicitHeight: field.pop ? field.pop.s(32) : 32
        radius: Radius.outer(field.pop ? field.pop.s(8) : 8)
        color: field.pop ? field.pop.surface0 : "transparent"
        border.width: 1
        border.color: (field.focused && field.pop) ? field.pop.crust : "transparent"
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }
}
