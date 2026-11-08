// The current tint as a circle; the palette's circles drop down from it.
import "../../services/layout"
import QtQuick
import QtQuick.Controls

Item {
    id: tp
    required property var host
    property var options: []      // [{ key, color }]
    property string current: ""
    signal picked(string value)
    implicitWidth: tp.host.s(44)
    implicitHeight: tp.host.s(32)

    readonly property real cell: tp.host.s(26)
    readonly property real gap: tp.host.s(7)
    function colorOf(k) {
        for (var i = 0; i < options.length; i++) if (options[i].key === k) return options[i].color;
        return tp.host.overlay0;
    }

    Rectangle {
        anchors.fill: parent
        radius: Radius.outer(tp.host.s(8))
        color: tpMa.containsMouse || pop.opened ? tp.host.surface1 : tp.host.surface0
        border.color: Qt.alpha(tp.host.surface2, 0.6)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            anchors.centerIn: parent
            width: tp.host.s(16)
            height: width
            radius: width / 2
            color: tp.colorOf(tp.current)
        }
    }
    MouseArea {
        id: tpMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pop.opened ? pop.close() : pop.open()
    }
    Popup {
        id: pop
        y: tp.height + tp.host.s(6)
        x: tp.width - width
        padding: tp.host.s(8)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: Rectangle {
            radius: Radius.outer(tp.host.s(8))
            color: tp.host.surface0
            border.color: Qt.alpha(tp.host.surface2, 0.6)
            border.width: 1
        }
        contentItem: Item {
            implicitWidth: tp.options.length * (tp.cell + tp.gap) - tp.gap
            implicitHeight: tp.cell
            SettingsSwatches {
                host: tp.host
                anchors.fill: parent
                options: tp.options
                current: tp.current
                onPicked: v => { tp.picked(v); pop.close(); }
            }
        }
    }
}
