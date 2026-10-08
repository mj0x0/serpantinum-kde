// Material 3 island dock, grounded flush to one screen edge (dock.position), Latte-style
// rather than a floating capsule. Auto-hides after inactivity, reveals on its edge.

import "../../services/audio"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "../../services/window"
import Quickshell
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    required property var panelWindow

    // Exposed to shell.qml for the window input mask (reveal trigger + dock).
    readonly property Item maskItem: revealZone
    readonly property Item blurItem: island

    // Frosted glass: translucent surface + compositor blur behind (see shell.qml).
    property bool frosted:    ShellSettings.value("dock.frosted", false) === true
    property real frostAlpha: 0.72

    // ── Edge ──────────────────────────────────────────────────────────────
    readonly property string position: {
        let p = "" + ShellSettings.value("dock.position", "bottom");
        return (p === "top" || p === "left" || p === "right") ? p : "bottom";
    }
    readonly property bool vertical: position === "left" || position === "right"
    // A CurveRenderer Shape whose fill is still "transparent" at first paint never paints
    // again (Qt 6, cold start only), so the fillets wait for the theme to land.
    readonly property bool themed: Colors.md3.surface.a > 0

    // ── Pinned apps ───────────────────────────────────────────────────────
    // App ids from dock.pinned; right-click an icon to pin or unpin.
    readonly property var pinnedApps: {
        let p = ShellSettings.value("dock.pinned", null)
        return Array.isArray(p) ? p : ["org.kde.dolphin", "firefox", "kitty", "code"]
    }
    function setPinned(group, pin) {
        let next = pinnedApps.filter(id => normId(id) !== group.key)
        if (pin) next.push(group.id)
        ShellSettings.setValue("dock.pinned", next)
    }

    // ── Geometry ──────────────────────────────────────────────────────────
    property int iconSize:       24
    property int buttonSize:     38
    property int buttonRadius:   Radius.inner(11)
    property int itemSpacing:    3
    property int islandPadAlong: 10    // breathing room along the edge, past the end icons
    property int islandPadAcross: 6    // between the icons and the island's long sides
    property int islandRadius:   Radius.chassis(24)    // island corners; matches the launcher
    readonly property int filletRadius: islandRadius
    readonly property bool filleted: themed && filletRadius > 0.5
    property int edgeMargin:     0     // shell.qml PanelWindow margin off the edge (genie rect)

    // Across the edge (thickness) and along it (length).
    readonly property int islandThickness: buttonSize + islandPadAcross * 2
    readonly property int islandLength: (vertical ? grid.height : grid.width) + islandPadAlong * 2
    readonly property int hiddenOffset: islandThickness + 4

    // Same surface as the launcher, so the two read as one family.
    readonly property color islandColor: root.frosted
        ? Qt.rgba(Colors.md3.surface.r, Colors.md3.surface.g, Colors.md3.surface.b, root.frostAlpha)
        : Colors.md3.surface

    // ── Auto-hide ─────────────────────────────────────────────────────────
    property bool autoHide:      ShellSettings.value("dock.autoHide", false) === true
    property int  hideDelay:     Math.max(1, Number(ShellSettings.value("dock.hideDelay", 5)) || 5) * 1000
    property int  triggerThickness: 6  // edge strip that reveals the dock
    property bool revealed:      true

    Timer {
        id: hideTimer
        interval: root.hideDelay
        onTriggered: if (root.autoHide && !winHover.hovered && root.previewGroup === null && root.menuGroup === null) root.revealed = false
    }
    Component.onCompleted: if (autoHide) hideTimer.restart()
    // Turning auto-hide off while hidden would otherwise strand the dock off-screen.
    onAutoHideChanged: {
        if (autoHide) hideTimer.restart();
        else { hideTimer.stop(); revealed = true; }
    }
    // A moved dock shows itself on its new edge, then hides again on schedule.
    onPositionChanged: { revealed = true; if (autoHide) hideTimer.restart(); }

    // ── Hover preview (window list popup) ─────────────────────────────────
    property var  previewGroup: null    // group whose windows to show
    property Item previewItem:  null    // dock icon the popup is anchored to

    Timer {
        id: previewHideTimer
        interval: 180                    // covers the icon→popup pointer transit
        onTriggered: { root.previewGroup = null; root.previewItem = null }
    }
    function openPreview(item, group) {
        if (root.menuGroup !== null) return
        previewHideTimer.stop()
        root.previewItem = item
        root.previewGroup = group
    }
    function keepPreview()      { previewHideTimer.stop() }
    function queuePreviewHide() { previewHideTimer.restart() }

    // Popups open away from the dock's edge.
    readonly property int away: position === "bottom" ? Edges.Top
                              : position === "top"    ? Edges.Bottom
                              : position === "left"   ? Edges.Right : Edges.Left

    // ── Right-click menu ──────────────────────────────────────────────────
    property var  menuGroup: null
    property Item menuItem:  null
    function openMenu(item, group) {
        previewHideTimer.stop()
        root.previewGroup = null
        root.previewItem = null
        root.menuItem = item
        root.menuGroup = group
        menu.visible = true
    }
    function closeMenu() {
        root.menuGroup = null
        root.menuItem = null
        if (root.autoHide && !winHover.hovered) hideTimer.restart()
    }

    // MultiEffect colorization shifts hue while PRESERVING light/dark detail, so icons
    // keep their shape - an alpha mask turns opaque icons into solid squares.
    property bool  colorizeIcons:      ShellSettings.value("dock.tintIcons", false) === true
    property color colorizeColor:      Colors.md3.primary   // accent; onSurface = neutral
    property real  colorizeStrength:   1.0    // colorization 0 (off) .. 1 (full hue)
    property real  colorizeBrightness: 0.35   // lift to counter darkening (-1..1)
    property real  colorizeContrast:   0.10   // -1 .. 1
    property real  colorizeSaturation: 0.0    // -1 grayscale .. 1

    function normId(s) { return (s || "").toString().toLowerCase().trim() }

    readonly property var windowList: WindowService.windows

    // Unified model: pinned first, then unpinned running apps, grouped by appId.
    readonly property var dockModel: {
        let groups = []
        let byKey = ({})

        for (let i = 0; i < pinnedApps.length; i++) {
            let id = "" + pinnedApps[i]
            let g = { key: normId(id), id: id, pinned: true, windows: [] }
            groups.push(g)
            byKey[g.key] = g
        }

        for (let j = 0; j < windowList.length; j++) {
            let wobj = windowList[j]
            if (!wobj) continue
            let k = normId(wobj.appId)
            if (k === "") continue

            let g = byKey[k]
            if (!g) {
                for (let m = 0; m < groups.length; m++) {
                    let gg = groups[m]
                    if (gg.pinned && (gg.key.indexOf(k) !== -1 || k.indexOf(gg.key) !== -1)) {
                        g = gg
                        break
                    }
                }
            }
            if (!g) {
                g = { key: k, id: wobj.appId, pinned: false, windows: [] }
                groups.push(g)
                byKey[k] = g
            }
            g.windows.push(wobj)
        }
        return groups
    }

    // Longer than the island by a fillet at each end, or the window clips them.
    implicitWidth:  vertical ? islandThickness : islandLength + filletRadius * 2
    implicitHeight: vertical ? islandLength + filletRadius * 2 : islandThickness

    // NOT translated: a thin edge strip when hidden, the whole island when revealed.
    // Island-long only, so clicks on the decorative fillets fall through to windows.
    Item {
        id: revealZone
        x: root.vertical ? (root.position === "right" ? root.width - width : 0) : island.x
        y: root.vertical ? island.y : (root.position === "bottom" ? root.height - height : 0)
        width:  root.vertical ? (root.revealed ? root.width : root.triggerThickness) : island.width
        height: root.vertical ? island.height : (root.revealed ? root.height : root.triggerThickness)

        HoverHandler {
            id: winHover
            onHoveredChanged: {
                if (hovered) {
                    root.revealed = true
                    hideTimer.stop()
                } else if (root.autoHide) {
                    hideTimer.restart()
                }
            }
        }
    }

    // Sliding content: the island, its fillets, and the icons. Hides along the edge normal.
    Item {
        id: content
        anchors.fill: parent

        transform: Translate {
            x: (root.revealed || !root.vertical) ? 0 : (root.position === "left" ? -root.hiddenOffset : root.hiddenOffset)
            y: (root.revealed ||  root.vertical) ? 0 : (root.position === "top"  ? -root.hiddenOffset : root.hiddenOffset)
            Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        // One fillet at each end of the island, its vertex in the corner between island and edge.
        Fillet { visible: root.filleted && root.position === "top";    x: island.x - r;                y: island.y;                     vertexX: "right"; vertexY: "top" }
        Fillet { visible: root.filleted && root.position === "top";    x: island.x + island.width;     y: island.y;                     vertexX: "left";  vertexY: "top" }
        Fillet { visible: root.filleted && root.position === "bottom"; x: island.x - r;                y: island.y + island.height - r; vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: root.filleted && root.position === "bottom"; x: island.x + island.width;     y: island.y + island.height - r; vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: root.filleted && root.position === "left";   x: island.x;                    y: island.y - r;                 vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: root.filleted && root.position === "left";   x: island.x;                    y: island.y + island.height;     vertexX: "left";  vertexY: "top" }
        Fillet { visible: root.filleted && root.position === "right";  x: island.x + island.width - r; y: island.y - r;                 vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: root.filleted && root.position === "right";  x: island.x + island.width - r; y: island.y + island.height;     vertexX: "right"; vertexY: "top" }

        // The island: flush to its edge, rounded only on the corners away from it.
        Rectangle {
            id: island
            x: root.vertical ? (root.position === "right" ? parent.width - width : 0) : Math.round((parent.width - width) / 2)
            y: root.vertical ? Math.round((parent.height - height) / 2) : (root.position === "bottom" ? parent.height - height : 0)
            width:  root.vertical ? root.islandThickness : root.islandLength
            height: root.vertical ? root.islandLength : root.islandThickness
            topLeftRadius:     (root.position === "top"    || root.position === "left")  ? 0 : root.islandRadius
            topRightRadius:    (root.position === "top"    || root.position === "right") ? 0 : root.islandRadius
            bottomLeftRadius:  (root.position === "bottom" || root.position === "left")  ? 0 : root.islandRadius
            bottomRightRadius: (root.position === "bottom" || root.position === "right") ? 0 : root.islandRadius
            color: root.islandColor

            // Grid, not Row/Column: it flips between one row and one column.
            Grid {
                id: grid
                anchors.centerIn: parent
                columns: root.vertical ? 1 : (itemRepeater.count || 1)
                onColumnsChanged: Qt.callLater(grid.forceLayout)
                spacing: root.itemSpacing

                Repeater {
                    id: itemRepeater
                    model: root.dockModel
                    delegate: DockItem {
                        required property var modelData
                        group: modelData
                        dock: root
                        panelWindow: root.panelWindow
                    }
                }
            }
        }
    }

    // Hover popup listing the hovered app's windows.
    DockPreview {
        dock: root
        panelWindow: root.panelWindow
    }

    PopupWindow {
        id: menu
        color: "transparent"
        grabFocus: true
        anchor.window: root.panelWindow
        anchor.rect: root.menuItem
                     ? root.menuItem.mapToItem(root.panelWindow.contentItem, 0, 0, root.menuItem.width, root.menuItem.height)
                     : Qt.rect(0, 0, 0, 0)
        anchor.edges: root.away
        anchor.gravity: root.away
        anchor.margins.bottom: root.position === "bottom" ? 8 : 0
        anchor.margins.top:    root.position === "top"    ? 8 : 0
        anchor.margins.left:   root.position === "left"   ? 8 : 0
        anchor.margins.right:  root.position === "right"  ? 8 : 0
        implicitWidth:  menuBg.implicitWidth
        implicitHeight: menuBg.implicitHeight
        // grabFocus unmaps the popup on an outside click.
        onVisibleChanged: if (!visible) root.closeMenu()

        Rectangle {
            id: menuBg
            anchors.fill: parent
            implicitWidth:  menuText.implicitWidth + 32
            implicitHeight: 36
            radius: Radius.scaled(12, 1.5, 24)
            color: Colors.md3.surface_container
            border.width: 1
            border.color: Qt.rgba(Colors.md3.outline.r, Colors.md3.outline.g, Colors.md3.outline.b, 0.15)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Colors.md3.on_surface
                opacity: menuMA.containsMouse ? 0.08 : 0
            }
            Text {
                id: menuText
                anchors.centerIn: parent
                text: root.menuGroup && root.menuGroup.pinned ? "Unpin" : "Pin"
                color: Colors.md3.on_surface
                font.pixelSize: 12
            }
            MouseArea {
                id: menuMA
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Sounds.playSfx("reusables/iconbutton/click.wav");
                    let g = root.menuGroup
                    menu.visible = false
                    if (g) root.setPinned(g, !g.pinned)
                }
            }
        }
    }

    // Concave wedge filling one vertex of its square, the launcher's join shape.
    component Fillet : Shape {
        id: fil
        readonly property real r: root.filletRadius
        property string vertexX: "left"   // left | right
        property string vertexY: "top"    // top | bottom
        readonly property real vx: vertexX === "left" ? 0 : r
        readonly property real ox: vertexX === "left" ? r : 0
        readonly property real vy: vertexY === "top" ? 0 : r
        readonly property real oy: vertexY === "top" ? r : 0
        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.islandColor
            strokeColor: "transparent"
            startX: fil.vx
            startY: fil.vy
            PathLine { x: fil.ox; y: fil.vy }
            PathArc {
                x: fil.vx; y: fil.oy
                radiusX: fil.r; radiusY: fil.r
                direction: ((fil.vertexX === "left") !== (fil.vertexY === "top")) ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathLine { x: fil.vx; y: fil.vy }
        }
    }
}
