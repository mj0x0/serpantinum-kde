// The current wallpaper over the theme page, upstream's theme/ThemeWallpaperPreview.qml:
// a cropped card with the picker button and the file's name and path.

import "../../services/layout"
import "../../services/reusables" as V2
import "../../services/wallpaper"
import "../wallpaper"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

Item {
    id: wpPreviewContainer
    required property var host

    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    Layout.preferredHeight: host.s(220)
    Layout.topMargin: host.s(6)
    Layout.bottomMargin: host.s(4)

    readonly property real borderRadius: Radius.outer(host.s(8))
    readonly property string wallpaperPath: WallpaperService.current

    property real highlightFlash: 0.0
    property int handledHighlightToken: -1
    property string registeredSearchKey: ""

    function resolveTabInfo() {
        let p = wpPreviewContainer.parent;
        let targetTabIdx = -1;
        let targetSubTabIdx = -1;
        while (p) {
            if (targetSubTabIdx === -1 && p.subTabIndex !== undefined && p.subTabIndex >= 0) targetSubTabIdx = p.subTabIndex;
            if (targetTabIdx === -1 && p.tabIndex !== undefined && p.tabIndex >= 0) targetTabIdx = p.tabIndex;
            p = p.parent;
        }
        let r = wpPreviewContainer.host;
        let tab = "";
        let subtab = "";
        if (r && r.tabsModel && targetTabIdx >= 0 && targetTabIdx < r.tabsModel.length) {
            let tModel = r.tabsModel[targetTabIdx];
            tab = tModel.key || "";
            if (tModel.subtabs && targetSubTabIdx >= 0 && targetSubTabIdx < tModel.subtabs.length) {
                subtab = tModel.subtabs[targetSubTabIdx].key || "";
            }
        }
        return { tab: tab, subtab: subtab };
    }

    function registerWithSearch() {
        let r = wpPreviewContainer.host;
        if (!r || typeof r.registerSearchItem !== "function") return;
        let info = resolveTabInfo();
        wpPreviewContainer.registeredSearchKey = info.tab + "|" + info.subtab + "|wallpaper";
        r.registerSearchItem({
            id: "wallpaper",
            title: "Wallpaper",
            desc: "Select and preview current wallpaper",
            tab: info.tab,
            subtab: info.subtab,
            icon: "\u{f0e09}",
            keywords: "wallpaper background image video select screen current desktop",
            target: wpPreviewContainer
        });
    }

    function unregisterFromSearch() {
        let r = wpPreviewContainer.host;
        if (!r || typeof r.unregisterSearchItem !== "function") return;
        if (wpPreviewContainer.registeredSearchKey !== "") r.unregisterSearchItem(wpPreviewContainer.registeredSearchKey);
    }

    function ensureVisibleInFlickable() {
        let p = wpPreviewContainer.parent;
        let flick = null;
        while (p) {
            if (p.contentY !== undefined && p.contentHeight !== undefined) {
                flick = p;
                break;
            }
            p = p.parent;
        }
        if (flick) {
            let targetPos = wpPreviewContainer.mapToItem(flick.contentItem, 0, 0);
            if (targetPos) {
                let viewTop = flick.contentY;
                let viewBottom = flick.contentY + flick.height;
                if (targetPos.y < viewTop || targetPos.y + wpPreviewContainer.height > viewBottom) {
                    flick.contentY = Math.max(0, Math.min(targetPos.y - flick.height / 2 + wpPreviewContainer.height / 2, flick.contentHeight - flick.height));
                }
            }
        }
    }

    function triggerHighlightAnimation() {
        highlightAnimation.restart();
        wpPreviewContainer.ensureVisibleInFlickable();
        ensureVisibleTimer.restart();
    }

    function checkHighlight() {
        let r = wpPreviewContainer.host;
        if (!r || r.highlightToken === undefined) return;
        if (r.highlightToken === wpPreviewContainer.handledHighlightToken) return;
        if (r.highlightedSettingId && (r.highlightedSettingId === "wallpaper" || r.highlightedSettingId === "wallpaper_preview")) {
            wpPreviewContainer.handledHighlightToken = r.highlightToken;
            r.highlightedSettingId = "";
            highlightDelayTimer.restart();
        }
    }

    Connections {
        target: wpPreviewContainer.host
        ignoreUnknownSignals: true
        function onHighlightTokenChanged() {
            wpPreviewContainer.checkHighlight();
        }
    }

    onVisibleChanged: {
        searchRegTimer.restart();
        if (visible) {
            wpPreviewContainer.checkHighlight();
        }
    }

    Timer {
        id: searchRegTimer
        interval: 10
        repeat: false
        onTriggered: wpPreviewContainer.registerWithSearch()
    }

    Timer {
        id: ensureVisibleTimer
        interval: 320
        repeat: false
        onTriggered: wpPreviewContainer.ensureVisibleInFlickable()
    }

    Timer {
        id: highlightDelayTimer
        interval: 80
        repeat: false
        onTriggered: wpPreviewContainer.triggerHighlightAnimation()
    }

    SequentialAnimation {
        id: highlightAnimation
        PropertyAction { target: wpPreviewContainer; property: "highlightFlash"; value: 0.0 }
        NumberAnimation { target: wpPreviewContainer; property: "highlightFlash"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: wpPreviewContainer; property: "highlightFlash"; from: 1.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
    }

    Component.onCompleted: {
        searchRegTimer.restart();
        checkHighlight();
    }

    Component.onDestruction: {
        unregisterFromSearch();
    }

    Rectangle {
        id: wpCardMask
        anchors.fill: parent
        radius: wpPreviewContainer.borderRadius
        color: "black"
        visible: false
        layer.enabled: true
    }

    Item {
        id: wpCardContent
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            id: wpCardBg
            anchors.fill: parent
            radius: wpPreviewContainer.borderRadius
            color: wpPreviewContainer.host.surface0
        }

        // Decoded at the card's size: a 4K wallpaper is not held at full resolution for a thumbnail.
        Image {
            id: wpCardImage
            anchors.fill: parent
            source: WallpaperService.still !== "" ? "file://" + WallpaperService.still : ""
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false
            visible: source !== ""
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: wpPreviewContainer.host.s(64)
            radius: wpPreviewContainer.borderRadius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: Qt.rgba(0, 0, 0, 0.35) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
            }
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: wpCardContent
        maskEnabled: true
        maskSource: wpCardMask
    }

    Rectangle {
        anchors.fill: parent
        radius: wpPreviewContainer.borderRadius
        color: wpPreviewContainer.host.accent
        opacity: wpPreviewContainer.highlightFlash * 0.2
        visible: opacity > 0.001
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    V2.IconButton {
        id: videoIndicator
        visible: WallpaperService.isVideo
        anchors.centerIn: parent
        size: wpPreviewContainer.host.s(50)
        cornerRadius: wpPreviewContainer.host.s(16)
        iconFontSize: wpPreviewContainer.host.s(20)
        buttonIcon: "\u{f040a}"
        centerInk: true
        accentColor: wpPreviewContainer.host.surface0
        textColor: wpPreviewContainer.host.text
        opacity: 1.0
        enabled: false
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: wpPreviewContainer.host.s(12)
        spacing: wpPreviewContainer.host.s(12)

        V2.ClickButton {
            id: wpSelectBtn
            Layout.preferredHeight: wpPreviewContainer.host.s(32)
            cornerRadius: wpPreviewContainer.borderRadius
            horizontalPadding: wpPreviewContainer.host.s(14)
            buttonIcon: "\u{f0e09}"
            iconFontSize: wpPreviewContainer.host.s(15)
            buttonText: "Select wallpaper"
            textFontSize: wpPreviewContainer.host.s(11)
            accentColor: wpPreviewContainer.host.accent
            textColor: wpPreviewContainer.host.base
            contentAlignment: Qt.AlignHCenter
            onClicked: WallpaperState.toggle()
        }

        Item { Layout.fillWidth: true }

        MouseArea {
            id: wpPathMa
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitWidth: wpPathCol.implicitWidth
            implicitHeight: wpPathCol.implicitHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (wpPreviewContainer.wallpaperPath !== "") {
                    let escapeBash = function(str) { return String(str).replace(/(["\\$`])/g, '\\$1'); };
                    Quickshell.execDetached(["bash", "-c", "xdg-open \"$(dirname \"" + escapeBash(wpPreviewContainer.wallpaperPath) + "\")\""]);
                }
            }

            ColumnLayout {
                id: wpPathCol
                anchors.right: parent.right
                spacing: wpPreviewContainer.host.s(1)

                Text {
                    text: {
                        if (!wpPreviewContainer.wallpaperPath) return "No Wallpaper Selected";
                        let fn = wpPreviewContainer.wallpaperPath.split("/").pop();
                        return fn || wpPreviewContainer.wallpaperPath;
                    }
                    font.family: wpPreviewContainer.host.fontFamily
                    font.pixelSize: wpPreviewContainer.host.s(12)
                    font.weight: Font.Bold
                    color: "#ffffff"
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideLeft
                    Layout.maximumWidth: Math.max(wpPreviewContainer.host.s(100), Math.min(wpPreviewContainer.host.s(320), wpPreviewContainer.width - wpPreviewContainer.host.s(220)))
                }

                Text {
                    text: wpPreviewContainer.wallpaperPath ? wpPreviewContainer.wallpaperPath.replace(Quickshell.env("HOME"), "~") : ""
                    font.family: wpPreviewContainer.host.fontFamily
                    font.pixelSize: wpPreviewContainer.host.s(10)
                    color: Qt.rgba(1, 1, 1, 0.75)
                    Layout.alignment: Qt.AlignRight
                    elide: Text.ElideLeft
                    Layout.maximumWidth: Math.max(wpPreviewContainer.host.s(100), Math.min(wpPreviewContainer.host.s(320), wpPreviewContainer.width - wpPreviewContainer.host.s(220)))
                    visible: text !== ""
                }
            }
        }
    }
}
