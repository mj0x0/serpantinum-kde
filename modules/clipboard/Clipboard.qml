// cliphist history on serpantinum v2's edge-attached chassis (see NOTICE), shared with Launcher.qml:
// it grows out of the edge across from the bar; helpers/clip_fetcher.py lists, pins and deletes.

import "../../services/audio"
import "../../services/bar"
import "../../services/caching"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "../launcher"
import "../popups"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../services/reusables" as V2
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: clipWin

    readonly property bool isVisible: ClipboardState.open
    visible: isVisible || container.animProgress > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
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

    Caching { id: paths }
    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve:    _theme.mauve

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite
        running: clipWin.isVisible
    }

    // --- Placement ------------------------------------------------------------
    // "opposite" is upstream's rule: across from the bar, so it never lands on the launcher.
    readonly property string positionSetting: "" + ShellSettings.value("clipboard.position", "opposite")
    readonly property string attachEdge: {
        let p = positionSetting;
        if (p === "top" || p === "bottom" || p === "left" || p === "right") return p;
        let b = BarState.position;
        return b === "bottom" ? "top" : b === "left" ? "right" : b === "right" ? "left" : "bottom";
    }
    readonly property bool isSideAttached: attachEdge === "left" || attachEdge === "right"

    // Latched while open, as in the launcher: a bar hiding mid-way must not move the card.
    property bool barHidden: BarState.hidden
    Connections {
        target: BarState
        function onHiddenChanged() { if (!clipWin.isVisible) clipWin.barHidden = BarState.hidden }
    }
    readonly property bool barMatches: BarState.position === attachEdge && !barHidden && BarState.solid
    readonly property real edgeOffset: barMatches ? BarState.slabThickness : 0

    onAttachEdgeChanged: ClipboardState.hide()
    onBarMatchesChanged: ClipboardState.hide()

    // One overlay at a time: opening either the launcher or a popup closes us.
    Connections {
        target: LauncherState
        function onOpenChanged() { if (LauncherState.open) ClipboardState.hide() }
    }
    Connections {
        target: Popups
        function onTargetChanged() { if (Popups.target !== "hidden") ClipboardState.hide() }
    }

    // --- Views: one history, filtered; images browse as a grid ---------------
    readonly property var views: [
        { key: "recent", glyph: "\u{f02da}", label: "Recent" },   // md-history
        { key: "images", glyph: "\u{f02e9}", label: "Images" },   // md-image
        { key: "text",   glyph: "\u{f09a8}", label: "Text" }      // md-text
    ]
    property string view: "recent"
    readonly property bool gridMode: view === "images"
    readonly property int gridCols: isSideAttached ? 2 : 3
    readonly property int gridRows: isSideAttached ? 3 : 2
    readonly property Item activeView: gridMode ? clipGrid : clipList

    function setView(v) {
        previewOpen = false;
        if (view !== v) {
            view = v;
            applyFilter(searchInput.text);
            if (v !== "recent") loadRest();
        }
        searchInput.forceInputFocus();
    }
    function cycleView(step) {
        let i = 0;
        for (let k = 0; k < views.length; k++) if (views[k].key === view) i = k;
        setView(views[(i + step + views.length) % views.length].key);
    }

    // --- Preview (Tab): the selected clip grows into the list area; Left/Right browse while open ---
    property bool previewOpen: false
    property var previewClip: null
    property rect previewFrom: Qt.rect(0, 0, 0, 0)
    readonly property real previewAreaH: isSideAttached ? s(520) : s(440)

    function selectedRect() {
        let v = activeView;
        let d = v.currentIndex >= 0 ? v.itemAtIndex(v.currentIndex) : null;
        if (!d) return Qt.rect(0, 0, listContainer.width, s(52));
        let p = d.mapToItem(listContainer, 0, 0);
        return Qt.rect(p.x, p.y, d.width, d.height);
    }

    function loadPreview() {
        let i = activeView.currentIndex;
        if (i < 0 || i >= clipModel.count) { previewOpen = false; return; }
        let it = clipModel.get(i);
        previewClip = { id: "" + it.id, type: it.type, content: it.content, meta: it.meta };
        if (it.type !== "image" && expandedId !== "" + it.id) fetchFullText(it.id);
        previewScrollAnim.stop();
        previewScroll.contentY = 0;
    }

    function togglePreview() {
        if (!previewOpen && activeView.currentIndex < 0) return;
        previewFrom = selectedRect();
        if (!previewOpen) loadPreview();
        previewOpen = !previewOpen;
    }

    function previewStep(delta) {
        nav(delta);
        loadPreview();
    }

    function scrollPreview(dy) {
        let f = previewScroll;
        let from = previewScrollAnim.running ? previewScrollAnim.to : f.contentY;
        previewScrollAnim.stop();
        previewScrollAnim.from = f.contentY;
        previewScrollAnim.to = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), from + dy));
        previewScrollAnim.start();
    }

    // --- Geometry (v2 metrics) ----------------------------------------------
    readonly property real cornerRadius: Radius.chassis(s(24))
    readonly property real baseWidth: isSideAttached ? Math.round(s(460) / 1.1) : Math.round(s(680) / 1.15)
    readonly property int maxVisibleClips: isSideAttached ? 7 : 6
    readonly property real targetHeight: previewOpen ? Math.max(listHeight, s(74) + previewAreaH) : listHeight
    readonly property real listHeight: {
        let rev = modelRevision;
        let n = clipModel.count;
        if (n <= 0) return s(64);
        if (gridMode) {
            let cell = Math.floor((baseWidth - s(28)) / gridCols);
            return s(74) + Math.min(Math.ceil(n / gridCols), gridRows) * cell;
        }
        let count = Math.min(n, maxVisibleClips);
        let hasPinned = false;
        let hasRecent = false;
        for (let i = 0; i < count; i++) {
            let it = clipModel.get(i);
            if (it) { if (it.pinned) hasPinned = true; else hasRecent = true; }
        }
        let sections = (hasPinned ? 1 : 0) + (hasRecent ? 1 : 0);
        return s(70) + (sections === 2 ? s(48) : sections === 1 ? s(22) : 0) + count * s(56);
    }
    property real animatedHeight: targetHeight
    Behavior on animatedHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // --- Data -----------------------------------------------------------------
    readonly property string fetcher: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/clip_fetcher.py"
    readonly property string cacheDir: paths.getCacheDir("clipboard")

    ListModel { id: clipModel }
    // Pin toggles restyle rows without changing the count, so the height binding needs a nudge.
    property int modelRevision: 0

    property var allClips: []
    readonly property int pageSize: 60
    readonly property int restSize: 400
    property int clipOffset: 0
    property bool hasMore: true
    property bool fetchPending: false
    property bool restPending: false

    property string expandedId: ""
    property string expandedText: ""
    property bool clearing: false
    property bool isKeyboardNav: false
    property string pendingQuery: ""

    function validId(id) { return /^\d+$/.test("" + id); }

    function toggleExpandCurrent() {
        if (gridMode) return;
        if (clipList.currentIndex >= 0 && clipList.currentItem && typeof clipList.currentItem.toggleExpand === "function")
            clipList.currentItem.toggleExpand();
    }

    // Arrow keys: rows in the list, cells in the grid (a short last row catches a Down).
    function nav(delta) {
        isKeyboardNav = true;
        keyboardNavTimer.restart();
        let v = activeView;
        let n = clipModel.count;
        if (n === 0) return;
        let i = v.currentIndex + delta;
        if (gridMode && delta > 1 && i >= n) {
            if (Math.floor(v.currentIndex / gridCols) >= Math.floor((n - 1) / gridCols)) return;
            i = n - 1;
        }
        if (i >= 0 && i < n) v.currentIndex = i;
    }

    // Live refresh only while open; every open refetches anyway.
    Process {
        running: clipWin.isVisible
        command: ["wl-paste", "--watch", "echo", "1"]
        stdout: SplitParser { onRead: watchDebounce.restart() }
    }
    Timer { id: watchDebounce; interval: 150; onTriggered: clipWin.refresh() }

    Process {
        id: fullTextProc
        stdout: StdioCollector { onStreamFinished: clipWin.expandedText = this.text || "" }
    }

    function fetchFullText(id) {
        expandedText = "";
        expandedId = id ? "" + id : "";
        if (!validId(expandedId)) return;
        fullTextProc.running = false;
        fullTextProc.command = ["cliphist", "decode", expandedId];
        fullTextProc.running = true;
    }

    function isSubsequence(sub, str) {
        let i = 0;
        for (let j = 0; i < sub.length && j < str.length; j++)
            if (sub[i] === str[j]) i++;
        return i === sub.length;
    }

    function syncModel(items) {
        for (let i = 0; i < items.length; i++) {
            let item = items[i];
            if (i < clipModel.count) {
                let cur = clipModel.get(i);
                if (cur.id !== item.id || cur.pinned !== item.pinned || cur.content !== item.content || cur.type !== item.type
                        || cur.meta !== item.meta || cur.sectionCategory !== item.sectionCategory || cur.score !== item.score)
                    clipModel.set(i, item);
            } else {
                clipModel.append(item);
            }
        }
        while (clipModel.count > items.length) clipModel.remove(clipModel.count - 1);
        modelRevision++;
    }

    function applyFilter(query) {
        isKeyboardNav = false;
        keyboardNavTimer.stop();

        let q = (query || "").trim().toLowerCase();
        let filtered = [];
        for (let i = 0; i < allClips.length; i++) {
            let item = allClips[i];
            let type = item.type || "text";
            if (view === "images" && type !== "image") continue;
            if (view === "text" && type !== "text") continue;
            // An image's content is a cache path, so it is searched by its format and size instead.
            let hay = (type === "image" ? (item.meta || "") : (item.content || "")).toLowerCase();
            let quality = -1;
            if (q.length === 0) quality = 0;
            else if (hay === q) quality = 100000;
            else if (hay.startsWith(q)) quality = 50000;
            else if (hay.includes(q)) quality = 10000;
            else if (isSubsequence(q, hay)) quality = 1000;
            if (quality < 0) continue;
            filtered.push({
                id: item.id,
                pinned: Boolean(item.pinned),
                content: item.content || "",
                type: type,
                meta: item.meta || "",
                sectionCategory: item.pinned ? "Pinned" : "Recent",
                score: (item.pinned ? 500000 : 0) + quality
            });
        }

        if (q.length > 0) filtered.sort((a, b) => b.score - a.score);
        else filtered = filtered.filter(it => it.pinned).concat(filtered.filter(it => !it.pinned));

        syncModel(filtered);
        clipList.resetScroll();
        clipGrid.resetScroll();
        activeView.currentIndex = clipModel.count > 0 ? 0 : -1;
    }

    function filter(query) {
        pendingQuery = query;
        filterTimer.restart();
    }
    Timer { id: filterTimer; interval: 80; onTriggered: clipWin.applyFilter(clipWin.pendingQuery) }

    Process {
        id: fetchProc
        // A queued refresh or catch-up fetch starts once the previous run has exited.
        onRunningChanged: {
            if (running) return;
            if (clipWin.fetchPending) {
                clipWin.fetchPending = false;
                clipWin.clipOffset = 0;
                clipWin.hasMore = true;
                clipWin.fetchPage();
            } else if (clipWin.restPending) {
                clipWin.restPending = false;
                clipWin.loadRest();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (clipWin.fetchPending) return;
                try {
                    let txt = this.text.trim();
                    let items = txt.length > 0 ? JSON.parse(txt) : [];
                    if (items.length < clipWin.pageSize) clipWin.hasMore = false;
                    if (clipWin.clipOffset === 0) {
                        clipWin.allClips = items;
                    } else {
                        let seen = {};
                        for (let i = 0; i < clipWin.allClips.length; i++) seen[clipWin.allClips[i].id] = true;
                        for (let i = 0; i < items.length; i++) {
                            if (!seen[items[i].id]) { clipWin.allClips.push(items[i]); seen[items[i].id] = true; }
                        }
                    }
                    clipWin.clipOffset = clipWin.allClips.length;
                    clipWin.applyFilter(searchInput.text);
                    // Filters see the whole history, not just the first page.
                    if (clipWin.view !== "recent") clipWin.loadRest();
                } catch (e) {
                    clipWin.hasMore = false;
                }
            }
        }
    }

    function refresh() {
        clipOffset = 0;
        hasMore = true;
        if (fetchProc.running) { fetchPending = true; return; }
        fetchPage();
    }

    function fetchPage() {
        if (fetchProc.running || !hasMore) return;
        fetchProc.command = ["python3", fetcher, "" + clipOffset, "" + pageSize, cacheDir];
        fetchProc.running = true;
    }

    function loadRest() {
        if (!hasMore) return;
        if (fetchProc.running) { restPending = true; return; }
        fetchProc.command = ["python3", fetcher, "" + clipOffset, "" + restSize, cacheDir];
        fetchProc.running = true;
    }

    function copyClip(id, pinned) {
        if (!validId(id)) return;
        if (pinned) {
            // Re-copying makes a new cliphist entry, so the pin moves to it.
            Quickshell.execDetached(["bash", "-c",
                "cliphist decode " + id + " | wl-copy && (sleep 0.15; n=$(cliphist list | head -n 1 | cut -f1); python3 \"$0\" pin \"$n\" \"$1\") &",
                fetcher, cacheDir]);
        } else {
            Quickshell.execDetached(["bash", "-c", "cliphist decode " + id + " | wl-copy"]);
        }
        ClipboardState.hide();
    }

    function pinClip(id) {
        if (!validId(id)) return;
        Quickshell.execDetached(["python3", fetcher, "pin", "" + id, cacheDir]);
        for (let i = 0; i < allClips.length; i++) {
            if ("" + allClips[i].id === "" + id) { allClips[i].pinned = !allClips[i].pinned; break; }
        }
        applyFilter(searchInput.text);
    }

    function deleteClip(id, index) {
        if (!validId(id)) return;
        Quickshell.execDetached(["python3", fetcher, "delete", "" + id, cacheDir]);
        allClips = allClips.filter(it => "" + it.id !== "" + id);
        if (index >= 0 && index < clipModel.count) clipModel.remove(index);
        modelRevision++;
    }

    function clearAll() {
        allClips = [];
        clipModel.clear();
        modelRevision++;
        clipList.resetScroll();
        clipGrid.resetScroll();
        Quickshell.execDetached(["python3", fetcher, "wipe", cacheDir]);
    }

    Timer {
        id: clearFinishTimer
        onTriggered: { clipWin.clearAll(); clipWin.clearing = false; }
    }

    // Visible rows or tiles leave one after another, then the history is wiped.
    function animateClear() {
        if (clearing || clipModel.count === 0) return;
        clearing = true;
        let v = activeView;
        let items = [];
        for (let i = 0; i < v.contentItem.children.length; i++) {
            let child = v.contentItem.children[i];
            if (child && typeof child.triggerClearSlide === "function"
                    && child.y + child.height >= v.contentY && child.y <= v.contentY + v.height)
                items.push(child);
        }
        items.sort((a, b) => (a.y - b.y) || (a.x - b.x));
        if (items.length === 0) { clearAll(); clearing = false; return; }
        for (let i = 0; i < items.length; i++) items[i].triggerClearSlide(i * 50);
        clearFinishTimer.interval = (items.length - 1) * 50 + 260;
        clearFinishTimer.start();
    }

    function activateIndex(index) {
        if (index < 0 || index >= clipModel.count) return;
        let item = clipModel.get(index);
        if (item) copyClip(item.id, item.pinned);
    }

    // --- Open / close -------------------------------------------------------
    Timer { id: focusTimer; interval: 50; onTriggered: searchInput.forceInputFocus() }
    Timer { id: focusRetryTimer; interval: 200; onTriggered: searchInput.forceInputFocus() }
    Timer { id: keyboardNavTimer; interval: 500; onTriggered: clipWin.isKeyboardNav = false }

    onIsVisibleChanged: {
        if (isVisible) {
            barHidden = BarState.hidden;
            LauncherState.hide();
            Popups.hide();
            previewOpen = false;
            view = "recent";
            searchInput.text = "";
            filterTimer.stop();
            applyFilter("");
            refresh();
            searchInput.forceInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
        } else {
            previewOpen = false;
            clipList.resetScroll();
            clipGrid.resetScroll();
            expandedId = "";
            filterTimer.stop();
            focusTimer.stop();
            focusRetryTimer.stop();
            keyboardNavTimer.stop();
        }
    }

    // Click outside the card closes it.
    MouseArea { anchors.fill: parent; enabled: clipWin.isVisible; onClicked: ClipboardState.hide() }

    Item {
        id: barHole
        readonly property bool active: clipWin.isVisible && !clipWin.barHidden
        readonly property real t: BarState.bandThickness
        x: (active && BarState.position === "right") ? clipWin.width - t : 0
        y: (active && BarState.position === "bottom") ? clipWin.height - t : 0
        width: !active ? 0 : (BarState.isVertical ? t : clipWin.width)
        height: !active ? 0 : (BarState.isVertical ? clipWin.height : t)
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
            fillColor: clipWin.base
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

    // --- CONTAINER: the thing that grows ------------------------------------
    Item {
        id: container

        property real animProgress: clipWin.isVisible ? 1.0 : 0.0
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
        readonly property bool settled: clipWin.isVisible && animProgress > 0.98

        readonly property real r: Math.max(0, Math.min(clipWin.cornerRadius, (clipWin.isSideAttached ? width : height) * 0.5))
        readonly property bool showFillets: r > 0.5

        x: clipWin.attachEdge === "left" ? clipWin.edgeOffset
         : clipWin.attachEdge === "right" ? clipWin.width - clipWin.edgeOffset - width
         : Math.floor((clipWin.width - width) / 2)
        y: clipWin.attachEdge === "top" ? clipWin.edgeOffset
         : clipWin.attachEdge === "bottom" ? clipWin.height - clipWin.edgeOffset - height
         : Math.floor((clipWin.height - height) / 2)

        width: clipWin.isSideAttached ? clipWin.baseWidth * animProgress : clipWin.baseWidth
        height: clipWin.isSideAttached ? clipWin.animatedHeight : clipWin.animatedHeight * animProgress

        MouseArea { anchors.fill: parent }

        Shortcut { sequence: "Ctrl+1"; enabled: clipWin.isVisible; onActivated: clipWin.setView("recent") }
        Shortcut { sequence: "Ctrl+2"; enabled: clipWin.isVisible; onActivated: clipWin.setView("images") }
        Shortcut { sequence: "Ctrl+3"; enabled: clipWin.isVisible; onActivated: clipWin.setView("text") }
        Shortcut { sequence: "Ctrl+Tab"; enabled: clipWin.isVisible; onActivated: clipWin.cycleView(1) }
        Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]; enabled: clipWin.isVisible; onActivated: clipWin.cycleView(-1) }

        Fillet { visible: container.showFillets && clipWin.attachEdge === "top";    x: -container.r;                  y: 0;                              vertexX: "right"; vertexY: "top" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "top";    x: container.width;               y: 0;                              vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "bottom"; x: -container.r;                  y: container.height - container.r; vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "bottom"; x: container.width;               y: container.height - container.r; vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "left";   x: 0;                             y: -container.r;                   vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "left";   x: 0;                             y: container.height;               vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "right";  x: container.width - container.r; y: -container.r;                   vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && clipWin.attachEdge === "right";  x: container.width - container.r; y: container.height;               vertexX: "right"; vertexY: "top" }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            color: clipWin.base
            radius: container.r
            topLeftRadius:     (clipWin.attachEdge === "top"    || clipWin.attachEdge === "left")  ? 0 : container.r
            topRightRadius:    (clipWin.attachEdge === "top"    || clipWin.attachEdge === "right") ? 0 : container.r
            bottomLeftRadius:  (clipWin.attachEdge === "bottom" || clipWin.attachEdge === "left")  ? 0 : container.r
            bottomRightRadius: (clipWin.attachEdge === "bottom" || clipWin.attachEdge === "right") ? 0 : container.r
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
                    x: (parent.width * 0.5 - width / 2) + Math.cos(clipWin.globalOrbitAngle) * clipWin.s(120)
                    y: (parent.height * 0.4 - height / 2) + Math.sin(clipWin.globalOrbitAngle) * clipWin.s(90)
                    color: clipWin.mauve
                    opacity: 0.05
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: clipWin.s(14)
                visible: width > 0 && height > 0
                clip: true

                readonly property bool searchAtBottom: clipWin.attachEdge === "bottom"
                readonly property real inputH: clipWin.s(36)
                readonly property real gap: clipWin.s(10)

                RowLayout {
                    id: searchRow
                    z: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: content.searchAtBottom ? Math.max(0, parent.height - height) : 0
                    height: content.inputH
                    spacing: clipWin.s(8)

                    V2.Input {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: content.inputH
                        baseColor: clipWin.surface0
                        accentColor: clipWin.mauve
                        textColor: clipWin.text
                        subTextColor: clipWin.subtext0
                        borderColor: Qt.rgba(clipWin.surface2.r, clipWin.surface2.g, clipWin.surface2.b, 0.6)
                        cornerRadius: Radius.outer(clipWin.s(12))
                        fontPixelSize: clipWin.s(12)
                        leadingIcon: "󰅌"
                        showClearButton: true
                        placeholderText: clipWin.gridMode ? "Search images" : "Search clipboard"
                        onTextChanged: { clipWin.previewOpen = false; clipWin.filter(text); }

                        // Previewing text, Up/Down scroll it; previewing an image, they step to the next one.
                        Keys.onDownPressed: (event) => {
                            let step = clipWin.gridMode ? clipWin.gridCols : 1;
                            if (!clipWin.previewOpen) clipWin.nav(step);
                            else if (preview.isImage) clipWin.previewStep(step);
                            else clipWin.scrollPreview(clipWin.s(60));
                            event.accepted = true;
                        }
                        Keys.onUpPressed: (event) => {
                            let step = clipWin.gridMode ? -clipWin.gridCols : -1;
                            if (!clipWin.previewOpen) clipWin.nav(step);
                            else if (preview.isImage) clipWin.previewStep(step);
                            else clipWin.scrollPreview(-clipWin.s(60));
                            event.accepted = true;
                        }
                        // Left/Right browse while previewing, and move between tiles while the grid has no query to edit.
                        Keys.onLeftPressed: (event) => {
                            event.accepted = clipWin.previewOpen || (clipWin.gridMode && searchInput.text === "");
                            if (!event.accepted) return;
                            if (clipWin.previewOpen) clipWin.previewStep(-1);
                            else clipWin.nav(-1);
                        }
                        Keys.onRightPressed: (event) => {
                            event.accepted = clipWin.previewOpen || (clipWin.gridMode && searchInput.text === "");
                            if (!event.accepted) return;
                            if (clipWin.previewOpen) clipWin.previewStep(1);
                            else clipWin.nav(1);
                        }
                        Keys.onTabPressed: (event) => { clipWin.togglePreview(); event.accepted = true; }
                        Keys.onBacktabPressed: (event) => { if (!clipWin.previewOpen) clipWin.toggleExpandCurrent(); event.accepted = true; }
                        Keys.onReturnPressed: (event) => { clipWin.activateIndex(clipWin.activeView.currentIndex); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { clipWin.activateIndex(clipWin.activeView.currentIndex); event.accepted = true; }
                        // Delete removes the selected clip unless there is query text after the cursor to delete.
                        Keys.onDeletePressed: (event) => {
                            if (clipWin.previewOpen) { event.accepted = true; return; }
                            if (searchInput.field.cursorPosition < searchInput.text.length) return;
                            let i = clipWin.activeView.currentIndex;
                            if (i >= 0 && i < clipModel.count) clipWin.deleteClip(clipModel.get(i).id, i);
                            event.accepted = true;
                        }
                        Keys.onEscapePressed: (event) => {
                            if (clipWin.previewOpen) clipWin.togglePreview();
                            else ClipboardState.hide();
                            event.accepted = true;
                        }
                    }

                    // Filter switch: the active segment spells out its name.
                    Rectangle {
                        Layout.preferredWidth: viewRow.implicitWidth + clipWin.s(8)
                        Layout.preferredHeight: content.inputH
                        radius: Radius.outer(clipWin.s(12))
                        color: clipWin.surface0
                        border.width: 1
                        border.color: Qt.rgba(clipWin.surface2.r, clipWin.surface2.g, clipWin.surface2.b, 0.6)

                        Row {
                            id: viewRow
                            anchors.centerIn: parent
                            spacing: clipWin.s(2)

                            Repeater {
                                model: clipWin.views
                                delegate: Rectangle {
                                    id: seg
                                    required property var modelData
                                    readonly property bool active: clipWin.view === modelData.key
                                    width: segRow.implicitWidth + clipWin.s(16)
                                    height: content.inputH - clipWin.s(8)
                                    radius: Radius.inset(clipWin.s(9), clipWin.s(4))
                                    color: active ? clipWin.mauve : (segMa.containsMouse ? clipWin.surface1 : "transparent")
                                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Row {
                                        id: segRow
                                        anchors.centerIn: parent
                                        spacing: clipWin.s(5)
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: seg.modelData.glyph
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: clipWin.s(15)
                                            color: seg.active ? clipWin.crust : clipWin.subtext0
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: seg.active
                                            text: seg.modelData.label
                                            font.family: Fonts.ui
                                            font.weight: Font.Bold
                                            font.pixelSize: clipWin.s(11)
                                            color: clipWin.crust
                                        }
                                    }
                                    MouseArea {
                                        id: segMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { Sounds.playSfx("network/switch.wav"); clipWin.setView(seg.modelData.key); }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: clearBtn
                        readonly property bool active: !clipWin.clearing && clipModel.count > 0
                        Layout.preferredWidth: clearRow.implicitWidth + clipWin.s(24)
                        Layout.preferredHeight: content.inputH
                        radius: Radius.outer(clipWin.s(12))
                        color: clearMa.containsMouse && active ? clipWin.surface1 : clipWin.surface0
                        border.width: 1
                        border.color: Qt.rgba(clipWin.surface2.r, clipWin.surface2.g, clipWin.surface2.b, 0.6)
                        opacity: active ? 1 : 0.5
                        scale: clearMa.pressed && active ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                        Row {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: clipWin.s(6)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰆴"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: clipWin.s(14)
                                color: clipWin.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !clipWin.isSideAttached
                                text: "Clear"
                                font.family: Fonts.ui
                                font.weight: Font.Bold
                                font.pixelSize: clipWin.s(11)
                                color: clipWin.text
                            }
                        }
                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: clearBtn.active
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clipWin.animateClear()
                        }
                    }
                }

                Item {
                    id: listContainer
                    z: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: content.searchAtBottom ? 0 : content.inputH + content.gap
                    height: Math.max(0, parent.height - content.inputH - content.gap)
                    clip: true

                    NumberAnimation {
                        id: scrollAnim
                        target: clipList
                        property: "contentY"
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        id: gridScroll
                        target: clipGrid
                        property: "contentY"
                        duration: 260
                        easing.type: Easing.OutCubic
                    }

                    Transition {
                        id: listAddTrans
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 270; easing.type: Easing.OutCubic }
                    }
                    Transition {
                        id: listRemoveTrans
                        NumberAnimation { property: "opacity"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; to: 0.96; duration: 170; easing.type: Easing.OutCubic }
                    }

                    ListView {
                        id: clipList
                        anchors.fill: parent
                        visible: !clipWin.gridMode
                        clip: true
                        model: clipWin.gridMode ? null : clipModel
                        spacing: clipWin.s(4)
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: clipWin.s(600)
                        interactive: !clipWin.clearing && contentHeight > height
                        highlightFollowsCurrentItem: false

                        add: container.settled ? listAddTrans : null
                        remove: container.settled ? listRemoveTrans : null
                        displaced: null

                        function resetScroll() {
                            scrollAnim.stop();
                            positionViewAtBeginning();
                            contentY = 0;
                        }

                        // Row bounds including its section header, estimated when the row isn't instantiated.
                        function itemBounds(idx) {
                            if (idx < 0 || idx >= clipModel.count) return null;
                            let secH = clipWin.s(22);
                            let defaultH = clipWin.s(52);
                            let cur = clipModel.get(idx);
                            let firstInSection = idx === 0 ? !!cur.sectionCategory
                                               : cur.sectionCategory !== clipModel.get(idx - 1).sectionCategory;
                            let obj = itemAtIndex(idx);
                            if (obj) return { top: Math.max(0, obj.y - (firstInSection ? secH : 0)), bottom: obj.y + obj.height };

                            let y = 0;
                            let prevSec = "";
                            for (let i = 0; i <= idx; i++) {
                                let m = clipModel.get(i);
                                let sec = m.sectionCategory || "";
                                let hasSec = sec !== "" && sec !== prevSec;
                                if (hasSec) { y += secH; prevSec = sec; }
                                let o = itemAtIndex(i);
                                let h = o ? o.height : defaultH;
                                if (i === idx) return { top: Math.max(0, y - (hasSec ? secH : 0)), bottom: y + h };
                                y += h + spacing;
                            }
                            return null;
                        }

                        function ensureVisible(idx, animated) {
                            let b = itemBounds(idx);
                            if (!b) return;
                            let curY = scrollAnim.running ? scrollAnim.to : contentY;
                            let maxScroll = Math.max(0, Math.max(contentHeight, b.bottom) - height);
                            let newY = curY;
                            if (b.top < curY) newY = b.top;
                            else if (b.bottom > curY + height) newY = b.bottom - height;
                            newY = Math.max(0, Math.min(maxScroll, newY));
                            if (Math.abs(newY - contentY) <= 0.5) return;
                            scrollAnim.stop();
                            if (animated) {
                                scrollAnim.from = contentY;
                                scrollAnim.to = newY;
                                scrollAnim.start();
                            } else {
                                contentY = newY;
                            }
                        }

                        onMovementStarted: scrollAnim.stop()
                        onCurrentIndexChanged: if (currentIndex >= 0) ensureVisible(currentIndex, clipWin.isKeyboardNav)

                        onContentYChanged: {
                            if (contentY < 0 && !moving && !flicking) contentY = 0;
                            if (clipWin.view === "recent" && clipWin.hasMore && !fetchProc.running && searchInput.text.trim().length === 0
                                    && contentY + height >= contentHeight - clipWin.s(450))
                                clipWin.fetchPage();
                        }

                        section.property: "sectionCategory"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            required property string section
                            width: ListView.view ? ListView.view.width : 0
                            height: clipWin.s(22)
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: clipWin.s(4)
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.section
                                font.family: Fonts.ui
                                font.weight: Font.Bold
                                font.pixelSize: clipWin.s(10.5)
                                color: clipWin.subtext0
                                opacity: 0.85
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            active: clipList.moving || clipList.movingVertically
                            width: clipWin.s(4)
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: clipWin.s(4); radius: clipWin.s(2); color: clipWin.surface2 }
                        }

                        delegate: Item {
                            id: row
                            width: ListView.view ? ListView.view.width : 0
                            height: card.height
                            z: isSelected ? 2 : 1

                            readonly property bool isSelected: index === clipList.currentIndex
                            readonly property string clipId: model.id !== undefined ? "" + model.id : ""

                            scale: cardMa.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                            property bool expanded: false
                            property real expandProgress: expanded ? 1.0 : 0.0
                            Behavior on expandProgress {
                                enabled: !cardMa.draggingV
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutQuart
                                    onRunningChanged: if (!running && row.isSelected) clipList.ensureVisible(clipList.currentIndex, true)
                                }
                            }

                            onClipIdChanged: { expanded = false; dragX = 0; }

                            property real dragX: 0

                            function triggerClearSlide(delayMs) {
                                clearSlideTimer.interval = delayMs;
                                clearSlideTimer.start();
                            }
                            Timer { id: clearSlideTimer; onTriggered: clearSlideAnim.start() }
                            NumberAnimation { id: clearSlideAnim; target: row; property: "dragX"; to: clipList.width * 1.2; duration: 220; easing.type: Easing.OutQuad }
                            NumberAnimation { id: resetAnim; target: row; property: "dragX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation {
                                id: dismissAnim
                                target: row
                                property: "dragX"
                                duration: 200
                                easing.type: Easing.OutQuad
                                onFinished: clipWin.deleteClip(row.clipId, index)
                            }

                            Text {
                                id: textMeasure
                                visible: false
                                width: Math.max(10, clipWin.baseWidth - clipWin.s(96))
                                text: model.type === "image" ? "" : (model.content || "")
                                font.family: Fonts.ui
                                font.pixelSize: clipWin.s(12)
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }

                            function toggleExpand() {
                                if (!card.canExpand) return;
                                expanded = !expanded;
                                expandProgress = Qt.binding(() => row.expanded ? 1.0 : 0.0);
                            }

                            onExpandedChanged: {
                                if (!expanded) return;
                                clipList.currentIndex = index;
                                if (model.type !== "image" && clipWin.expandedId !== clipId) clipWin.fetchFullText(clipId);
                                clipList.ensureVisible(index, true);
                            }

                            Rectangle {
                                id: cardMask
                                width: card.width
                                height: card.height
                                radius: card.radius
                                visible: false
                                layer.enabled: card.isImage && row.expandProgress > 0.01
                            }

                            Rectangle {
                                id: card
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top

                                readonly property bool isImage: model.type === "image"
                                readonly property string imageUrl: isImage && model.content
                                    ? (model.content.startsWith("file://") ? model.content : "file://" + model.content) : ""
                                readonly property bool showingImage: isImage && row.expandProgress > 0.5
                                readonly property bool canExpand: {
                                    if (isImage) return true;
                                    let c = model.content || "";
                                    return c.indexOf("\n") !== -1 || c.length > 45 || textMeasure.lineCount >= 2
                                        || textMeasure.paintedHeight > clipWin.s(18);
                                }
                                readonly property real baseH: clipWin.s(52)
                                readonly property real expandedH: isImage ? clipWin.s(250) : clipWin.s(172)
                                height: baseH + (expandedH - baseH) * row.expandProgress

                                layer.enabled: isImage && row.expandProgress > 0.01
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: cardMask
                                }

                                transform: Translate { x: row.dragX }
                                opacity: Math.max(0.0, 1.0 - Math.abs(row.dragX) / (card.width * 0.75))

                                radius: Radius.outer(clipWin.s(12))
                                color: showingImage ? clipWin.surface0
                                     : row.isSelected ? clipWin.mauve
                                     : cardMa.containsMouse ? Qt.lighter(clipWin.surface1, 1.04) : clipWin.surface1
                                clip: true
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                // The whole image, fitted, once expanded.
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: clipWin.s(6)
                                    source: card.isImage && row.expandProgress > 0.01 ? card.imageUrl : ""
                                    sourceSize.width: 1024
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true; cache: true; smooth: true; mipmap: true
                                    visible: card.isImage && row.expandProgress > 0.01
                                    opacity: Math.max(0.0, (row.expandProgress - 0.15) / 0.85)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    z: 10
                                    radius: card.radius
                                    visible: card.showingImage
                                    color: "transparent"
                                    border.width: row.isSelected ? clipWin.s(2) : 0
                                    border.color: clipWin.mauve
                                }

                                // Drag sideways to delete, down to expand; right-click pins.
                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !clipWin.clearing
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                                    property real startX: 0
                                    property real startY: 0
                                    property bool draggingH: false
                                    property bool draggingV: false

                                    onPressed: (mouse) => {
                                        clipList.currentIndex = index;
                                        let pt = mapToItem(container, mouse.x, mouse.y);
                                        startX = pt.x;
                                        startY = pt.y;
                                        draggingH = false;
                                        draggingV = false;
                                        resetAnim.stop();
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return;
                                        let pt = mapToItem(container, mouse.x, mouse.y);
                                        let dx = pt.x - startX;
                                        let dy = pt.y - startY;
                                        if (!draggingH && !draggingV) {
                                            if (Math.abs(dx) > clipWin.s(6) && Math.abs(dx) > Math.abs(dy)) {
                                                draggingH = true;
                                                preventStealing = true;
                                            } else if (card.canExpand && Math.abs(dy) > clipWin.s(6) && Math.abs(dy) >= Math.abs(dx)) {
                                                draggingV = true;
                                                preventStealing = true;
                                                if (model.type !== "image" && clipWin.expandedId !== row.clipId) clipWin.fetchFullText(row.clipId);
                                            }
                                        }
                                        if (draggingH) {
                                            row.dragX = dx;
                                        } else if (draggingV) {
                                            let dist = clipWin.s(120);
                                            row.expandProgress = row.expanded ? Math.max(0, Math.min(1, 1 + dy / dist))
                                                                              : Math.max(0, Math.min(1, dy / dist));
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        preventStealing = false;
                                        if (draggingH) {
                                            if (Math.abs(row.dragX) > card.width * 0.25) {
                                                dismissAnim.from = row.dragX;
                                                dismissAnim.to = row.dragX > 0 ? card.width * 1.2 : -card.width * 1.2;
                                                dismissAnim.start();
                                            } else {
                                                resetAnim.from = row.dragX;
                                                resetAnim.start();
                                            }
                                            draggingH = false;
                                        } else if (draggingV) {
                                            if (!row.expanded && row.expandProgress > 0.35) row.expanded = true;
                                            else if (row.expanded && row.expandProgress < 0.65) row.expanded = false;
                                            row.expandProgress = Qt.binding(() => row.expanded ? 1.0 : 0.0);
                                            draggingV = false;
                                        } else if (mouse.button === Qt.RightButton) {
                                            clipWin.pinClip(row.clipId);
                                        } else {
                                            clipWin.copyClip(row.clipId, model.pinned);
                                        }
                                    }

                                    onCanceled: {
                                        preventStealing = false;
                                        if (draggingH) { resetAnim.from = row.dragX; resetAnim.start(); draggingH = false; }
                                        if (draggingV) { row.expandProgress = Qt.binding(() => row.expanded ? 1.0 : 0.0); draggingV = false; }
                                    }
                                }

                                // Type glyph for text; a real thumbnail for images.
                                Rectangle {
                                    id: typeIcon
                                    z: 3
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.leftMargin: card.isImage ? clipWin.s(7) : clipWin.s(8)
                                    anchors.topMargin: card.isImage ? clipWin.s(7) : clipWin.s(11)
                                    width: card.isImage ? clipWin.s(38) : clipWin.s(30)
                                    height: width
                                    radius: Radius.inset(clipWin.s(8), clipWin.s(4))
                                    color: (!card.isImage && row.isSelected) ? Qt.rgba(0, 0, 0, 0.15) : clipWin.surface2
                                    clip: true
                                    opacity: Math.max(0.0, 1.0 - row.expandProgress * 2.0)
                                    visible: row.expandProgress < 0.99 && opacity > 0.001
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        anchors.margins: clipWin.s(3)
                                        visible: card.isImage
                                        source: card.isImage ? card.imageUrl : ""
                                        sourceSize: Qt.size(128, 128)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: true; smooth: true; mipmap: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !card.isImage || thumb.status !== Image.Ready
                                        text: card.isImage ? "󰋩" : "󰈙"
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: clipWin.s(14)
                                        color: (!card.isImage && row.isSelected) ? clipWin.crust : clipWin.subtext0
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Rectangle {
                                    id: expandBtn
                                    z: 4
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: clipWin.s(13)
                                    anchors.rightMargin: clipWin.s(8)
                                    width: clipWin.s(26)
                                    height: width
                                    radius: Radius.inset(clipWin.s(7), clipWin.s(4))
                                    visible: card.canExpand
                                    readonly property bool onAccent: row.isSelected && !card.showingImage
                                    color: onAccent ? Qt.rgba(0, 0, 0, expandMa.containsMouse ? 0.22 : 0.15)
                                         : (expandMa.containsMouse ? Qt.lighter(clipWin.surface2, 1.12) : clipWin.surface2)
                                    scale: expandMa.pressed ? 1.08 : (expandMa.containsMouse ? 1.04 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u{f0140}"   // md-chevron_down
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: clipWin.s(16)
                                        rotation: row.expandProgress > 0.5 ? 180 : 0
                                        color: expandBtn.onAccent ? clipWin.crust : (expandMa.containsMouse ? clipWin.text : clipWin.subtext1)
                                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    MouseArea {
                                        id: expandMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { clipList.currentIndex = index; row.toggleExpand(); }
                                    }
                                }

                                Item {
                                    z: 2
                                    anchors.left: typeIcon.right
                                    anchors.leftMargin: clipWin.s(8)
                                    anchors.right: parent.right
                                    anchors.rightMargin: card.canExpand ? clipWin.s(38) : clipWin.s(12)
                                    anchors.top: parent.top
                                    anchors.topMargin: clipWin.s(10)
                                    height: clipWin.s(32)
                                    opacity: Math.max(0.0, 1.0 - row.expandProgress * 2.0)
                                    visible: row.expandProgress < 0.99 && opacity > 0.001
                                    clip: true

                                    Text {
                                        anchors.fill: parent
                                        text: card.isImage ? ("Image" + (model.meta ? "  ·  " + model.meta : "")) : (model.content || "")
                                        font.family: Fonts.ui
                                        font.pixelSize: clipWin.s(12)
                                        font.weight: row.isSelected ? Font.Bold : Font.Normal
                                        color: row.isSelected ? clipWin.crust : clipWin.text
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    z: 3
                                    visible: !card.isImage && row.expandProgress > 0.01
                                    anchors.fill: parent
                                    anchors.leftMargin: clipWin.s(10)
                                    anchors.topMargin: clipWin.s(10)
                                    anchors.bottomMargin: clipWin.s(10)
                                    anchors.rightMargin: card.canExpand ? clipWin.s(42) : clipWin.s(10)
                                    clip: true
                                    opacity: Math.max(0.0, (row.expandProgress - 0.15) / 0.85)

                                    Flickable {
                                        id: previewFlick
                                        anchors.fill: parent
                                        contentWidth: width
                                        contentHeight: previewText.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height
                                        clip: true

                                        ScrollBar.vertical: ScrollBar {
                                            width: clipWin.s(3)
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { radius: clipWin.s(1.5); color: row.isSelected ? Qt.rgba(0, 0, 0, 0.25) : clipWin.surface2 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: (mouse) => {
                                                Sounds.playSfx("system/quick_click.wav");
                                                clipList.currentIndex = index;
                                                if (mouse.button === Qt.RightButton) clipWin.pinClip(row.clipId);
                                                else clipWin.copyClip(row.clipId, model.pinned);
                                            }
                                        }

                                        Text {
                                            id: previewText
                                            width: previewFlick.width
                                            text: row.expandProgress <= 0.01 ? ""
                                                : (clipWin.expandedId === row.clipId && clipWin.expandedText !== "") ? clipWin.expandedText
                                                : (model.content || "")
                                            font.family: Fonts.ui
                                            font.pixelSize: clipWin.s(12)
                                            color: row.isSelected ? clipWin.crust : clipWin.text
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Images browse as tiles: same model, same actions, just a grid.
                    GridView {
                        id: clipGrid
                        anchors.fill: parent
                        visible: clipWin.gridMode
                        clip: true
                        model: clipWin.gridMode ? clipModel : null
                        cellWidth: Math.floor(width / clipWin.gridCols)
                        cellHeight: cellWidth
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: clipWin.s(400)
                        interactive: !clipWin.clearing && contentHeight > height
                        highlightFollowsCurrentItem: false

                        add: container.settled ? listAddTrans : null
                        remove: container.settled ? listRemoveTrans : null

                        function resetScroll() {
                            gridScroll.stop();
                            positionViewAtBeginning();
                            contentY = 0;
                        }

                        function ensureVisible(idx) {
                            let top = Math.floor(idx / clipWin.gridCols) * cellHeight;
                            let y = gridScroll.running ? gridScroll.to : contentY;
                            if (top < y) y = top;
                            else if (top + cellHeight > y + height) y = top + cellHeight - height;
                            y = Math.max(0, Math.min(Math.max(0, contentHeight - height), y));
                            if (Math.abs(y - contentY) <= 0.5) return;
                            gridScroll.stop();
                            gridScroll.from = contentY;
                            gridScroll.to = y;
                            gridScroll.start();
                        }

                        onMovementStarted: gridScroll.stop()
                        onCurrentIndexChanged: if (currentIndex >= 0) ensureVisible(currentIndex)

                        ScrollBar.vertical: ScrollBar {
                            active: clipGrid.moving || clipGrid.movingVertically
                            width: clipWin.s(4)
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: clipWin.s(4); radius: clipWin.s(2); color: clipWin.surface2 }
                        }

                        delegate: Item {
                            id: tile
                            width: clipGrid.cellWidth
                            height: clipGrid.cellHeight

                            readonly property bool isSelected: index === clipGrid.currentIndex
                            readonly property string clipId: model.id !== undefined ? "" + model.id : ""
                            readonly property string imageUrl: model.content
                                ? (model.content.startsWith("file://") ? model.content : "file://" + model.content) : ""

                            function triggerClearSlide(delayMs) {
                                tileClearTimer.interval = delayMs;
                                tileClearTimer.start();
                            }
                            Timer { id: tileClearTimer; onTriggered: tileClearAnim.start() }
                            ParallelAnimation {
                                id: tileClearAnim
                                NumberAnimation { target: tileBody; property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutQuad }
                                NumberAnimation { target: tileBody; property: "scale"; to: 0.85; duration: 220; easing.type: Easing.OutQuad }
                            }

                            Item {
                                id: tileBody
                                anchors.fill: parent
                                anchors.margins: clipWin.s(3)

                                Rectangle {
                                    id: tileMask
                                    anchors.fill: parent
                                    radius: Radius.outer(clipWin.s(12))
                                    visible: false
                                    layer.enabled: true
                                }

                                Rectangle {
                                    id: tileCard
                                    anchors.fill: parent
                                    radius: tileMask.radius
                                    color: clipWin.surface1
                                    scale: tileMa.pressed ? 0.97 : (tileMa.containsMouse ? 1.02 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: tileMask
                                    }

                                    Image {
                                        anchors.fill: parent
                                        source: tile.imageUrl
                                        sourceSize: Qt.size(512, 512)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: true; smooth: true; mipmap: true
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(0, 0, 0, tileMa.containsMouse ? 0.15 : 0.0)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    Rectangle {
                                        visible: model.pinned === true
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: clipWin.s(6)
                                        width: clipWin.s(22)
                                        height: width
                                        radius: width / 2
                                        color: Qt.rgba(clipWin.crust.r, clipWin.crust.g, clipWin.crust.b, 0.8)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u{f0403}"   // md-pin
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: clipWin.s(12)
                                            color: clipWin.mauve
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: clipWin.s(6)
                                        height: clipWin.s(20)
                                        radius: Radius.inset(clipWin.s(8), clipWin.s(4))
                                        color: Qt.rgba(clipWin.crust.r, clipWin.crust.g, clipWin.crust.b, 0.8)
                                        opacity: (tile.isSelected || tileMa.containsMouse) && model.meta ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: clipWin.s(6)
                                            anchors.rightMargin: clipWin.s(6)
                                            verticalAlignment: Text.AlignVCenter
                                            text: model.meta || ""
                                            elide: Text.ElideRight
                                            font.family: Fonts.ui
                                            font.pixelSize: clipWin.s(9.5)
                                            color: clipWin.text
                                        }
                                    }
                                }

                                // Selection ring sits outside the mask so it isn't clipped.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: tileMask.radius
                                    scale: tileCard.scale
                                    color: "transparent"
                                    border.width: tile.isSelected ? clipWin.s(2) : 0
                                    border.color: clipWin.mauve
                                }

                                MouseArea {
                                    id: tileMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !clipWin.clearing
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        Sounds.playSfx("system/quick_click.wav");
                                        clipGrid.currentIndex = index;
                                        if (mouse.button === Qt.RightButton) clipWin.pinClip(tile.clipId);
                                        else clipWin.copyClip(tile.clipId, model.pinned);
                                    }
                                }
                            }
                        }
                    }

                    // Tab preview: the selected clip grows out of its row or tile into the whole list area.
                    Rectangle {
                        id: preview
                        z: 20

                        property real p: clipWin.previewOpen ? 1 : 0
                        Behavior on p {
                            id: previewBehavior
                            NumberAnimation { duration: previewBehavior.targetValue > 0.5 ? 320 : 220; easing.type: Easing.OutExpo }
                        }
                        readonly property var pc: clipWin.previewClip
                        readonly property bool isImage: pc !== null && pc.type === "image"
                        readonly property string fullText: (pc === null || isImage) ? ""
                            : (clipWin.expandedId === pc.id && clipWin.expandedText !== "") ? clipWin.expandedText : (pc.content || "")
                        readonly property real fade: Math.max(0, (p - 0.4) / 0.6)

                        visible: p > 0.001 && pc !== null
                        x: clipWin.previewFrom.x * (1 - p)
                        y: clipWin.previewFrom.y * (1 - p)
                        width: clipWin.previewFrom.width + (parent.width - clipWin.previewFrom.width) * p
                        height: clipWin.previewFrom.height + (parent.height - clipWin.previewFrom.height) * p
                        radius: Radius.outer(clipWin.s(12))
                        color: clipWin.crust
                        border.width: 1
                        border.color: Qt.rgba(clipWin.mauve.r, clipWin.mauve.g, clipWin.mauve.b, 0.6 * p)
                        clip: true

                        // Swallows clicks meant for the rows underneath.
                        MouseArea { anchors.fill: parent }

                        NumberAnimation {
                            id: previewScrollAnim
                            target: previewScroll
                            property: "contentY"
                            duration: 150
                            easing.type: Easing.OutCubic
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: clipWin.s(12)
                            anchors.bottomMargin: clipWin.s(34)
                            visible: preview.isImage
                            source: preview.isImage && preview.pc.content
                                ? (preview.pc.content.startsWith("file://") ? preview.pc.content : "file://" + preview.pc.content) : ""
                            sourceSize.width: 1600
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; cache: true; smooth: true; mipmap: true
                            opacity: preview.fade
                        }

                        Flickable {
                            id: previewScroll
                            anchors.fill: parent
                            anchors.margins: clipWin.s(14)
                            anchors.rightMargin: clipWin.s(30)
                            anchors.bottomMargin: clipWin.s(34)
                            visible: !preview.isImage
                            opacity: preview.fade
                            contentWidth: width
                            contentHeight: previewEdit.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            onMovementStarted: previewScrollAnim.stop()

                            ScrollBar.vertical: ScrollBar {
                                width: clipWin.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: clipWin.s(4); radius: clipWin.s(2); color: clipWin.surface2 }
                            }

                            TextEdit {
                                id: previewEdit
                                width: previewScroll.width
                                // A huge clip is laid out only once the morph has landed, so it can't stall it.
                                text: preview.p < 0.99 ? preview.fullText.substring(0, 3000) : preview.fullText.substring(0, 200000)
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                font.family: Fonts.ui
                                font.pixelSize: clipWin.s(13)
                                color: clipWin.text
                                selectionColor: clipWin.surface2
                                selectedTextColor: clipWin.mauve
                            }
                        }

                        Text {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: clipWin.s(10)
                            z: 2
                            opacity: preview.fade
                            text: "󰅖"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: clipWin.s(14)
                            color: closePreviewMa.containsMouse ? clipWin.text : clipWin.subtext0
                            MouseArea {
                                id: closePreviewMa
                                anchors.fill: parent
                                anchors.margins: -clipWin.s(6)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clipWin.togglePreview()
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: clipWin.s(14)
                            anchors.rightMargin: clipWin.s(12)
                            anchors.bottomMargin: clipWin.s(8)
                            height: clipWin.s(20)
                            spacing: clipWin.s(10)
                            opacity: preview.fade

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: preview.pc === null ? ""
                                    : preview.isImage ? (preview.pc.meta || "Image")
                                    : preview.fullText.length + " chars · " + preview.fullText.split("\n").length + " lines"
                                font.family: Fonts.ui
                                font.pixelSize: clipWin.s(10)
                                color: clipWin.subtext0
                            }
                            Text {
                                text: "←→ browse   ↵ copy   Tab close"
                                font.family: Fonts.ui
                                font.pixelSize: clipWin.s(10)
                                color: Qt.alpha(clipWin.subtext0, 0.75)
                            }
                        }
                    }
                }
            }
        }
    }
}
