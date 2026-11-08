import QtQuick

Item {
    id: root
    clip: true

    required property QtObject dateTime
    required property QtObject theme

    readonly property real minWidth: 100
    readonly property real minHeight: 100

    // Upstream sweeps the hands continuously; on NVIDIA's OpenGL path every rendered frame leaks, so stepping is the default.
    property bool smoothHands: false
    property var currentTime: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.currentTime = new Date()
    }

    Item {
        width: Math.min(root.width, root.height)
        height: width
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.theme.surface0

            Rectangle {
                width: parent.width * 0.045
                height: parent.height * 0.32
                color: root.theme.text
                anchors.bottom: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                transformOrigin: Item.Bottom
                rotation: (root.currentTime.getHours() % 12) * 30 + root.currentTime.getMinutes() * 0.5 + root.currentTime.getSeconds() * (0.5 / 60)
                radius: width / 2

                Behavior on rotation {
                    enabled: root.smoothHands
                    RotationAnimation {
                        duration: 1000
                        direction: RotationAnimation.Clockwise
                        easing.type: Easing.Linear
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.03
                height: parent.height * 0.42
                color: root.theme.subtext0
                anchors.bottom: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                transformOrigin: Item.Bottom
                rotation: root.currentTime.getMinutes() * 6 + root.currentTime.getSeconds() * 0.1
                radius: width / 2

                Behavior on rotation {
                    enabled: root.smoothHands
                    RotationAnimation {
                        duration: 1000
                        direction: RotationAnimation.Clockwise
                        easing.type: Easing.Linear
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.015
                height: parent.height * 0.46
                color: root.theme.mauve
                anchors.bottom: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                transformOrigin: Item.Bottom
                rotation: root.currentTime.getSeconds() * 6
                radius: width / 2

                Behavior on rotation {
                    enabled: root.smoothHands
                    RotationAnimation {
                        duration: 1000
                        direction: RotationAnimation.Clockwise
                        easing.type: Easing.Linear
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.05
                height: width
                color: root.theme.mauve
                anchors.centerIn: parent
                radius: width / 2
            }
        }
    }
}
