// Group heading for a settings section, in the v2 guide's small-caps style.
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var host
    property string text: ""

    Layout.fillWidth: true
    Layout.topMargin: root.host.s(10)
    implicitHeight: label.implicitHeight + root.host.s(6)

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: root.host.s(4)
        anchors.bottom: parent.bottom
        text: root.text.toUpperCase()
        font.family: root.host.fontFamily
        font.pixelSize: root.host.s(10)
        font.weight: Font.Bold
        font.letterSpacing: root.host.s(1)
        color: root.host.subtext0
    }
}
