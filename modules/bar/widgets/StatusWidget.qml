// Base for the split status pills: the old StatusPill's sub-pill chrome inside a bar
// pill that vanishes when the widget is grouped, since the group then draws one pill.
// Publishes targetWidth/targetHeight (0 when collapsed) for the placement engine.
import QtQuick

Rectangle {
    id: root
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool grouped: false
    property bool placed: true
    property bool active: true
    property bool revealed: false
    property int revealDelay: 0
    property bool hovered: false
    property real subWidth: 0
    property real targetX: 0
    property real targetY: 0
    readonly property real pillHeight: barWindow.s(34)
    default property alias content: sub.data
    property alias sub: sub
    property color subColor: hovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6)
                                     : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)

    readonly property real pad: grouped ? 0 : barWindow.s(20)
    readonly property real targetWidth: (placed && active && !vertical) ? subWidth + pad : 0
    readonly property real targetHeight: (placed && active && vertical) ? pillHeight + pad : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !root.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && root.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !root.vertical; NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
    Behavior on height { enabled: root.vertical; NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
    visible: placed && ((vertical ? height : width) > 0 || opacity > 0)
    clip: true

    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08 * barWindow.pillBorderAlpha)

    // Staggered reveal, as the old status cluster did.
    property bool initAnimTrigger: false
    Timer { running: root.revealed && !root.initAnimTrigger; interval: root.revealDelay; onTriggered: root.initAnimTrigger = true }
    opacity: initAnimTrigger ? 1 : 0
    transform: Translate { y: root.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    function reportCenter() {
        return root.mapToItem(null, root.width / 2, root.height / 2);
    }

    Rectangle {
        id: sub
        anchors.centerIn: parent
        width: root.vertical ? root.pillHeight : root.subWidth
        height: root.pillHeight
        radius: barWindow.innerRadius
        color: root.subColor
        clip: true
        scale: root.hovered ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on width { enabled: !root.vertical; NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
    }
}
