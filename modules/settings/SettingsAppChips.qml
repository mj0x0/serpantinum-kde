// ToggleChips that wrap, with a caption naming what the hovered app needs.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: ac
    required property var host
    property var options: []      // catalog apps: { key, label, glyph, packages, note }
    property var current: []
    property var hovered: null
    signal changed(var value)
    spacing: ac.host.s(6)

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

    Flow {
        Layout.fillWidth: true
        spacing: ac.host.s(6)
        Repeater {
            model: ac.options
            delegate: V2.ClickButton {
                required property var modelData
                readonly property bool on: ac.current.indexOf(modelData.key) !== -1
                implicitHeight: ac.host.s(32)
                horizontalPadding: ac.host.s(12)
                cornerRadius: Radius.outer(ac.host.s(8))
                buttonText: modelData.label
                buttonIcon: modelData.glyph || ""
                textFontSize: ac.host.s(11)
                accentColor: on ? ac.host.accent : ac.host.surface0
                textColor: on ? ac.host.crust : ac.host.text
                onClicked: ac.flip(modelData.key)
                onIsHoveredOrHighlightedChanged: {
                    if (isHoveredOrHighlighted) ac.hovered = modelData;
                    else if (ac.hovered && ac.hovered.key === modelData.key) ac.hovered = null;
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.minimumHeight: ac.host.s(30)
        text: {
            var a = ac.hovered;
            if (!a) return "Hover an app for the packages it needs and any manual step";
            var p = (a.packages || []).join(", ");
            return "Needs: " + (p || "nothing extra") + (a.note ? "\n" + a.note : "");
        }
        font.family: ac.host.fontFamily
        font.pixelSize: ac.host.s(11)
        color: ac.host.subtext0
        wrapMode: Text.Wrap
    }
}
