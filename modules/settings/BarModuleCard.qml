// One bar module's options, upstream's bar/modules/BarModuleCard.qml. Upstream's live
// widget previews need a face registry we do not have, so this is the card alone.

import "../../services/layout"
import QtQuick
import QtQuick.Layouts
import "../../services/bar/BarModules.js" as BarModules

Rectangle {
    id: card
    required property var host
    required property string moduleId
    default property alias content: contentCol.data

    readonly property var info: BarModules.INFO[card.moduleId] || ({})
    property string title: card.info.label || ""
    property string glyph: card.info.icon || ""

    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + card.host.s(24)
    radius: Radius.outer(card.host.s(8))
    color: Qt.alpha(card.host.surface0, 0.4)
    border.width: 1
    border.color: Qt.alpha(card.host.surface2, 0.6)

    ColumnLayout {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.host.s(12)
        spacing: card.host.s(6)

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: card.host.s(2)
            spacing: card.host.s(8)

            Text {
                visible: card.glyph !== ""
                text: card.glyph
                font.family: card.host.glyphFamily
                font.pixelSize: card.host.s(14)
                color: card.host.subtext0
            }
            Text {
                Layout.fillWidth: true
                text: card.title
                font.family: card.host.fontFamily
                font.pixelSize: card.host.s(14)
                font.bold: true
                color: card.host.text
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            id: contentCol
            Layout.fillWidth: true
            spacing: card.host.s(6)
        }
    }
}
