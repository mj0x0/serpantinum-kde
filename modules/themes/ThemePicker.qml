// Compact theme strip on the clipboard's chassis: a search field over one row of palette tiles,
// floating centred or attached to an edge (themes.position); the cursor previews shell-wide.

import "../../services/bar"
import "../../services/layout"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import "../clipboard"
import "../launcher"
import "../popups"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: themeWin

    readonly property bool isVisible: ThemePickerState.open
    visible: isVisible || container.animProgress > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-themes"
    WlrLayershell.keyboardFocus: isVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    mask: Region {
        item: barHole
        intersection: Intersection.Xor
        Region { item: container; intersection: Intersection.Subtract }
    }

    // --- Scaling + theme ----------------------------------------------------
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve:    _theme.mauve
    readonly property color borderDim: Qt.rgba(surface2.r, surface2.g, surface2.b, 0.6)

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite
        running: themeWin.isVisible
    }

    // --- Placement ------------------------------------------------------------
    readonly property string positionSetting: "" + ShellSettings.value("themes.position", "center")
    readonly property string attachEdge: {
        let p = positionSetting;
        return (p === "top" || p === "bottom" || p === "left" || p === "right") ? p : "";
    }
    readonly property bool isCenter: attachEdge === ""
    readonly property bool isSideAttached: attachEdge === "left" || attachEdge === "right"

    // Latched while open, as in the launcher: a bar hiding mid-way must not move the card.
    property bool barHidden: BarState.hidden
    Connections {
        target: BarState
        function onHiddenChanged() { if (!themeWin.isVisible) themeWin.barHidden = BarState.hidden }
    }
    readonly property bool barMatches: !isCenter && BarState.position === attachEdge && !barHidden && BarState.solid
    readonly property real edgeOffset: barMatches ? BarState.slabThickness : 0

    onAttachEdgeChanged: ThemePickerState.hide()
    onBarMatchesChanged: ThemePickerState.hide()

    // One overlay at a time: opening the launcher, the clipboard or a popup closes us.
    Connections {
        target: LauncherState
        function onOpenChanged() { if (LauncherState.open) ThemePickerState.hide() }
    }
    Connections {
        target: ClipboardState
        function onOpenChanged() { if (ClipboardState.open) ThemePickerState.hide() }
    }
    Connections {
        target: Popups
        function onTargetChanged() { if (Popups.target !== "hidden") ThemePickerState.hide() }
    }

    // --- Geometry -----------------------------------------------------------
    readonly property real cornerRadius: Radius.chassis(s(24))
    readonly property real baseWidth: isSideAttached ? Math.round(s(460) / 1.1) : Math.round(s(680) / 1.15)
    readonly property real margin: s(14)
    readonly property real inputH: s(36)
    readonly property real tileW: s(112)
    readonly property real tileH: s(72)
    readonly property real tileGap: s(8)
    readonly property real listHeight: isSideAttached
        ? Math.min(s(520), Math.max(tileH, shown.length * (tileH + tileGap) - tileGap))
        : s(76)
    readonly property real footerH: s(14)
    readonly property real contentHeight: margin * 2 + inputH + s(10) + listHeight + s(6) + footerH
    readonly property real targetHeight: height > 0 ? Math.min(contentHeight, height - edgeOffset) : contentHeight
    property real animatedHeight: targetHeight
    Behavior on animatedHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // --- Model --------------------------------------------------------------
    readonly property string current: "" + ShellSettings.value("appearance.theme", "matugen")
    property var themes: []
    property var shown: []
    property int cursor: -1
    property bool syncing: false
    property bool applied: false
    property var pendingTheme: null

    readonly property var md3: ThemePreview.matugen && ThemePreview.matugen.md3 && typeof ThemePreview.matugen.md3.on_surface === "string"
                               ? ThemePreview.matugen.md3 : null
    readonly property var matugenDots: md3 ? [md3.on_surface, md3.primary, md3.primary, md3.tertiary, md3.secondary, md3.error]
                                           : [_theme.text, _theme.blue, _theme.mauve, _theme.peach, _theme.green, _theme.red]
    function tileDots(t) {
        if (t.isMatugen) return matugenDots;
        var c = t.colors;
        return [c.text, c.blue, c.mauve, c.peach, c.green, c.red];
    }

    Process {
        running: true
        command: ["python3", ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/theme-sort.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                var list = [];
                try { list = JSON.parse(this.text); } catch (e) { list = []; }
                var out = [];
                for (var i = 0; i < list.length; i++) if (list[i] && !list[i].isDivider) out.push(list[i]);
                themeWin.themes = out;
                if (themeWin.isVisible) themeWin.sync();
            }
        }
    }

    function matches(t, q) {
        return q === "" || ("" + t.name).toLowerCase().indexOf(q) >= 0;
    }
    function applyFilter() {
        var q = search.text.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < themes.length; i++) if (matches(themes[i], q)) out.push(themes[i]);
        shown = out;
    }
    function indexOfCurrent() {
        for (var i = 0; i < shown.length; i++) if (shown[i].id === current) return i;
        return -1;
    }
    // Filter and land the cursor on the current theme without previewing anything on the way.
    function sync() {
        syncing = true;
        search.text = "";
        applyFilter();
        // The model reset dropped the view's current item; an unchanged cursor would never re-sync it.
        cursor = -1;
        cursor = indexOfCurrent();
        syncing = false;
        Qt.callLater(positionCursor);
    }
    function positionCursor() {
        if (cursor >= 0) tileList.positionViewAtIndex(cursor, ListView.Contain);
    }
    function onQuery() {
        if (syncing) return;
        applyFilter();
        var next = shown.length > 0 ? 0 : -1;
        if (cursor === next) preview(); else cursor = next;
    }
    function step(d) {
        if (shown.length === 0) return;
        var next = cursor < 0 ? 0 : Math.max(0, Math.min(shown.length - 1, cursor + d));
        cursor = next;
    }
    onCursorChanged: {
        if (cursor >= 0) tileList.positionViewAtIndex(cursor, ListView.Contain);
        if (!syncing) preview();
    }

    // --- Preview / apply ----------------------------------------------------
    function preview() {
        var t = shown[cursor];
        if (!t) return;
        // Clearing while a commit is pending would flash the stale colors.json theme.
        if (t.id === current && ThemePreview.committed === "") ThemePreview.clear();
        else if (t.isMatugen) ThemePreview.showMatugen();
        else ThemePreview.show(t);
    }

    function applyCurrent() {
        if (applied) return;
        var t = shown[cursor];
        if (!t) return;
        applied = true;
        if (t.id !== current) {
            ShellSettings.setValue("appearance.theme", t.id);
            pendingTheme = t;
            ThemePreview.commit(t.id);
        }
        ThemePickerState.hide();
    }

    function cancel() { ThemePickerState.hide(); }

    // Leave the preview on what colors.json will hold: a pending commit's theme, else the file itself.
    function restorePreview() {
        var p = pendingTheme;
        if (ThemePreview.committed === "") ThemePreview.clear();
        else if (!p || p.id !== ThemePreview.committed) return;
        else if (p.isMatugen) ThemePreview.showMatugen();
        else ThemePreview.show(p);
    }

    // --- Open / close -------------------------------------------------------
    Timer { id: focusTimer; interval: 50; onTriggered: search.forceInputFocus() }
    Timer { id: focusRetryTimer; interval: 200; onTriggered: search.forceInputFocus() }

    onIsVisibleChanged: {
        if (isVisible) {
            barHidden = BarState.hidden;
            LauncherState.hide();
            Popups.hide();
            ClipboardState.hide();
            applied = false;
            if (ThemePreview.committed === "") pendingTheme = null;
            sync();
            search.forceInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
        } else {
            focusTimer.stop();
            focusRetryTimer.stop();
            restorePreview();
        }
    }

    // Click outside the card closes; the close path puts the preview back.
    MouseArea { anchors.fill: parent; enabled: themeWin.isVisible; onClicked: themeWin.cancel() }

    Item {
        id: barHole
        readonly property bool active: themeWin.isVisible && !themeWin.barHidden
        readonly property real t: BarState.bandThickness
        x: (active && BarState.position === "right") ? themeWin.width - t : 0
        y: (active && BarState.position === "bottom") ? themeWin.height - t : 0
        width: !active ? 0 : (BarState.isVertical ? t : themeWin.width)
        height: !active ? 0 : (BarState.isVertical ? themeWin.height : t)
    }

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
            fillColor: themeWin.base
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

    component Tile : Rectangle {
        id: tile
        required property var modelData
        required property int index
        readonly property bool selected: index === themeWin.cursor
        readonly property bool committed: modelData.id === themeWin.current
        readonly property var dots: themeWin.tileDots(modelData)
        width: themeWin.isSideAttached ? ListView.view.width : themeWin.tileW
        height: themeWin.tileH
        radius: Radius.inner(themeWin.s(8), themeWin.s(12))
        color: themeWin.surface0
        border.width: selected ? 1.5 : 1
        border.color: selected ? themeWin.text : themeWin.borderDim

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: themeWin.s(14)
            spacing: themeWin.s(5)
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    width: themeWin.s(10); height: width; radius: width / 2
                    color: tile.dots[index]
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: themeWin.s(8)
            y: themeWin.s(14) + themeWin.s(10) + themeWin.s(12)
            text: "" + tile.modelData.name
            color: tile.selected ? themeWin.text : themeWin.subtext0
            font.family: Fonts.ui
            font.pixelSize: themeWin.s(11)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Rectangle {
            visible: tile.committed
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: themeWin.s(8)
            width: themeWin.s(6); height: width; radius: width / 2
            color: themeWin.text
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (tile.selected) themeWin.applyCurrent(); else themeWin.cursor = tile.index; }
        }
    }

    // --- CONTAINER: grows from an edge, or fades in centred -------------------
    Item {
        id: container

        property real animProgress: themeWin.isVisible ? 1.0 : 0.0
        // Keyed on the Behavior's own target so open and close never swap easings.
        Behavior on animProgress {
            id: progBehavior
            NumberAnimation {
                readonly property bool opening: progBehavior.targetValue > 0.5
                duration: opening ? 220 : 150
                easing.type: opening ? Easing.OutBack : Easing.InQuad
                easing.overshoot: 1.15
            }
        }

        readonly property real r: Math.max(0, Math.min(themeWin.cornerRadius, (themeWin.isSideAttached ? width : height) * 0.5))
        readonly property bool showFillets: !themeWin.isCenter && r > 0.5

        x: themeWin.attachEdge === "left" ? themeWin.edgeOffset
         : themeWin.attachEdge === "right" ? themeWin.width - themeWin.edgeOffset - width
         : Math.floor((themeWin.width - width) / 2)
        y: themeWin.attachEdge === "top" ? themeWin.edgeOffset
         : themeWin.attachEdge === "bottom" ? themeWin.height - themeWin.edgeOffset - height
         : Math.floor((themeWin.height - height) / 2)

        width: themeWin.isSideAttached ? themeWin.baseWidth * animProgress : themeWin.baseWidth
        height: themeWin.isCenter ? themeWin.animatedHeight
              : themeWin.isSideAttached ? themeWin.animatedHeight : themeWin.animatedHeight * animProgress

        opacity: themeWin.isCenter ? Math.min(1, animProgress) : 1
        scale: themeWin.isCenter ? 0.96 + 0.04 * animProgress : 1
        transformOrigin: Item.Center

        MouseArea { anchors.fill: parent }

        // Apply must not depend on the search field holding focus; Escape is doubled harmlessly (cancel is idempotent).
        Shortcut { sequences: ["Return", "Enter"]; enabled: themeWin.isVisible; onActivated: themeWin.applyCurrent() }
        Shortcut { sequence: "Escape"; enabled: themeWin.isVisible; onActivated: themeWin.cancel() }

        Fillet { visible: container.showFillets && themeWin.attachEdge === "top";    x: -container.r;                  y: 0;                              vertexX: "right"; vertexY: "top" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "top";    x: container.width;               y: 0;                              vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "bottom"; x: -container.r;                  y: container.height - container.r; vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "bottom"; x: container.width;               y: container.height - container.r; vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "left";   x: 0;                             y: -container.r;                   vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "left";   x: 0;                             y: container.height;               vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "right";  x: container.width - container.r; y: -container.r;                   vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && themeWin.attachEdge === "right";  x: container.width - container.r; y: container.height;               vertexX: "right"; vertexY: "top" }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            color: themeWin.base
            radius: container.r
            topLeftRadius:     (themeWin.attachEdge === "top"    || themeWin.attachEdge === "left")  ? 0 : container.r
            topRightRadius:    (themeWin.attachEdge === "top"    || themeWin.attachEdge === "right") ? 0 : container.r
            bottomLeftRadius:  (themeWin.attachEdge === "bottom" || themeWin.attachEdge === "left")  ? 0 : container.r
            bottomRightRadius: (themeWin.attachEdge === "bottom" || themeWin.attachEdge === "right") ? 0 : container.r
            clip: true

            Rectangle {
                id: blobMask
                anchors.fill: parent
                radius: bgCard.radius
                topLeftRadius: bgCard.topLeftRadius
                topRightRadius: bgCard.topRightRadius
                bottomLeftRadius: bgCard.bottomLeftRadius
                bottomRightRadius: bgCard.bottomRightRadius
                color: "white"
                visible: false
                layer.enabled: true
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: blobMask
                }

                Rectangle {
                    width: parent.width * 0.45
                    height: width
                    radius: width / 2
                    x: (parent.width * 0.5 - width / 2) + Math.cos(themeWin.globalOrbitAngle) * themeWin.s(120)
                    y: (parent.height * 0.4 - height / 2) + Math.sin(themeWin.globalOrbitAngle) * themeWin.s(90)
                    color: themeWin.mauve
                    opacity: 0.05
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: themeWin.margin
                visible: width > 0 && height > 0
                clip: true

                // Fixed size and edge-glued, so the growing card reveals the strip instead of re-flowing it.
                Item {
                    id: body
                    width: themeWin.baseWidth - themeWin.margin * 2
                    height: themeWin.contentHeight - themeWin.margin * 2
                    x: themeWin.attachEdge === "right" ? parent.width - width : 0
                    y: themeWin.attachEdge === "bottom" ? parent.height - height : 0

                    V2.Input {
                        id: search
                        anchors.left: parent.left
                        anchors.right: countLabel.left
                        anchors.rightMargin: themeWin.s(10)
                        y: 0
                        height: themeWin.inputH
                        baseColor: themeWin.surface0
                        accentColor: themeWin.mauve
                        textColor: themeWin.text
                        subTextColor: themeWin.subtext0
                        borderColor: themeWin.borderDim
                        cornerRadius: Radius.outer(themeWin.s(10))
                        fontPixelSize: themeWin.s(12)
                        leadingIcon: "\u{f0349}"
                        showClearButton: true
                        placeholderText: "Search themes…"
                        onTextChanged: themeWin.onQuery()

                        Keys.onUpPressed: (event) => { themeWin.step(-1); event.accepted = true; }
                        Keys.onDownPressed: (event) => { themeWin.step(1); event.accepted = true; }
                        // Left/Right move the cursor only while there is no query for the caret to walk.
                        Keys.onLeftPressed: (event) => {
                            event.accepted = search.text === "";
                            if (event.accepted) themeWin.step(-1);
                        }
                        Keys.onRightPressed: (event) => {
                            event.accepted = search.text === "";
                            if (event.accepted) themeWin.step(1);
                        }
                    }

                    Text {
                        id: countLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: search.verticalCenter
                        text: themeWin.shown.length + "/" + themeWin.themes.length
                        color: themeWin.overlay0
                        font.family: Fonts.ui
                        font.pixelSize: themeWin.s(11)
                        horizontalAlignment: Text.AlignRight
                    }

                    ListView {
                        id: tileList
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: themeWin.inputH + themeWin.s(10)
                        height: themeWin.listHeight
                        orientation: themeWin.isSideAttached ? ListView.Vertical : ListView.Horizontal
                        spacing: themeWin.tileGap
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: themeWin.shown
                        currentIndex: themeWin.cursor
                        highlightFollowsCurrentItem: true
                        delegate: Tile {}

                        // A plain wheel steps the strip; Flickable only maps it onto a vertical view.
                        WheelHandler {
                            enabled: !themeWin.isSideAttached
                            onWheel: event => themeWin.step(event.angleDelta.y < 0 || event.angleDelta.x < 0 ? 1 : -1)
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: "Enter to apply"
                        color: themeWin.overlay0
                        font.family: Fonts.ui
                        font.pixelSize: themeWin.s(10)
                    }
                }
            }
        }
    }
}
