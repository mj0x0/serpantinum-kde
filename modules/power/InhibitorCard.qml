// One app keeping the machine awake (or blocked from it), on the Bluetooth card chassis.

import "../../services/layout"
import "../../services/power"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: card

    property var inhibition: null     // { who, why, granted, asking }
    property var popup: null

    readonly property bool holding: inhibition !== null && inhibition.granted
    // `who` is an app name or an absolute path (/usr/bin/claude-desktop).
    readonly property string exe: inhibition ? ("" + inhibition.who).split("/").pop() : ""
    readonly property var entry: exe !== "" ? DesktopEntries.heuristicLookup(exe) : null
    readonly property string appName: entry && entry.name ? entry.name : exe

    width: popup ? popup.s(200) : 200
    height: popup ? popup.s(60) : 60

    Rectangle {
        anchors.fill: parent
        radius: Radius.outer(popup.s(14))
        color: Qt.alpha(popup.surface0, 0.9)
        border.width: 1
        border.color: cardMa.containsMouse ? (card.holding ? popup.red : popup.accent)
                    : (card.holding ? Qt.alpha(popup.accent, 0.45) : Qt.alpha(popup.overlay0, 0.5))
        Behavior on border.color { ColorAnimation { duration: 200 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: popup.s(14)
            anchors.rightMargin: popup.s(14)
            spacing: popup.s(10)

            Image {
                Layout.preferredWidth: popup.s(22)
                Layout.preferredHeight: popup.s(22)
                source: Quickshell.iconPath(card.entry && card.entry.icon ? card.entry.icon : card.exe,
                                            "application-x-executable")
                sourceSize: Qt.size(64, 64)
                opacity: card.holding ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Marquee {
                    Layout.fillWidth: true
                    text: card.appName
                    bold: true
                    pixelSize: popup.s(13)
                    color: card.holding ? popup.text : popup.subtext0
                }
                Marquee {
                    Layout.fillWidth: true
                    text: card.inhibition ? card.inhibition.why + (card.holding ? "" : " · blocked") : ""
                    pixelSize: popup.s(10)
                    color: popup.overlay0
                }
            }

            Text {
                text: card.holding ? "\u{f04b3}" : "\u{f073a}"   // md-sleep_off / md-cancel
                font.family: "Iosevka Nerd Font"
                font.pixelSize: popup.s(16)
                color: card.holding ? popup.accent : popup.overlay0
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (card.inhibition) PowerInfo.setAllowed(card.inhibition.who, card.inhibition.why, !card.holding)
        }
    }

    scale: cardMa.containsMouse ? 1.06 : 1.0
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

    // Text that loops like the music title when it doesn't fit: pause, scroll to the clone, snap back.
    component Marquee: Item {
        id: mq
        property string text
        property color color
        property int pixelSize: 12
        property bool bold: false
        readonly property real gap: pixelSize * 2.5
        readonly property bool overflow: main.implicitWidth > width

        implicitHeight: main.implicitHeight
        clip: true

        Row {
            id: strip
            spacing: mq.gap
            Text { id: main; text: mq.text; color: mq.color; font.family: Fonts.ui; font.pixelSize: mq.pixelSize; font.bold: mq.bold }
            Text { visible: mq.overflow; text: mq.text; color: mq.color; font.family: Fonts.ui; font.pixelSize: mq.pixelSize; font.bold: mq.bold }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            running: mq.overflow
            onRunningChanged: if (!running) strip.x = 0
            PauseAnimation { duration: 2500 }
            NumberAnimation { target: strip; property: "x"; from: 0; to: -(main.implicitWidth + mq.gap); duration: (main.implicitWidth + mq.gap) * 25 }
            PropertyAction { target: strip; property: "x"; value: 0 }
        }
    }
}
