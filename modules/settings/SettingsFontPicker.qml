// Searchable list of installed families, each row drawn in its own font.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: fp
    required property var host
    property string current: ""
    property string query: ""
    signal picked(string family)
    spacing: fp.host.s(6)

    readonly property var families: {
        let seen = {};
        let out = [];
        let all = Qt.fontFamilies();
        for (let i = 0; i < all.length; i++) {
            if (!seen[all[i]]) { seen[all[i]] = true; out.push(all[i]); }
        }
        return out;
    }
    readonly property var matches: {
        let q = fp.query.trim().toLowerCase();
        return q === "" ? fp.families : fp.families.filter(f => f.toLowerCase().indexOf(q) !== -1);
    }

    V2.Input {
        Layout.preferredWidth: fp.host.s(280)
        Layout.preferredHeight: fp.host.s(32)
        placeholderText: "Search " + fp.families.length + " fonts"
        baseColor: fp.host.surface0
        accentColor: fp.host.accent
        textColor: fp.host.text
        subTextColor: fp.host.subtext0
        borderColor: Qt.alpha(fp.host.surface2, 0.6)
        cornerRadius: Radius.outer(fp.host.s(8))
        fontPixelSize: fp.host.s(11)
        onTextEdited: t => fp.query = t
    }

    ListView {
        Layout.preferredWidth: fp.host.s(280)
        Layout.preferredHeight: fp.host.s(180)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: fp.matches
        delegate: Rectangle {
            required property string modelData
            readonly property bool isCurrent: modelData === fp.current
            width: ListView.view.width
            height: fp.host.s(26)
            radius: Radius.outer(fp.host.s(6))
            color: isCurrent ? Qt.alpha(fp.host.accent, 0.18) : (rowMa.containsMouse ? fp.host.surface2 : "transparent")
            Text {
                anchors.fill: parent
                anchors.leftMargin: fp.host.s(10)
                anchors.rightMargin: fp.host.s(10)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: parent.modelData
                font.family: parent.modelData
                font.pixelSize: fp.host.s(11)
                color: parent.isCurrent ? fp.host.accent : fp.host.text
            }
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: fp.picked(parent.modelData)
            }
        }
    }
}
