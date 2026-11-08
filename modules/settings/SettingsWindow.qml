// The Settings app's own window on the launcher's edge-attached chassis: centred by
// default, or flush to a screen edge (settings.position) with the fillets. The card is
// built on open and torn down once the close animation has run out.

import "../../services/bar"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "../clipboard"
import "../launcher"
import "../popups"
import "../themes"
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: settingsWin

    readonly property bool isVisible: SettingsState.open
    visible: isVisible || container.animProgress > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: isVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    mask: Region {
        item: barHole
        intersection: Intersection.Xor
        Region { item: container; intersection: Intersection.Subtract }
    }

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base

    // --- Placement ------------------------------------------------------------
    readonly property string positionSetting: "" + ShellSettings.value("settings.position", "center")
    readonly property string attachEdge: {
        let p = positionSetting;
        if (p === "top" || p === "bottom" || p === "left" || p === "right") return p;
        if (p === "opposite") {
            let b = BarState.position;
            return b === "bottom" ? "top" : b === "left" ? "right" : b === "right" ? "left" : "bottom";
        }
        return "";
    }
    readonly property bool isCenter: attachEdge === ""
    readonly property bool isSideAttached: attachEdge === "left" || attachEdge === "right"

    // Latched while open, as in the launcher: a bar hiding mid-way must not move the card.
    property bool barHidden: BarState.hidden
    Connections {
        target: BarState
        function onHiddenChanged() { if (!settingsWin.isVisible) settingsWin.barHidden = BarState.hidden }
    }
    readonly property bool barMatches: !isCenter && BarState.position === attachEdge && !barHidden && BarState.solid
    readonly property real edgeOffset: barMatches ? BarState.slabThickness : 0

    onAttachEdgeChanged: SettingsState.hide()
    onBarMatchesChanged: SettingsState.hide()

    // One overlay at a time: opening the launcher, the clipboard, the theme strip or a popup closes us.
    Connections {
        target: LauncherState
        function onOpenChanged() { if (LauncherState.open) SettingsState.hide() }
    }
    Connections {
        target: ClipboardState
        function onOpenChanged() { if (ClipboardState.open) SettingsState.hide() }
    }
    Connections {
        target: ThemePickerState
        function onOpenChanged() { if (ThemePickerState.open) SettingsState.hide() }
    }
    Connections {
        target: Popups
        function onTargetChanged() { if (Popups.target !== "hidden") SettingsState.hide() }
    }

    onIsVisibleChanged: {
        if (isVisible) {
            barHidden = BarState.hidden;
            LauncherState.hide();
            Popups.hide();
            ClipboardState.hide();
            ThemePickerState.hide();
        }
    }

    // --- Geometry -------------------------------------------------------------
    readonly property real cornerRadius: Radius.chassis(s(24))
    readonly property real cardW: Math.min(s(1200), width - edgeOffset - s(24))
    readonly property real cardH: Math.min(s(750), height - edgeOffset - s(24))

    // The only Escape in this window; the card may consume it first (search, a focused field).
    Shortcut {
        sequence: "Escape"
        enabled: settingsWin.isVisible
        onActivated: {
            var it = popupLoader.item;
            if (it && typeof it.handleEscape === "function" && it.handleEscape()) return;
            SettingsState.hide();
        }
    }

    // Click outside the card closes it.
    MouseArea { anchors.fill: parent; enabled: settingsWin.isVisible; onClicked: SettingsState.hide() }

    // The bar's strip along its edge, punched out of our input region.
    Item {
        id: barHole
        readonly property bool active: settingsWin.isVisible && !settingsWin.barHidden
        readonly property real t: BarState.bandThickness
        x: (active && BarState.position === "right") ? settingsWin.width - t : 0
        y: (active && BarState.position === "bottom") ? settingsWin.height - t : 0
        width: !active ? 0 : (BarState.isVertical ? t : settingsWin.width)
        height: !active ? 0 : (BarState.isVertical ? settingsWin.height : t)
    }

    // Concave fillet hugging one vertex of its square: the wedge between the bar
    // and the container's attached side. Non-Items inside resolve `fil`, not parent.
    component Fillet : Shape {
        id: fil
        property string vertexX: "left"   // left | right
        property string vertexY: "top"    // top | bottom
        readonly property real r: container.r
        readonly property real vx: vertexX === "left" ? 0 : r
        readonly property real ox: vertexX === "left" ? r : 0
        readonly property real vy: vertexY === "top" ? 0 : r
        readonly property real oy: vertexY === "top" ? r : 0
        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: settingsWin.base
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

    // --- CONTAINER: grows from an edge, or fades in centred -------------------
    Item {
        id: container

        property real animProgress: settingsWin.isVisible ? 1.0 : 0.0
        // Keyed on the Behavior's own target so open and close never swap easings.
        Behavior on animProgress {
            id: progBehavior
            NumberAnimation {
                readonly property bool opening: progBehavior.targetValue > 0.5
                duration: opening ? (settingsWin.isCenter ? 280 : 220) : (settingsWin.isCenter ? 160 : 150)
                easing.type: opening ? (settingsWin.isCenter ? Easing.OutCubic : Easing.OutBack) : (settingsWin.isCenter ? Easing.InCubic : Easing.InQuad)
                easing.overshoot: 1.15
            }
        }

        readonly property real r: Math.max(0, Math.min(settingsWin.cornerRadius, (settingsWin.isSideAttached ? width : height) * 0.5))
        readonly property bool showFillets: !settingsWin.isCenter && r > 0.5

        x: settingsWin.attachEdge === "left" ? settingsWin.edgeOffset
         : settingsWin.attachEdge === "right" ? settingsWin.width - settingsWin.edgeOffset - width
         : Math.floor((settingsWin.width - width) / 2)
        y: settingsWin.attachEdge === "top" ? settingsWin.edgeOffset
         : settingsWin.attachEdge === "bottom" ? settingsWin.height - settingsWin.edgeOffset - height
         : Math.floor((settingsWin.height - height) / 2)

        width: settingsWin.isSideAttached ? settingsWin.cardW * animProgress : settingsWin.cardW
        height: settingsWin.isCenter || settingsWin.isSideAttached ? settingsWin.cardH : settingsWin.cardH * animProgress

        opacity: settingsWin.isCenter ? Math.min(1, animProgress) : 1
        scale: settingsWin.isCenter ? 0.96 + 0.04 * animProgress : 1
        transformOrigin: Item.Center

        // Swallow clicks on the card so they never reach the catcher above.
        MouseArea { anchors.fill: parent }

        Fillet { visible: container.showFillets && settingsWin.attachEdge === "top";    x: -container.r;                  y: 0;                              vertexX: "right"; vertexY: "top" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "top";    x: container.width;               y: 0;                              vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "bottom"; x: -container.r;                  y: container.height - container.r; vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "bottom"; x: container.width;               y: container.height - container.r; vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "left";   x: 0;                             y: -container.r;                   vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "left";   x: 0;                             y: container.height;               vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "right";  x: container.width - container.r; y: -container.r;                   vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && settingsWin.attachEdge === "right";  x: container.width - container.r; y: container.height;               vertexX: "right"; vertexY: "top" }

        // Fixed size and edge-glued, so the growing container reveals the card instead of re-flowing it.
        Item {
            anchors.fill: parent
            clip: !settingsWin.isCenter

            Loader {
                id: popupLoader
                width: settingsWin.cardW
                height: settingsWin.cardH
                x: settingsWin.attachEdge === "right" ? parent.width - width : 0
                y: settingsWin.attachEdge === "bottom" ? parent.height - height : 0
                active: settingsWin.visible
                sourceComponent: SettingsPopup {
                    attachEdge: settingsWin.attachEdge
                    cardRadius: settingsWin.isCenter ? Radius.eased(settingsWin.s(18)) : container.r
                }
                onLoaded: item.forceActiveFocus()
            }
        }
    }
}
