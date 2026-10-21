// Multi-select chips: each option toggles in or out of the list, kept in option order.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: tc
    required property var host
    property var options: []      // [{ key, label, glyph }]
    property var current: []
    signal changed(var value)
    spacing: tc.host.s(6)

    readonly property color cOn: tc.host.accent
    readonly property color cOff: tc.host.surface0
    readonly property color cTextOn: tc.host.crust
    readonly property color cText: tc.host.text
    readonly property real cRadius: Radius.outer(tc.host.s(8))
    readonly property real cH: tc.host.s(32)
    readonly property real cPad: tc.host.s(12)
    readonly property real cFont: tc.host.s(11)

    function flip(key) {
        var next = [];
        for (var i = 0; i < options.length; i++) {
            var k = options[i].key;
            var on = current.indexOf(k) !== -1;
            if (k === key) on = !on;
            if (on) next.push(k);
        }
        changed(next);
    }

    Repeater {
        model: tc.options
        delegate: V2.ClickButton {
            required property var modelData
            readonly property bool on: tc.current.indexOf(modelData.key) !== -1
            implicitHeight: tc.cH
            horizontalPadding: tc.cPad
            cornerRadius: tc.cRadius
            buttonText: modelData.label
            buttonIcon: modelData.glyph
            textFontSize: tc.cFont
            accentColor: on ? tc.cOn : tc.cOff
            textColor: on ? tc.cTextOn : tc.cText
            onClicked: tc.flip(modelData.key)
        }
    }
}
