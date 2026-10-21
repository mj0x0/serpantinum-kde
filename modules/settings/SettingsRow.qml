import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    required property var host
    property string label
    property string desc
    property string glyph: ""
    default property alias content: holder.data

    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + row.host.s(24)
    radius: Radius.outer(row.host.s(8))
    color: Qt.alpha(row.host.surface0, 0.4)

    RowLayout {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: row.host.s(14)
        anchors.rightMargin: row.host.s(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.host.s(12)

        V2.IconButton {
            visible: row.glyph !== ""
            enabled: false
            size: row.host.s(32)
            Layout.preferredWidth: row.host.s(32)
            Layout.preferredHeight: row.host.s(32)
            Layout.alignment: Qt.AlignVCenter
            cornerRadius: Radius.outer(row.host.s(8))
            buttonIcon: row.glyph
            centerInk: true
            iconFontSize: row.host.s(16)
            accentColor: row.host.surface0
            textColor: row.host.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: row.host.s(2)
            Text {
                Layout.fillWidth: true
                text: row.label
                font.family: row.host.fontFamily
                font.pixelSize: row.host.s(13)
                color: row.host.text
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: row.desc
                visible: row.desc !== ""
                font.family: row.host.fontFamily
                font.pixelSize: row.host.s(11)
                color: row.host.subtext0
                wrapMode: Text.Wrap
            }
        }
        Item {
            id: holder
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
    }
}
