// One tile per desktop; clicking one drops a glyph grid, a paste field and #.

import "../../services/layout"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flow {
    id: gs
    required property var host
    property int count: 10
    property var glyphs: []
    signal picked(int index, string glyph)
    spacing: gs.host.s(6)

    readonly property real cell: gs.host.s(38)
    readonly property real pickCell: gs.host.s(32)
    readonly property int pickCols: 8
    readonly property color cBase: gs.host.surface0
    readonly property color cHover: gs.host.surface1
    readonly property color cBorder: Qt.alpha(gs.host.surface2, 0.6)
    readonly property color cAccent: gs.host.accent
    readonly property color cText: gs.host.text
    readonly property color cSub: gs.host.overlay0
    readonly property color cOn: gs.host.crust
    readonly property real cRadius: Radius.outer(gs.host.s(8))
    readonly property string gFont: gs.host.glyphFamily
    readonly property string tFont: gs.host.fontFamily
    readonly property real gSize: gs.host.s(18)
    readonly property real nSize: gs.host.s(12)
    readonly property real tagSize: gs.host.s(8)
    readonly property real tagPad: gs.host.s(3)

    // console web code folder chat music gamepad image email cog, then more apps and moods.
    readonly property var library: [
        "\u{f018d}", "\u{f059f}", "\u{f0169}", "\u{f024b}", "\u{f0b79}", "\u{f075a}", "\u{f0297}", "\u{f02e9}",
        "\u{f01ee}", "\u{f0493}", "\u{f0239}", "\u{f02a4}", "\u{f14f7}", "\u{f082e}", "\u{f03d8}", "\u{f00e3}",
        "\u{f0567}", "\u{f02cb}", "\u{f04c7}", "\u{f04d3}", "\u{f066f}", "\u{f00ed}", "\u{f04ce}", "\u{f02d1}",
        "\u{f14de}", "\u{f0093}", "\u{f140b}", "\u{f0320}", "\u{f01a7}", "\u{f0431}", "\u{f02dc}", "\u{f00d6}",
        "\u{f0474}", "\u{f03eb}", "\u{f01bc}", "\u{f048b}", "\u{f015f}", "\u{f032a}", "\u{f0238}", "\u{f0176}"
    ]

    property int editing: -1
    function glyphAt(i) { return i < glyphs.length ? "" + glyphs[i] : ""; }
    function choose(g) { if (editing >= 0) picked(editing, g); pop.close(); }

    Repeater {
        model: gs.count
        delegate: Item {
            id: slot
            required property int index
            readonly property string g: gs.glyphAt(index)
            width: gs.cell
            height: gs.cell

            Rectangle {
                anchors.fill: parent
                radius: gs.cRadius
                color: slotMa.containsMouse || gs.editing === slot.index && pop.opened ? gs.cHover : gs.cBase
                border.width: gs.editing === slot.index && pop.opened ? 2 : 1
                border.color: gs.editing === slot.index && pop.opened ? gs.cAccent : gs.cBorder
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: slot.g !== "" ? gs.host.glyphNudge(slot.g, gs.gSize) : 0
                text: slot.g !== "" ? slot.g : "" + (slot.index + 1)
                font.family: slot.g !== "" ? gs.gFont : gs.tFont
                font.pixelSize: slot.g !== "" ? gs.gSize : gs.nSize
                color: gs.cText
            }
            Text {
                visible: slot.g !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: gs.tagPad
                text: "" + (slot.index + 1)
                font.family: gs.tFont
                font.pixelSize: gs.tagSize
                color: gs.cSub
            }
            MouseArea {
                id: slotMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    gs.editing = slot.index;
                    pop.x = slot.x;
                    pop.y = slot.y + slot.height + gs.spacing;
                    pop.open();
                }
            }
        }
    }

    Popup {
        id: pop
        padding: gs.host.s(8)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: gs.editing = -1
        background: Rectangle {
            radius: gs.cRadius
            color: gs.cBase
            border.color: gs.cBorder
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: gs.host.s(8)

            Grid {
                columns: gs.pickCols
                spacing: gs.host.s(4)
                Repeater {
                    model: gs.library
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool isCurrent: gs.editing >= 0 && gs.glyphAt(gs.editing) === modelData
                        width: gs.pickCell
                        height: gs.pickCell
                        radius: gs.cRadius
                        color: isCurrent ? gs.cAccent : (pickMa.containsMouse ? gs.cHover : "transparent")
                        Text {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: gs.host.glyphNudge(parent.modelData, gs.gSize)
                            text: parent.modelData
                            font.family: gs.gFont
                            font.pixelSize: gs.gSize
                            color: parent.isCurrent ? gs.cOn : gs.cText
                        }
                        MouseArea {
                            id: pickMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gs.choose(parent.modelData)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: gs.host.s(6)
                SettingsPathField {
                    Layout.fillWidth: true
                    host: gs.host
                    placeholder: "Paste any Nerd Font glyph"
                    value: gs.editing >= 0 ? gs.glyphAt(gs.editing) : ""
                    onCommitted: v => { if (v.trim() !== "") gs.choose(v.trim()); }
                }
                SettingsBtn {
                    host: gs.host
                    label: "#"
                    onClicked: gs.choose("")
                }
            }
        }
    }
}
