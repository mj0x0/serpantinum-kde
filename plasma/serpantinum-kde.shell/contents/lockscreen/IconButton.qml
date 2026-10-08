// serpantinum v2's IconButton, without the sound hooks.
import QtQuick

Item {
    id: root
    implicitWidth: size
    implicitHeight: size

    property int size: 44
    property int cornerRadius: 12
    property string buttonIcon: ""
    property int iconFontSize: 18
    property color accentColor: Qt.rgba(1, 1, 1, 0.08)
    property color textColor: "white"
    property bool action_highlight: false

    signal clicked()
    signal triggered()

    property real flashOpacity: 0.0
    property real popScale: 1.0
    readonly property bool isHoveredOrHighlighted: (btnMa.containsMouse || root.action_highlight) && root.enabled

    Rectangle {
        id: btnShape
        anchors.fill: parent
        radius: root.cornerRadius
        clip: true
        color: !root.enabled ? root.accentColor
             : (btnMa.pressed ? Qt.darker(root.accentColor, 1.12)
             : (root.isHoveredOrHighlighted ? Qt.lighter(root.accentColor, 1.12) : root.accentColor))
        opacity: root.enabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        scale: (!root.enabled ? 1.0 : (btnMa.pressed ? 1.08 : (root.isHoveredOrHighlighted ? 1.04 : 1.0))) * root.popScale
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: root; property: "popScale"; to: 1.1; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "popScale"; to: 1.0; duration: 420; easing.type: Easing.OutQuint }
        }

        Text {
            anchors.centerIn: parent
            text: root.buttonIcon
            font.family: "Iosevka Nerd Font"
            font.pixelSize: root.iconFontSize
            color: root.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "white"
            opacity: root.flashOpacity
            PropertyAnimation on opacity { id: flashAnim; to: 0; duration: 400; easing.type: Easing.OutExpo }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: root.enabled
            enabled: root.enabled
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                popAnim.start();
                root.flashOpacity = 0.4;
                flashAnim.start();
                root.clicked();
                root.triggered();
            }
        }
    }
}
