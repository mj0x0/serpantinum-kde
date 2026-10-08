import "../../../services/layout"
import "../../../services/theme"
import QtQuick
import QtQuick.Effects
import QtMultimedia

// One thumbnail for the Wall and Hand layouts; the current card plays its video after a beat.
Item {
    id: card

    property var picker
    property string fileName: ""
    property url fileUrl
    property bool current: false
    property real radius: Radius.outer(card.picker.s(12))
    readonly property bool isVideo: card.fileName.startsWith("000_")
    readonly property bool playing: video.item ? video.item.playing : false

    property bool preview: false
    onCurrentChanged: if (!card.current)
        card.preview = false

    Timer {
        interval: 250
        running: card.current && card.isVideo && !card.picker.isFilterAnimating && !card.picker.isItemAnimating
        onTriggered: card.preview = true
    }

    // Sits under the opaque frame; it only exists as the layer's mask.
    Rectangle {
        id: mask
        anchors.fill: content
        radius: card.radius
        layer.enabled: true
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: card.radius
        color: card.picker.theme.base
        border.width: card.current ? card.picker.s(3) : 1
        border.color: card.current ? card.picker.theme.text : card.picker.theme.surface1
        Behavior on border.color {
            ColorAnimation {
                duration: 250
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: card.picker.s(3)
        layer.enabled: card.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Image {
            anchors.fill: parent
            source: card.fileUrl
            sourceSize.height: Math.round(card.height * 1.2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        // Only the current video card owns a player; a grid of hundreds must not.
        Loader {
            id: video
            anchors.fill: parent
            active: card.preview
            sourceComponent: Item {
                readonly property bool playing: previewPlayer.playbackState === MediaPlayer.PlayingState

                MediaPlayer {
                    id: previewPlayer
                    source: "file://" + card.picker.srcDir + "/" + card.picker.getCleanName(card.fileName)
                    audioOutput: AudioOutput {
                        muted: true
                    }
                    videoOutput: previewOutput
                    loops: MediaPlayer.Infinite
                    Component.onCompleted: play()
                }

                VideoOutput {
                    id: previewOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    visible: parent.playing
                }
            }
        }

        Rectangle {
            visible: !card.playing
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: card.picker.s(8)
            width: typeLabel.implicitWidth + card.picker.s(10)
            height: typeLabel.implicitHeight + card.picker.s(4)
            radius: Radius.outer(card.picker.s(4))
            color: Qt.rgba(card.picker.theme.base.r, card.picker.theme.base.g, card.picker.theme.base.b, 0.7)

            Text {
                id: typeLabel
                anchors.centerIn: parent
                text: card.isVideo ? "VID" : "PIC"
                color: card.picker.theme.text
                font.family: Fonts.ui
                font.pixelSize: card.picker.s(9)
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }
}
