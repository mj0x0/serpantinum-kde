// One app: M3 state-layer button, icon, up to three indicator pills. Click = launch,
// or minimize when focused (genie into this icon), or activate when unfocused. Right-click = Pin/Unpin.

import "../../services/audio"
import "../../services/theme"
import "../../services/window"
import Quickshell
import QtQuick
import QtQuick.Effects

Item {
    id: item

    required property var group        // { key, id, pinned, windows: [...] }
    required property var dock         // Dock root (geometry + colors)
    required property var panelWindow

    implicitWidth:  dock.buttonSize
    implicitHeight: dock.buttonSize

    readonly property var  windows: group ? (group.windows || []) : []
    readonly property bool running: windows.length > 0
    readonly property bool active: {
        for (let i = 0; i < windows.length; i++) {
            let w = windows[i]
            if (w && w.active && !w.minimized) return true
        }
        return false
    }
    readonly property int dotCount: Math.min(3, windows.length)

    // Electron/Flatpak report reverse-DNS ids, so fall back to the id's last segment.
    function resolveEntry(id) {
        if (!id) return null
        let e = DesktopEntries.heuristicLookup(id)
        if (e) return e
        if (id.indexOf(".") !== -1) {
            e = DesktopEntries.heuristicLookup(id.split(".").pop())
            if (e) return e
        }
        return null
    }

    readonly property var entry: group ? resolveEntry(group.id) : null
    readonly property string iconName: (entry && entry.icon) ? entry.icon : (group ? group.id : "")
    readonly property string label:    (entry && entry.name) ? entry.name : (group ? group.id : "")

    function iconGlobalRect() {
        let win = panelWindow
        let scr = win.screen
        let p = iconImg.mapToItem(win.contentItem, 0, 0)
        let m = dock.edgeMargin
        // The window sits centred on its edge; the compositor never tells us where.
        let winX = dock.vertical
            ? (dock.position === "left" ? scr.x + m : scr.x + scr.width - win.width - m)
            : scr.x + Math.round((scr.width - win.width) / 2)
        let winY = dock.vertical
            ? scr.y + Math.round((scr.height - win.height) / 2)
            : (dock.position === "top" ? scr.y + m : scr.y + scr.height - win.height - m)
        let r = {
            x: Math.round(winX + p.x),
            y: Math.round(winY + p.y),
            w: Math.round(iconImg.width),
            h: Math.round(iconImg.height)
        }
        return r
    }

    function launch() {
        if (entry) entry.execute()
        else Quickshell.execDetached([group.id])
    }

    function trigger() {
        if (!group) return
        if (windows.length === 0) { launch(); return }

        let focused = null
        for (let i = 0; i < windows.length; i++) {
            let w = windows[i]
            if (w && w.active && !w.minimized) { focused = w; break }
        }

        if (focused) {
            let ids = windows.map(function (w) { return w.id })
            WindowService.minimize(ids, iconGlobalRect())
        } else {
            let target = null
            for (let i = 0; i < windows.length; i++) {
                if (windows[i] && windows[i].minimized) { target = windows[i]; break }
            }
            if (!target) target = windows[0]
            if (target) WindowService.activate(target.id)
        }
    }

    // M3 state layer — hover/press highlight behind the icon.
    Rectangle {
        anchors.fill: parent
        radius: dock.buttonRadius
        color: Colors.md3.on_surface
        opacity: tap.pressed ? 0.12 : (hover.hovered ? 0.08 : 0.0)
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    Item {
        id: iconWrap
        width:  dock.iconSize
        height: dock.iconSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // Nudged away from the edge, making room for the pills on the edge side.
        anchors.horizontalCenterOffset: dock.vertical ? (dock.position === "left" ? 2 : -2) : 0
        anchors.verticalCenterOffset:   dock.vertical ? 0 : (dock.position === "top" ? 2 : -2)

        scale: tap.pressed ? 0.90 : 1.0
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        // colorization shifts hue keeping shape; brightness/contrast lift it back out.
        Image {
            id: iconImg
            anchors.fill: parent
            source: Quickshell.iconPath(item.iconName, "application-x-executable")
            sourceSize.width:  dock.iconSize * 2
            sourceSize.height: dock.iconSize * 2
            fillMode: Image.PreserveAspectFit
            smooth: true

            layer.enabled: dock.colorizeIcons
            layer.effect: MultiEffect {
                colorization:      dock.colorizeStrength
                colorizationColor: dock.colorizeColor
                brightness:        dock.colorizeBrightness
                contrast:          dock.colorizeContrast
                saturation:        dock.colorizeSaturation
            }
        }
    }

    // Indicator pills on the edge side — primary when focused, faded otherwise. Pills
    // when few windows, shrinking toward dots when many (M3 taskbar convention).
    Grid {
        id: pills
        columns: dock.vertical ? 1 : 3
        onColumnsChanged: Qt.callLater(pills.forceLayout)
        x: dock.vertical ? (dock.position === "left" ? 4 : parent.width - width - 4) : Math.round((parent.width - width) / 2)
        y: dock.vertical ? Math.round((parent.height - height) / 2) : (dock.position === "top" ? 4 : parent.height - height - 4)
        spacing: 3
        visible: item.running

        Repeater {
            model: item.dotCount
            delegate: Rectangle {
                width:  dock.vertical ? 3 : (item.windows.length <= 3 ? 10 : 4)
                height: dock.vertical ? (item.windows.length <= 3 ? 10 : 4) : 3
                radius: 1.5
                color: item.active
                       ? Colors.md3.primary
                       : Qt.rgba(Colors.md3.on_surface.r, Colors.md3.on_surface.g, Colors.md3.on_surface.b, 0.3)
            }
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered && item.running) dock.openPreview(item, item.group)
            else dock.queuePreviewHide()
        }
    }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => { Sounds.playSfx("reusables/iconbutton/click.wav"); if (button === Qt.RightButton) dock.openMenu(item, item.group); else item.trigger(); }
    }
}
