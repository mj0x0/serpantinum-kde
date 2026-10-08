// Hover popup beside a dock icon: one card per window with a live thumbnail (a KWin
// screencast over PipeWire, as Plasma's Task Manager does), the caption and a close button.
// Needs extra/org.quickshell.serpantinum.desktop installed; without it the cards show the icon.

import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "../../services/window"
import Quickshell
import QtQuick
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

PopupWindow {
    id: preview

    required property var dock
    required property var panelWindow

    // Built for shownGroup, which trails dock.previewGroup: a mapped popup keeps its
    // top-left corner when it resizes, so new content means unmap, then map again.
    property var shownGroup: null
    readonly property var wins: shownGroup ? (shownGroup.windows || []) : []
    Connections {
        target: dock
        function onPreviewGroupChanged() {
            let g = dock.previewGroup;
            if (g === null || preview.shownGroup === null) { remap.stop(); preview.shownGroup = g; return; }
            if (g === preview.shownGroup) return;
            preview.shownGroup = null;
            remap.restart();
        }
    }
    Timer { id: remap; interval: 60; onTriggered: preview.shownGroup = dock.previewGroup }
    // The hovered DockItem already resolved the app's icon; the fallback reuses it.
    readonly property string iconName: dock.previewItem ? dock.previewItem.iconName : ""

    property int thumbH:   160
    property int thumbMinW: 100
    property int thumbMaxW: 320
    property real defaultAspect: 1.6   // until a frame tells us the window's shape
    property int captionH: 20
    property int rowW:     240   // compact list
    property int rowH:     30
    property int padding:  6
    property int maxCasts: 6     // live streams at once; further windows show the icon
    // dock.thumbnails off: a compact caption list, no casts.
    readonly property bool thumbnails: ShellSettings.value("dock.thumbnails", false) === true

    visible: shownGroup !== null && wins.length > 0
    color: "transparent"

    implicitWidth:  bg.implicitWidth
    implicitHeight: bg.implicitHeight

    // Opens away from the dock's edge, centred on the hovered icon, with an 8px gap.
    readonly property int away: dock.away
    anchor.window: panelWindow
    anchor.rect: dock.previewItem
                 ? dock.previewItem.mapToItem(panelWindow.contentItem, 0, 0,
                                              dock.previewItem.width, dock.previewItem.height)
                 : Qt.rect(0, 0, 0, 0)
    anchor.edges: away
    anchor.gravity: away
    anchor.margins.bottom: dock.position === "bottom" ? 8 : 0
    anchor.margins.top:    dock.position === "top"    ? 8 : 0
    anchor.margins.left:   dock.position === "left"   ? 8 : 0
    anchor.margins.right:  dock.position === "right"  ? 8 : 0

    Rectangle {
        id: bg
        anchors.fill: parent
        implicitWidth:  cards.implicitWidth + preview.padding * 2
        implicitHeight: cards.implicitHeight + preview.padding * 2
        radius: Radius.outer(14)
        color: Colors.md3.surface_container
        border.width: 1
        border.color: Qt.rgba(Colors.md3.outline.r, Colors.md3.outline.g, Colors.md3.outline.b, 0.15)

        // Keep the popup open while the pointer is over it.
        HoverHandler {
            onHoveredChanged: hovered ? dock.keepPreview() : dock.queuePreviewHide()
        }

        // A strip along the dock's edge: cards side by side, or stacked beside a side dock.
        Grid {
            id: cards
            x: preview.padding
            y: preview.padding
            columns: (dock.vertical || !preview.thumbnails) ? 1 : (cardRepeater.count || 1)
            onColumnsChanged: Qt.callLater(cards.forceLayout)
            spacing: 6

            Repeater {
                id: cardRepeater
                model: preview.wins
                // Delegates die with the popup, and a dead delegate is a closed cast.
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    width:  preview.thumbnails ? thumbBox.width + 12 : preview.rowW
                    height: preview.thumbnails ? preview.thumbH + preview.captionH + 16 : preview.rowH
                    radius: Radius.outer(10)
                    color: cardMA.containsMouse
                           ? Qt.rgba(Colors.md3.on_surface.r, Colors.md3.on_surface.g, Colors.md3.on_surface.b, 0.08)
                           : "transparent"

                    MouseArea {
                        id: cardMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            WindowService.activate(card.modelData.id)
                            dock.queuePreviewHide()
                        }
                    }

                    // Sized to the window's aspect, so a live frame fills the box, not a letterbox.
                    Rectangle {
                        id: thumbBox
                        visible: preview.thumbnails
                        x: 6; y: 6
                        // From the window's client size, known before the popup maps: a popup
                        // does not grow once shown, so the box must be right from the start.
                        readonly property real aspect: (card.modelData.w > 0 && card.modelData.h > 0)
                            ? card.modelData.w / card.modelData.h
                            : (stream.ready && stream.streamSize.height > 0)
                                ? stream.streamSize.width / stream.streamSize.height : preview.defaultAspect
                        width: Math.round(Math.max(preview.thumbMinW, Math.min(preview.thumbMaxW, preview.thumbH * aspect)))
                        height: preview.thumbH
                        radius: Radius.inner(6)
                        color: Qt.rgba(Colors.md3.on_surface.r, Colors.md3.on_surface.g, Colors.md3.on_surface.b, 0.06)

                        // KWin has no frames for a minimized window, so no cast: the icon shows.
                        TaskManager.ScreencastingRequest {
                            id: cast
                            uuid: (preview.thumbnails && !card.modelData.minimized && card.index < preview.maxCasts)
                                  ? card.modelData.id : ""
                        }
                        // Stays visible: kpipewire only runs a stream while its item is shown,
                        // so hiding this until ready would never let it become ready.
                        PipeWire.PipeWireSourceItem {
                            id: stream
                            anchors.fill: parent
                            nodeId: cast.nodeId
                            // Drawn into a texture up to 4x the box (never past the stream's own size)
                            // and mipmapped, so the shrink averages pixels instead of skipping them.
                            layer.enabled: ready
                            layer.mipmap: true
                            layer.smooth: true
                            layer.textureSize: Qt.size(Math.min(streamSize.width,  Math.round(width  * 4)),
                                                       Math.min(streamSize.height, Math.round(height * 4)))
                        }
                        Image {
                            anchors.centerIn: parent
                            width: 48; height: 48
                            visible: !stream.ready
                            source: Quickshell.iconPath(preview.iconName, "application-x-executable")
                            sourceSize.width: 96
                            sourceSize.height: 96
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: closeBtn.left
                        anchors.top: preview.thumbnails ? thumbBox.bottom : undefined
                        anchors.verticalCenter: preview.thumbnails ? undefined : parent.verticalCenter
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        anchors.topMargin: 4
                        height: preview.captionH
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: (card.modelData.caption && card.modelData.caption.length > 0)
                              ? card.modelData.caption : card.modelData.appId
                        color: card.modelData.active ? Colors.md3.primary : Colors.md3.on_surface
                        font.pixelSize: 12
                    }

                    Rectangle {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.top: preview.thumbnails ? thumbBox.bottom : undefined
                        anchors.verticalCenter: preview.thumbnails ? undefined : parent.verticalCenter
                        anchors.rightMargin: 5
                        anchors.topMargin: 4
                        width: 20; height: 20; radius: 10
                        color: closeMA.containsMouse
                               ? Qt.rgba(Colors.md3.on_surface.r, Colors.md3.on_surface.g, Colors.md3.on_surface.b, 0.15)
                               : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Colors.md3.on_surface
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: closeMA
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                WindowService.closeWindow(card.modelData.id)
                                dock.queuePreviewHide()
                            }
                        }
                    }
                }
            }
        }
    }
}
