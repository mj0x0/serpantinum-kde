import QtQuick

Flow {
    id: swf
    required property var host
    property var options: []      // [{ key, color }]
    property string current: ""
    property bool enabled: true
    property bool compact: false
    signal picked(string value)

    spacing: swf.host.s(compact ? 5 : 7)

    // Hoisted: `host` does not resolve inside the delegate, only out here.
    readonly property real cell: swf.host.s(compact ? 20 : 26)
    readonly property real ring: swf.host.s(2)
    readonly property real pad: swf.host.s(4)
    readonly property color ringOn: swf.host.text
    readonly property color ringOff: Qt.alpha(swf.host.surface2, 0.8)

    Repeater {
        model: swf.options
        delegate: Item {
            required property var modelData
            readonly property bool active: modelData.key === swf.current
            width: swf.cell
            height: width

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: parent.active ? swf.ring : 1
                border.color: parent.active ? swf.ringOn : swf.ringOff
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - (parent.active ? 2 * swf.pad : swf.pad)
                height: width
                radius: width / 2
                color: parent.modelData.color
                Behavior on width { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                anchors.fill: parent
                enabled: swf.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: swf.picked(parent.modelData.key)
            }
        }
    }
}
