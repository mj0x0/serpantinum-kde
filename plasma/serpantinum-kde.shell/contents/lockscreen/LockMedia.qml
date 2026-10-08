// v2's now-playing strip on Plasma's MPRIS model. No visualiser: cava lives in the session.
import QtQuick
import QtQuick.Layouts
import QtCore
import Qt5Compat.GraphicalEffects
import org.kde.plasma.private.mpris as Mpris

LockCard {
    id: box
    implicitHeight: box.lock.s(96)

    Mpris.Mpris2Model { id: mpris }
    readonly property var player: mpris.currentPlayer
    readonly property bool active: player !== null && player !== undefined
                                   && player.playbackStatus !== Mpris.PlaybackStatus.Stopped && player.track !== ""
    readonly property bool playing: active && player.playbackStatus === Mpris.PlaybackStatus.Playing

    // Remote covers are blocked in the greeter; the session caches every cover under md5(url + "\n").
    readonly property string coversDir: StandardPaths.writableLocation(StandardPaths.RuntimeLocation) + "/quickshell/music/covers/"
    readonly property string artUrl: active && player.artUrl ? "" + player.artUrl : ""
    readonly property string artSource: artUrl === "" ? ""
                                        : (artUrl.startsWith("file://") ? artUrl : coversDir + Qt.md5(artUrl + "\n") + "_art.jpg")
    property int artRetry: 0

    function formatTime(us) {
        var sec = Math.floor((us || 0) / 1000000);
        var m = Math.floor(sec / 60), s = sec % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        interval: 1000
        running: box.playing && box.lock.wingsReveal > 0.98
        repeat: true
        onTriggered: box.player.updatePosition()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: box.lock.s(10)
        spacing: box.lock.s(10)

        Rectangle {
            id: artRect
            Layout.preferredWidth: box.lock.s(60)
            Layout.preferredHeight: box.lock.s(60)
            Layout.alignment: Qt.AlignVCenter
            radius: box.lock.radius
            color: box.lock.surface1
            border.width: 1
            border.color: box.playing ? box.lock.mauve : box.lock.surface1
            clip: true

            Text {
                anchors.centerIn: parent
                text: "󰎈"
                font.family: box.lock.iconFont
                font.pixelSize: box.lock.s(22)
                color: box.lock.subtext0
                visible: art.status !== Image.Ready
            }
            Image {
                id: art
                anchors.fill: parent
                source: box.artSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: false
                onStatusChanged: if (status === Image.Error && box.artRetry < 5) retry.restart()
            }
            // The session may still be downloading the cover; look again shortly.
            Timer {
                id: retry
                interval: 2000
                onTriggered: { box.artRetry++; var s = art.source; art.source = ""; art.source = s; }
            }
            Connections { target: box; function onArtSourceChanged() { box.artRetry = 0; } }
            Rectangle { id: artMask; anchors.fill: parent; radius: artRect.radius; visible: false }
            OpacityMask {
                anchors.fill: parent
                source: art
                maskSource: artMask
                visible: art.status === Image.Ready
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: box.lock.s(2)

            Item {
                id: titleClip
                Layout.fillWidth: true
                implicitHeight: titleText.implicitHeight
                clip: true
                readonly property int gap: box.lock.s(30)
                readonly property bool overflow: titleText.implicitWidth > width
                property real scroll: 0.0

                Row {
                    spacing: titleClip.gap
                    x: titleClip.overflow ? -titleClip.scroll * (titleText.implicitWidth + titleClip.gap) : 0
                    Text {
                        id: titleText
                        text: box.active ? (box.player.track || "Unknown Track") : "Nothing is playing"
                        font.family: box.lock.uiFont
                        font.weight: Font.Black
                        font.pixelSize: box.lock.s(13)
                        color: box.lock.text
                        onTextChanged: titleClip.scroll = 0.0
                    }
                    Text {
                        text: titleText.text
                        font.family: box.lock.uiFont
                        font.weight: Font.Black
                        font.pixelSize: box.lock.s(13)
                        color: box.lock.text
                        visible: titleClip.overflow
                    }
                }
                SequentialAnimation {
                    loops: Animation.Infinite
                    running: titleClip.overflow
                    PauseAnimation { duration: 3000 }
                    NumberAnimation { target: titleClip; property: "scroll"; from: 0.0; to: 1.0; duration: (titleText.implicitWidth + titleClip.gap) * 25 }
                    PropertyAction { target: titleClip; property: "scroll"; value: 0.0 }
                }
            }
            Text {
                Layout.fillWidth: true
                text: box.active ? (box.player.artist || "Unknown Artist") : ""
                font.family: box.lock.uiFont
                font.weight: Font.Medium
                font.pixelSize: box.lock.s(10)
                color: box.lock.subtext1
                elide: Text.ElideRight
                visible: box.active && text !== ""
            }
            Text {
                Layout.fillWidth: true
                text: box.active ? (box.formatTime(box.player.position) + " / " + box.formatTime(box.player.length)) : "--:-- / --:--"
                font.family: box.lock.uiFont
                font.weight: Font.Bold
                font.pixelSize: box.lock.s(10)
                color: box.lock.subtext0
                elide: Text.ElideRight
                visible: box.active
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: box.lock.s(4)
            IconButton {
                size: box.lock.s(28)
                cornerRadius: box.lock.r(8)
                buttonIcon: "󰒮"
                iconFontSize: box.lock.s(14)
                accentColor: box.lock.surface1
                textColor: isHoveredOrHighlighted ? box.lock.text : box.lock.overlay2
                onClicked: if (box.active && box.player.canGoPrevious) box.player.Previous()
            }
            IconButton {
                size: box.lock.s(32)
                cornerRadius: box.lock.r(10)
                buttonIcon: box.playing ? "󰏤" : "󰐊"
                iconFontSize: box.lock.s(16)
                accentColor: box.lock.surface1
                textColor: box.playing ? box.lock.green : box.lock.text
                onClicked: if (box.active && box.player.canControl) box.player.PlayPause()
            }
            IconButton {
                size: box.lock.s(28)
                cornerRadius: box.lock.r(8)
                buttonIcon: "󰒭"
                iconFontSize: box.lock.s(14)
                accentColor: box.lock.surface1
                textColor: isHoveredOrHighlighted ? box.lock.text : box.lock.overlay2
                onClicked: if (box.active && box.player.canGoNext) box.player.Next()
            }
        }
    }
}
