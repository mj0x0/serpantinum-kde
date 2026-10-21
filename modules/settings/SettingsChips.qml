// Up to four options: v2's segmented Switch; more: its Dropdown. Same API either way.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick

Item {
    id: ch
    required property var host
    property var options: []
    property string current: ""
    property bool enabled: true
    signal picked(string value)

    readonly property int sel: options.indexOf(current)
    readonly property bool compact: options.length <= 4
    implicitWidth: pick.item ? pick.item.implicitWidth : 0
    implicitHeight: pick.item ? pick.item.implicitHeight : 0
    opacity: enabled ? 1 : 0.4

    // Hoisted for the components below, where `host` may not resolve.
    readonly property color cAccent: ch.host.accent
    readonly property color cBase: ch.host.surface0
    readonly property color cHover: ch.host.surface1
    readonly property color cBorder: Qt.alpha(ch.host.surface2, 0.6)
    readonly property color cText: ch.host.text
    readonly property color cSub: ch.host.subtext0
    readonly property color cOn: ch.host.crust
    readonly property real cRadius: Radius.outer(ch.host.s(8))
    readonly property real cFont: ch.host.s(11)
    readonly property real cH: ch.host.s(32)
    readonly property real segW: ch.host.s(Math.max(120, 58 * options.length))
    property real dropW: ch.host.s(220)

    Loader {
        id: pick
        sourceComponent: ch.compact ? seg : drop
    }
    Component {
        id: seg
        V2.Switch {
            id: sw
            implicitWidth: ch.segW
            implicitHeight: ch.cH
            options: ch.options
            currentIndex: Math.max(0, ch.sel)
            enabled: ch.enabled
            accentColor: ch.cAccent
            baseColor: ch.cBase
            textColor: ch.cSub
            activeTextColor: ch.cOn
            cornerRadius: ch.cRadius
            fontPixelSize: ch.cFont
            onToggled: i => ch.picked(ch.options[i])
            Connections { target: ch; function onSelChanged() { sw.currentIndex = Math.max(0, ch.sel) } }
        }
    }
    Component {
        id: drop
        V2.Dropdown {
            id: dd
            implicitWidth: ch.dropW
            implicitHeight: ch.cH
            options: ch.options
            currentIndex: ch.sel
            placeholderText: "—"
            enabled: ch.enabled
            accentColor: ch.cAccent
            baseColor: ch.cBase
            hoverColor: ch.cHover
            dropdownColor: ch.cBase
            borderColor: ch.cBorder
            textColor: ch.cText
            activeTextColor: ch.cOn
            cornerRadius: ch.cRadius
            fontPixelSize: ch.cFont
            onValueChanged: (i, v) => ch.picked(v)
            Connections { target: ch; function onSelChanged() { dd.currentIndex = ch.sel } }
        }
    }
}
