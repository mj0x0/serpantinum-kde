import QtQuick

// Drag or click anywhere on the track. Reports percent; the caller owns the value,
// so the fill follows PipeWire rather than the pointer when something else changes it.
Item {
    id: root

    property real value: 0            // 0..150
    property bool muted: false
    property color accent: "#888"
    property color trackColor: "#333"
    property real radius: 9
    property bool dragging: false

    signal moved(real pct)

    implicitHeight: 18

    function pctAt(mx) {
        return Math.max(0, Math.min(100, (mx / Math.max(1, track.width)) * 100));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: parent.height
        radius: root.radius
        color: root.trackColor

        Rectangle {
            width: parent.width * Math.min(1, root.value / 100)
            height: parent.height
            radius: root.radius
            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: 200; easing.type: Easing.OutQuint }
            }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.muted ? Qt.darker(root.accent, 2.0) : root.accent
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                GradientStop {
                    position: 1.0
                    color: root.muted ? Qt.darker(root.accent, 1.6) : Qt.lighter(root.accent, 1.25)
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4          // easier to grab than the visual height
        hoverEnabled: true
        onPressed: (m) => { root.dragging = true; root.moved(root.pctAt(m.x)); }
        onPositionChanged: (m) => { if (root.dragging) root.moved(root.pctAt(m.x)); }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
    }
}
