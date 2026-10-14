import "../shims"
import QtQuick

Item {
    id: root
    clip: true
    visible: LyricsBridge.hasLyrics

    function s(val) {
        return (typeof Scaler !== "undefined") ? Scaler.s(val) : val;
    }

    property bool animate: false

    property real sideMargin: root.s(4)
    property real baseActiveFont: root.s(16)
    property real lineHeight: Math.max(root.s(24), baseActiveFont * 1.4)
    property real lineSpacing: Math.max(root.s(4), baseActiveFont * 0.25)
    readonly property real itemStep: lineHeight + lineSpacing

    property string alignment: "left"
    readonly property int effectiveHorizontalAlignment: {
        if (root.alignment === "center" || root.alignment === "middle") return Text.AlignHCenter;
        if (root.alignment === "right") return Text.AlignRight;
        return Text.AlignLeft;
    }
    readonly property int effectiveTransformOrigin: {
        if (root.alignment === "center" || root.alignment === "middle") return Item.Center;
        if (root.alignment === "right") return Item.Right;
        return Item.Left;
    }

    property int linesBehind: -1
    property int linesAfter: -1
    property int lyricsBehind: -1
    property int lyricsAfter: -1
    readonly property int effectiveLinesBehind: root.linesBehind >= 0 ? root.linesBehind : root.lyricsBehind
    readonly property int effectiveLinesAfter: root.linesAfter >= 0 ? root.linesAfter : root.lyricsAfter

    property real inactiveOpacity: -1

    property color activeLineColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.mauve) ? ThemeBackend.mauve : "#cba6f7"
    property color inactiveLineColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.text) ? ThemeBackend.text : "#cdd6f4"
    property string fontFamily: (typeof ThemeBackend !== "undefined" && ThemeBackend.fontFamily) ? ThemeBackend.fontFamily : "sans-serif"
    property int fontWeight: Font.Bold
    property real centerRatio: 0.44

    property real activeItemCenterY: 0

    Connections {
        target: LyricsBridge
        function onLyricsChanged() {
            root.animate = false;
            root.activeItemCenterY = 0;
        }
        function onCurrentIndexChanged() {
            if (root.activeItemCenterY > 0) {
                root.animate = true;
            }
            if (LyricsBridge.currentIndex >= 0 && lyricsRepeater && lyricsRepeater.count > LyricsBridge.currentIndex) {
                let it = lyricsRepeater.itemAt(LyricsBridge.currentIndex);
                if (it && (LyricsBridge.currentIndex === 0 || it.y > 0)) {
                    root.activeItemCenterY = it.y + it.height / 2;
                }
            }
        }
    }

    readonly property real targetY: {
        let center = root.height * root.centerRatio;
        if (LyricsBridge.currentIndex >= 0 && LyricsBridge.hasLyrics) {
            if (root.activeItemCenterY > 0) {
                return center - root.activeItemCenterY;
            }
            if (lyricsRepeater && lyricsRepeater.count > LyricsBridge.currentIndex) {
                let it = lyricsRepeater.itemAt(LyricsBridge.currentIndex);
                if (it && (LyricsBridge.currentIndex === 0 || it.y > 0)) {
                    return center - (it.y + it.height / 2);
                }
            }
            return center - (LyricsBridge.currentIndex * root.itemStep + root.lineHeight / 2);
        }
        return center - (root.lineHeight / 2);
    }

    Item {
        id: scrollContainer
        width: parent.width
        height: lyricsColumn.height
        y: root.targetY

        Behavior on y {
            enabled: root.animate
            NumberAnimation {
                duration: 650
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!running) {
                        root.animate = false;
                    }
                }
            }
        }

        Column {
            id: lyricsColumn
            width: parent.width
            spacing: root.lineSpacing

            Repeater {
                id: lyricsRepeater
                model: LyricsBridge.lyrics

                delegate: Item {
                    id: lineDelegate
                    width: lyricsColumn.width
                    height: Math.max(root.lineHeight, lineText.implicitHeight)

                    readonly property bool isCurrent: index === LyricsBridge.currentIndex

                    readonly property bool isWithinRange: {
                        let behind = root.effectiveLinesBehind;
                        let after = root.effectiveLinesAfter;
                        if (behind < 0 && after < 0) return true;

                        let cur = (typeof LyricsBridge !== "undefined" && LyricsBridge.currentIndex >= 0) ? LyricsBridge.currentIndex : 0;
                        let diff = index - cur;
                        if (diff < 0) {
                            return behind < 0 || (-diff) <= behind;
                        } else if (diff > 0) {
                            return after < 0 || diff <= after;
                        }
                        return true;
                    }

                    Component.onCompleted: {
                        if (isCurrent && (index === 0 || y > 0)) {
                            root.activeItemCenterY = y + height / 2;
                        }
                    }

                    onIsCurrentChanged: {
                        if (isCurrent && (index === 0 || y > 0)) {
                            root.activeItemCenterY = y + height / 2;
                        }
                    }

                    onYChanged: {
                        if (isCurrent && (index === 0 || y > 0)) {
                            root.activeItemCenterY = y + height / 2;
                        }
                    }

                    onHeightChanged: {
                        if (isCurrent && (index === 0 || y > 0)) {
                            root.activeItemCenterY = y + height / 2;
                        }
                    }

                    Text {
                        id: lineText
                        width: parent.width - (root.sideMargin * 2)
                        x: root.sideMargin
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: root.effectiveHorizontalAlignment
                        wrapMode: Text.WordWrap
                        font.family: root.fontFamily
                        font.weight: root.fontWeight
                        font.pixelSize: root.baseActiveFont
                        color: (index === LyricsBridge.currentIndex && (!modelData.words || modelData.words.length === 0)) ? root.activeLineColor : root.inactiveLineColor
                        opacity: {
                            if (!lineDelegate.isWithinRange) return 0.0;
                            if (index === LyricsBridge.currentIndex) return 1.0;
                            if (root.inactiveOpacity >= 0) return root.inactiveOpacity;
                            return (typeof LyricsBridge !== "undefined" && typeof LyricsBridge.getLineOpacity === "function") ? LyricsBridge.getLineOpacity(index, LyricsBridge.currentIndex) : 0.4;
                        }
                        visible: opacity > 0.0
                        scale: {
                            if (index === LyricsBridge.currentIndex) return 1.0;
                            let d = Math.abs(index - LyricsBridge.currentIndex);
                            if (d === 1) return 0.88;
                            return 0.80;
                        }
                        transformOrigin: root.effectiveTransformOrigin

                        textFormat: (index === LyricsBridge.currentIndex && modelData.words && modelData.words.length > 0) ? Text.StyledText : Text.PlainText

                        text: {
                            if (index === LyricsBridge.currentIndex && modelData.words && modelData.words.length > 0) {
                                return LyricsBridge.renderActiveLineText(modelData, LyricsBridge.currentPosition, root.activeLineColor, root.inactiveLineColor);
                            }
                            return modelData.text !== "" ? modelData.text : "♪";
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 650
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 650
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 650
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
