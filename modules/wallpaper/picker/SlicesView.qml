import "../../../services/layout"
import QtQuick
import QtMultimedia

Item {
    id: root

    property var picker
    property alias currentIndex: view.currentIndex

    function snapTo(index) {
        view.forceLayout();
        view.positionViewAtIndex(index, ListView.Center);
        view.currentIndex = index;
    }

    function selectedRect() {
        const it = view.currentItem;
        if (!it || it.width <= 0)
            return null;
        return it.mapToItem(root, 0, 0, Math.max(1, it.width - picker.spacing), it.height);
    }

    ListView {
        id: view
        anchors.fill: parent
        
        opacity: picker.isReady ? 1.0 : 0.0
        anchors.margins: picker.isReady ? 0 : picker.s(40)
        
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }
        Behavior on anchors.margins { NumberAnimation { duration: 700; easing.type: Easing.OutExpo } }

        spacing: 0
        orientation: ListView.Horizontal
        clip: false

        interactive: !picker.isApplying
        cacheBuffer: 2000

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((picker.itemWidth * 1.5 + picker.spacing) / 2)
        preferredHighlightEnd: (width / 2) + ((picker.itemWidth * 1.5 + picker.spacing) / 2)
        
        highlightMoveDuration: picker.initialFocusSet ? 500 : 0
        focus: true
        
        onCurrentIndexChanged: picker.noteItemMove()

        // New items slide+fade in — enabled once focus has been snapped
        add: Transition {
            enabled: picker.allowAddAnimation
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 400; easing.type: Easing.OutBack }
            }
        }
        addDisplaced: Transition {
            enabled: picker.allowAddAnimation
            NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutCubic }
        }

        header: Item { width: Math.max(0, (view.width / 2) - ((picker.itemWidth * 1.5) / 2)) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((picker.itemWidth * 1.5) / 2)) }

        model: picker.activeModel

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton

            onWheel: (wheel) => {
                if (picker.isApplying) {
                    wheel.accepted = true;
                    return;
                }
                let dx = wheel.angleDelta.x;
                let dy = wheel.angleDelta.y;
                picker.wheelStep(Math.abs(dx) > Math.abs(dy) ? dx : dy);
                wheel.accepted = true;
            }
        }

        delegate: Item {
            id: delegateRoot
            
            readonly property string safeFileName: fileName !== undefined ? String(fileName) : ""
            
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property bool isVisuallyEnlarged: isCurrent
            
            readonly property bool isVideo: safeFileName.startsWith("000_")
            readonly property bool matchesFilter: picker.checkItemMatchesFilter(safeFileName, isVideo, picker.cacheVersion, picker.currentFilter)
            
            readonly property real targetWidth: isVisuallyEnlarged ? (picker.itemWidth * 1.5) : (picker.itemWidth * 0.5)
            readonly property real targetHeight: isVisuallyEnlarged ? (picker.itemHeight + picker.s(30)) : picker.itemHeight
            
            property bool isPlayingVideo: false

            Timer {
                id: videoPlayTimer
                interval: 250
                running: delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo && !picker.isFilterAnimating && !picker.isItemAnimating
                onTriggered: {
                    if (delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo) {
                        delegateRoot.isPlayingVideo = true;
                        previewPlayer.play();
                    }
                }
            }

            onIsVisuallyEnlargedChanged: {
                if (!isVisuallyEnlarged) {
                    isPlayingVideo = false;
                    videoPlayTimer.stop();
                    previewPlayer.stop();
                }
            }
            
            width: matchesFilter ? (targetWidth + picker.spacing) : 0
            visible: width > 0.1 || opacity > 0.01
            opacity: matchesFilter ? (isVisuallyEnlarged ? 1.0 : 0.6) : 0.0
            
            scale: matchesFilter ? 1.0 : 0.5

            height: matchesFilter ? targetHeight : 0
            // A released delegate loses its parent before it dies; undefined resets the anchor.
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: picker.s(15)

            z: isVisuallyEnlarged ? 10 : 1
            
            Behavior on scale { enabled: picker.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on width { enabled: picker.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on height { enabled: picker.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: picker.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

            Item {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: ((picker.itemHeight - height) / 2) * picker.skewFactor
                
                width: parent.width > 0 ? parent.width * (targetWidth / (targetWidth + picker.spacing)) : 0
                height: parent.height

                transform: Matrix4x4 {
                    property real s: picker.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
                
                MouseArea {
                    anchors.fill: parent
                    enabled: delegateRoot.matchesFilter && !picker.isApplying
                    onClicked: {
                        view.currentIndex = index
                        picker.applyWallpaper(delegateRoot.safeFileName, delegateRoot.isVideo)
                    }
                }

                Image {
                    anchors.fill: parent
                    source: fileUrl !== undefined ? fileUrl : ""
                    sourceSize: Qt.size(1, 1)
                    fillMode: Image.Stretch
                    visible: true
                    asynchronous: true
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: picker.borderWidth
                    Rectangle { anchors.fill: parent; color: picker.theme.base }
                    clip: true

                    Image {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: picker.s(-50)
                        width: (picker.itemWidth * 1.5) + ((picker.itemHeight + picker.s(30)) * Math.abs(picker.skewFactor)) + picker.s(50)
                        height: picker.itemHeight + picker.s(30)
                        fillMode: Image.PreserveAspectCrop
                        source: fileUrl !== undefined ? fileUrl : ""
                        asynchronous: true

                        transform: Matrix4x4 {
                            property real s: -picker.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    
                    MediaPlayer {
                        id: previewPlayer
                        source: delegateRoot.isPlayingVideo ? "file://" + picker.srcDir + "/" + picker.getCleanName(delegateRoot.safeFileName) : ""
                        audioOutput: AudioOutput { muted: true }
                        videoOutput: previewOutput
                        loops: MediaPlayer.Infinite
                    }

                    VideoOutput {
                        id: previewOutput
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: picker.s(-50)
                        width: (picker.itemWidth * 1.5) + ((picker.itemHeight + picker.s(30)) * Math.abs(picker.skewFactor)) + picker.s(50)
                        height: picker.itemHeight + picker.s(30)
                        fillMode: VideoOutput.PreserveAspectCrop
                        visible: delegateRoot.isPlayingVideo && previewPlayer.playbackState === MediaPlayer.PlayingState

                        transform: Matrix4x4 {
                            property real s: -picker.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    
                    Rectangle {
                        visible: delegateRoot.isVideo && (!delegateRoot.isPlayingVideo || previewPlayer.playbackState !== MediaPlayer.PlayingState)
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: picker.s(10)
                        width: picker.s(32)
                        height: picker.s(32)
                        radius: Radius.outer(picker.s(6))
                        color: Qt.rgba(picker.theme.base.r, picker.theme.base.g, picker.theme.base.b, 0.6)
                        transform: Matrix4x4 {
                            property real s: -picker.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                        
                        Canvas {
                            anchors.fill: parent
                            anchors.margins: picker.s(8)
                            property real scaleTrigger: picker.s(1)
                            onScaleTriggerChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                var s = picker.s;
                                ctx.reset();
                                ctx.fillStyle = Qt.rgba(picker.theme.text.r, picker.theme.text.g, picker.theme.text.b, 0.93);
                                ctx.beginPath();
                                ctx.moveTo(s(4), 0);
                                ctx.lineTo(s(14), s(8));
                                ctx.lineTo(s(4), s(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }
                }
            }
        }
    }
}
