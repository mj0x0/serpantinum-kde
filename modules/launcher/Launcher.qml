// Ported serpantinum appLauncher on our KDE backend: apps and ranking from
// AppSearchService, launch via DesktopEntry.execute(), open/close via LauncherState.
// Chassis is v2's edge-attached design: one animProgress grows the container out of
// the bar (or the screen edge), concave fillets curve the join, and the bar's strip is
// cut out of the input region so it stays clickable while we are open.

import "../../services/audio"
import "../../services/appsearch"
import "../../services/bar"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
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
    id: launcher

    readonly property bool isVisible: LauncherState.open
    // Stays mapped until the close animation has run out.
    visible: isVisible || container.animProgress > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: isVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // The bar's strip is cut out of our input region so it stays clickable; the card
    // itself is put back, since it may overlap a modular bar.
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
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve:    _theme.mauve
    readonly property color blue:     _theme.blue

    // Ambient orbit, same feel as the volume popup. No Behavior on the blob's x/y:
    // chasing a per-frame binding starves the animation and it silently freezes.
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite
        running: launcher.isVisible
    }

    // --- launcher.* settings ------------------------------------------------
    readonly property string positionSetting: "" + ShellSettings.value("launcher.position", "follow")
    readonly property real customWidth: {
        let w = Number(ShellSettings.value("launcher.width", 600));
        return (isNaN(w) || w < 200) ? 600 : w;
    }
    readonly property int itemCount: {
        let n = Number(ShellSettings.value("launcher.itemCount", 6));
        return (isNaN(n) || n < 1) ? 6 : Math.round(n);
    }

    // "follow" tracks the bar so the flush look is the out-of-box behaviour.
    readonly property string attachEdge: {
        let p = positionSetting;
        if (p === "top" || p === "bottom" || p === "left" || p === "right" || p === "center") return p;
        return BarState.position;
    }
    readonly property bool isSideAttached: attachEdge === "left" || attachEdge === "right"
    readonly property bool isCentered: attachEdge === "center"

    // Latched while open: a bar that hides mid-way (fullscreen overlay) must not move the card.
    property bool barHidden: BarState.hidden
    Connections {
        target: BarState
        function onHiddenChanged() { if (!launcher.isVisible) launcher.barHidden = BarState.hidden }
    }

    // v2's rule: flush to the screen edge, or to a solid bar's slab on the same edge.
    // A modular bar is simply overlapped.
    readonly property bool barMatches: !isCentered && BarState.position === attachEdge && !barHidden && BarState.solid
    readonly property real edgeOffset: barMatches ? BarState.slabThickness : 0

    onAttachEdgeChanged: LauncherState.hide()
    onBarMatchesChanged: LauncherState.hide()

    // --- Geometry (v2 metrics) ----------------------------------------------
    readonly property real cornerRadius: Radius.chassis(s(24))
    readonly property real baseWidth: s(customWidth)
    readonly property real collapsedCenterHeight: s(14) * 2 + s(36)
    readonly property real rowHeight: s(44)
    readonly property real rowSpacing: s(4)
    readonly property real targetHeight: {
        let count = Math.min(appModel.count, itemCount);
        if (count <= 0) return collapsedCenterHeight;
        return collapsedCenterHeight + s(10) + count * rowHeight + (count - 1) * rowSpacing;
    }
    property real animatedHeight: targetHeight
    Behavior on animatedHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // id -> DesktopEntry, so a smart-diff row (name/icon/id only) can launch the real entry.
    readonly property var entryById: {
        let m = ({});
        let a = AppSearchService.apps || [];
        for (let i = 0; i < a.length; i++) if (a[i]) m[a[i].id] = a[i];
        return m;
    }

    ListModel { id: appModel }

    // --- Emoji picker (type `emoji <query>`) --- KDE CLDR keywords, lazy-loaded, wl-copy.
    property var emojiData: null
    property bool emojiLoading: false
    readonly property string emojiJsonPath: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/emoji/emoji.json"

    Process {
        id: emojiLoader
        command: ["cat", launcher.emojiJsonPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try { launcher.emojiData = JSON.parse(this.text); }
                catch (e) { launcher.emojiData = []; }
                launcher.emojiLoading = false;
                // If the user is already mid-emoji-query, populate now that data's in.
                var m = searchInput.text.match(/^emoji\s+(.+)$/i);
                if (m) launcher.filterEmoji(m[1].trim());
            }
        }
    }

    property bool isKeyboardNav: false
    Timer { id: keyboardNavTimer; interval: 500; onTriggered: launcher.isKeyboardNav = false }

    // Fuzzy filter (AppSearchService.query — "" returns all, alpha-sorted) with
    // serpantinum's smart diff so rows animate to their new positions.
    function filterApps(query) {
        var cm = query.match(/^>\s*(\S*)\s*(.*)$/);
        if (cm !== null) {
            launcher.filterCommands(cm[1].toLowerCase(), cm[2].trim());
            return;
        }

        // "emoji <query>" → show matching emoji in the SAME list (no mode switch).
        var em = query.match(/^emoji\s+(.*)$/i);
        if (em !== null) {
            launcher.filterEmoji(em[1].trim());
            return;
        }

        launcher.isKeyboardNav = false;
        if (keyboardNavTimer.running) keyboardNavTimer.stop();

        appList.currentIndex = -1;
        appList.positionViewAtBeginning();

        let entries = AppSearchService.query(query);
        let filtered = [];
        for (let i = 0; i < entries.length; i++) {
            let e = entries[i];
            filtered.push({ name: e.name || e.id, desc: e.comment || e.genericName || "",
                            icon: e.icon || "", id: e.id, type: "app", emoji: "" });
        }

        // Drop rows no longer in the result set.
        for (let i = appModel.count - 1; i >= 0; i--) {
            let cur = appModel.get(i);
            let keep = false;
            if (cur.type === "app") for (let j = 0; j < filtered.length; j++) {
                if (filtered[j].name === cur.name) { keep = true; break; }
            }
            if (!keep) appModel.remove(i);
        }

        // Insert/move rows into the new order.
        for (let i = 0; i < filtered.length; i++) {
            let targetApp = filtered[i];
            if (i < appModel.count) {
                if (appModel.get(i).name !== targetApp.name) {
                    let foundIdx = -1;
                    for (let j = i + 1; j < appModel.count; j++) {
                        if (appModel.get(j).name === targetApp.name) { foundIdx = j; break; }
                    }
                    if (foundIdx !== -1) appModel.move(foundIdx, i, 1);
                    else appModel.insert(i, targetApp);
                }
            } else {
                appModel.append(targetApp);
            }
        }

        if (appModel.count > 0) appList.currentIndex = 0;
    }

    function launchApp(id) {
        let e = launcher.entryById[id];
        if (e) e.execute();
        LauncherState.hide();
    }

    // Populate the list with emoji matches (or nothing for a bare "emoji ").
    function filterEmoji(sub) {
        launcher.isKeyboardNav = false;
        if (keyboardNavTimer.running) keyboardNavTimer.stop();
        appList.currentIndex = -1;
        appList.positionViewAtBeginning();

        appModel.clear();
        if (sub.length === 0) return;   // "emoji " alone → empty list, no flood

        var results = launcher.emojiSearch(sub);
        for (var i = 0; i < results.length; i++)
            appModel.append({ name: results[i].n, desc: "", icon: "", id: "", type: "emoji", emoji: results[i].e });
        if (appModel.count > 0) appList.currentIndex = 0;
    }

    // Rank: exact keyword > name-exact > prefix > substring; all tokens required.
    function emojiSearch(query) {
        if (launcher.emojiData === null) {
            if (!launcher.emojiLoading) { launcher.emojiLoading = true; emojiLoader.running = true; }
            return [];
        }
        var toks = query.toLowerCase().split(/\s+/).filter(function (t) { return t.length > 0; });
        if (toks.length === 0) return [];
        var joined = query.toLowerCase().replace(/\s+/g, "");
        var data = launcher.emojiData;
        var scored = [];
        for (var i = 0; i < data.length; i++) {
            var name = data[i].n, kws = data[i].k;
            var score = 0, ok = true;
            for (var ti = 0; ti < toks.length; ti++) {
                var t = toks[ti], b = 0;
                if (name === t) b = 120;                                      // exact name wins outright
                else if (kws.indexOf(t) !== -1) b = 100;
                else {
                    if (name.lastIndexOf(t, 0) === 0) b = 60;                 // name startsWith
                    else { for (var ki = 0; ki < kws.length; ki++) if (kws[ki].lastIndexOf(t, 0) === 0) { b = 60; break; } }
                    if (b === 0) {
                        if (name.indexOf(t) !== -1) b = 30;
                        else { for (var kj = 0; kj < kws.length; kj++) if (kws[kj].indexOf(t) !== -1) { b = 30; break; } }
                    }
                }
                if (b === 0) { ok = false; break; }
                score += b;
            }
            if (!ok) continue;
            if (joined.length > 1 && kws.indexOf(joined) !== -1) score += 80;
            scored.push({ s: score, e: data[i].e, n: name });
        }
        // Score desc, then shorter emoji first (plain 🔥 over ZWJ ❤️‍🔥).
        scored.sort(function (a, b) { return (b.s - a.s) || (a.e.length - b.e.length); });
        return scored.slice(0, 50);
    }

    function copyEmoji(ch) {
        if (ch && ch.length > 0) Quickshell.execDetached(["wl-copy", ch]);
        LauncherState.hide();
    }

    // --- Commands (type `>`) -------------------------------------------------
    readonly property var commands: [
        { name: ">calc",    desc: "Calculator, e.g. >calc 2^10 or >calc 5 usd to eur", glyph: "\u{f00ec}" },   // md-calculator
        { name: ">songrec", desc: "Recognize the song that's playing",                 glyph: "\u{f147d}" },   // md-waveform
        { name: ">find",    desc: "Files and folders by name; Shift+Enter opens the folder", glyph: "\u{f0968}" }    // md-folder_search
    ]
    readonly property string songrecScript: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/songrec.sh"
    property string calcResult: ""

    readonly property string findScript: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/file-search.py"
    readonly property int folderModifier: Qt.ShiftModifier
    property var findResults: []
    property string findResultsFor: ""

    Timer {
        id: findTimer
        property string pending: ""
        interval: 150
        onTriggered: {
            if (findProc.running && findProc.query === pending) return;
            findProc.running = false;
            findProc.query = pending;
            findProc.command = [launcher.findScript, pending, "30"];
            findProc.running = true;
        }
    }

    Process {
        id: findProc
        property string query: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var data = null;
                try { data = JSON.parse(this.text); } catch (e) { return; }
                // The helper echoes its query, so a killed or late run can never label the wrong results.
                if (!data || data.query !== findProc.query) return;
                launcher.findResults = data.results || [];
                launcher.findResultsFor = data.query;
                if (/^>\s*find\s/.test(searchInput.text)) launcher.filterApps(searchInput.text);
            }
        }
    }

    Process {
        id: calcProc
        property string expr: ""
        stdout: StdioCollector {
            onStreamFinished: {
                launcher.calcResult = this.text.trim();
                if (/^>\s*calc\s/.test(searchInput.text)) launcher.filterApps(searchInput.text);
            }
        }
    }

    function filterCommands(cmd, arg) {
        launcher.isKeyboardNav = false;
        if (keyboardNavTimer.running) keyboardNavTimer.stop();

        if (cmd === "find" && arg !== "") { launcher.filterFind(arg); return; }
        appList.currentIndex = -1;
        appModel.clear();

        if (cmd === "calc" && arg !== "") {
            if (arg !== calcProc.expr) {
                calcProc.expr = arg;
                calcProc.running = false;
                calcProc.command = ["qalc", "-t", "-set", "max decimals 2", arg];
                calcProc.running = true;
            }
            if (launcher.calcResult !== "")
                appModel.append({ name: launcher.calcResult, desc: "Enter to copy", icon: "", id: "", type: "calc", emoji: "\u{f00ec}" });
        } else {
            for (let i = 0; i < commands.length; i++)
                if (commands[i].name.indexOf(">" + cmd) === 0)
                    appModel.append({ name: commands[i].name, desc: commands[i].desc, icon: "", id: commands[i].name, type: "command", emoji: commands[i].glyph });
        }
        if (appModel.count > 0) appList.currentIndex = 0;
    }

    // Rows are rebuilt only when the result set changes, so keystrokes don't flicker the list.
    function filterFind(arg) {
        if (arg.length < 2) {
            launcher.findResults = [];
            launcher.findResultsFor = "";
        } else if (arg !== launcher.findResultsFor && arg !== findTimer.pending) {
            findTimer.pending = arg;
            findTimer.restart();
        }
        var rows = launcher.findResults;
        var same = appModel.count === rows.length;
        for (var i = 0; same && i < rows.length; i++)
            same = appModel.get(i).id === rows[i].path && appModel.get(i).type === rows[i].type;
        if (same) return;
        appList.currentIndex = -1;
        appModel.clear();
        for (var j = 0; j < rows.length; j++)
            appModel.append({ name: "" + rows[j].name, desc: "" + rows[j].desc, icon: "" + rows[j].icon,
                              id: "" + rows[j].path, type: "" + rows[j].type, emoji: "" });
        if (appModel.count > 0) appList.currentIndex = 0;
    }

    function openPath(path, inFolder) {
        if (path) Quickshell.execDetached(inFolder ? ["dolphin", "--select", path] : ["xdg-open", path]);
        LauncherState.hide();
    }

    function runCommand(name) {
        if (name === ">calc") { searchInput.text = ">calc "; return; }
        if (name === ">find") { searchInput.text = ">find "; return; }
        if (name === ">songrec") Quickshell.execDetached([launcher.songrecScript]);
        LauncherState.hide();
    }

    // Enter/click on a row: copy an emoji or result, run a command, open a path, or launch the app.
    function activateIndex(idx, inFolder) {
        if (idx < 0 || idx >= appModel.count) return;
        var row = appModel.get(idx);
        if (row.type === "emoji" || row.type === "calc") launcher.copyEmoji(row.type === "calc" ? row.name : row.emoji);
        else if (row.type === "command") launcher.runCommand(row.id);
        else if (row.type === "file" || row.type === "dir") launcher.openPath(row.id, !!inFolder);
        else launcher.launchApp(row.id);
    }

    // --- Open / close -------------------------------------------------------
    Timer { id: focusTimer; interval: 50; onTriggered: searchInput.forceInputFocus() }
    Timer { id: focusRetryTimer; interval: 200; onTriggered: searchInput.forceInputFocus() }

    onIsVisibleChanged: {
        if (isVisible) {
            barHidden = BarState.hidden;
            searchInput.text = "";
            filterApps("");
            searchInput.forceInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
        } else {
            focusTimer.stop();
            focusRetryTimer.stop();
            keyboardNavTimer.stop();
        }
    }
    Component.onCompleted: filterApps("")

    // Click outside the card closes it.
    MouseArea { anchors.fill: parent; enabled: launcher.isVisible; onClicked: LauncherState.hide() }

    // The bar's strip along its edge, punched out of our input region.
    Item {
        id: barHole
        readonly property bool active: launcher.isVisible && !launcher.barHidden
        readonly property real t: BarState.bandThickness
        x: (active && BarState.position === "right") ? launcher.width - t : 0
        y: (active && BarState.position === "bottom") ? launcher.height - t : 0
        width: !active ? 0 : (BarState.isVertical ? t : launcher.width)
        height: !active ? 0 : (BarState.isVertical ? launcher.height : t)
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
            fillColor: launcher.base
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

        property real animProgress: launcher.isVisible ? 1.0 : 0.0
        // Keyed on the Behavior's own target: an isVisible binding here evaluates
        // AFTER the animation has already started, so open/close would swap easings.
        Behavior on animProgress {
            id: progBehavior
            NumberAnimation {
                readonly property bool opening: progBehavior.targetValue > 0.5
                duration: opening ? (launcher.isCentered ? 320 : 220) : (launcher.isCentered ? 200 : 150)
                easing.type: opening ? Easing.OutBack : Easing.InQuad
                easing.overshoot: 1.15
            }
        }
        // List transitions only once the open animation has landed, or they fight it.
        readonly property bool settled: launcher.isVisible && animProgress > 0.98

        // Fillet radius follows the growing side so the join never inverts mid-animation.
        readonly property real r: Math.max(0, Math.min(launcher.cornerRadius, (launcher.isSideAttached ? width : height) * 0.5))
        // Square corners + fillets on the attached side; centred stays a rounded card.
        readonly property bool flush: !launcher.isCentered
        readonly property bool showFillets: flush && r > 0.5

        x: launcher.attachEdge === "left" ? launcher.edgeOffset
         : launcher.attachEdge === "right" ? launcher.width - launcher.edgeOffset - width
         : Math.floor((launcher.width - width) / 2)
        y: launcher.attachEdge === "top" ? launcher.edgeOffset
         : launcher.attachEdge === "bottom" ? launcher.height - launcher.edgeOffset - height
         : Math.floor((launcher.height - height) / 2)

        // Side-attached grows in width, top/bottom in height, centred out of the search field.
        width: launcher.isSideAttached ? launcher.baseWidth * animProgress : launcher.baseWidth
        height: {
            if (launcher.isCentered) {
                let baseH = launcher.collapsedCenterHeight;
                let targetH = Math.max(baseH, launcher.animatedHeight);
                return baseH + (targetH - baseH) * animProgress;
            }
            if (!launcher.isSideAttached) return launcher.animatedHeight * animProgress;
            return launcher.animatedHeight;
        }
        opacity: launcher.isCentered ? Math.max(0, Math.min(1, animProgress * 1.5)) : 1

        // Swallow clicks on the card so they never reach the catcher above.
        MouseArea { anchors.fill: parent }

        Fillet { visible: container.showFillets && launcher.attachEdge === "top";    x: -container.r;                       y: 0;                                  vertexX: "right"; vertexY: "top" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "top";    x: container.width;                    y: 0;                                  vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "bottom"; x: -container.r;                       y: container.height - container.r;     vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "bottom"; x: container.width;                    y: container.height - container.r;     vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "left";   x: 0;                                  y: -container.r;                       vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "left";   x: 0;                                  y: container.height;                   vertexX: "left";  vertexY: "top" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "right";  x: container.width - container.r;      y: -container.r;                       vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: container.showFillets && launcher.attachEdge === "right";  x: container.width - container.r;      y: container.height;                   vertexX: "right"; vertexY: "top" }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            color: launcher.base
            radius: container.r
            // The attached side goes square so the fillets read as one surface with the bar.
            topLeftRadius:     (container.flush && (launcher.attachEdge === "top"    || launcher.attachEdge === "left"))  ? 0 : container.r
            topRightRadius:    (container.flush && (launcher.attachEdge === "top"    || launcher.attachEdge === "right")) ? 0 : container.r
            bottomLeftRadius:  (container.flush && (launcher.attachEdge === "bottom" || launcher.attachEdge === "left"))  ? 0 : container.r
            bottomRightRadius: (container.flush && (launcher.attachEdge === "bottom" || launcher.attachEdge === "right")) ? 0 : container.r
            border.width: container.flush ? 0 : 1
            border.color: container.flush ? "transparent" : Qt.rgba(launcher.surface2.r, launcher.surface2.g, launcher.surface2.b, 0.6)
            clip: true

            // clip is rectangular, so the blob is masked to the card's real corners.
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
                    x: (parent.width * 0.5 - width / 2) + Math.cos(launcher.globalOrbitAngle) * launcher.s(120)
                    y: (parent.height * 0.4 - height / 2) + Math.sin(launcher.globalOrbitAngle) * launcher.s(90)
                    color: launcher.mauve
                    opacity: 0.05
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: launcher.s(14)
                visible: width > 0 && height > 0
                clip: true

                readonly property bool searchAtBottom: launcher.attachEdge === "bottom"
                readonly property real inputH: launcher.s(36)
                readonly property real gap: launcher.s(10)

                // Search field.
                V2.Input {
                    id: searchInput
                    z: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: content.searchAtBottom ? Math.max(0, parent.height - height) : 0
                    height: content.inputH
                    baseColor: launcher.surface0
                    accentColor: launcher.mauve
                    textColor: launcher.text
                    subTextColor: launcher.subtext0
                    borderColor: Qt.rgba(launcher.surface2.r, launcher.surface2.g, launcher.surface2.b, 0.6)
                    cornerRadius: Radius.outer(launcher.s(12))
                    fontPixelSize: launcher.s(12)
                    leadingIcon: "󰍉"
                    showClearButton: true
                    placeholderText: "Search apps, emoji <name>, or > for commands"
                    onTextChanged: launcher.filterApps(text)

                    Keys.onDownPressed: (event) => {
                        launcher.isKeyboardNav = true; keyboardNavTimer.restart();
                        if (appList.currentIndex < appModel.count - 1) appList.currentIndex++;
                        event.accepted = true;
                    }
                    Keys.onUpPressed: (event) => {
                        launcher.isKeyboardNav = true; keyboardNavTimer.restart();
                        if (appList.currentIndex > 0) appList.currentIndex--;
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: (event) => {
                        launcher.activateIndex(appList.currentIndex, (event.modifiers & launcher.folderModifier) !== 0);
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: (event) => {
                        launcher.activateIndex(appList.currentIndex, (event.modifiers & launcher.folderModifier) !== 0);
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: (event) => { LauncherState.hide(); event.accepted = true; }
                }

                // App list.
                Item {
                    id: listContainer
                    z: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: content.searchAtBottom ? 0 : content.inputH + content.gap
                    height: Math.max(0, parent.height - content.inputH - content.gap)
                    clip: true
                    opacity: launcher.isCentered
                             ? Math.max(0, Math.min(1, (container.animProgress - 0.2) / 0.8))
                             : 1

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
                    Transition {
                        id: listMoveTrans
                        NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutCubic }
                    }

                    ListView {
                        id: appList
                        anchors.fill: parent
                        clip: true
                        model: appModel
                        spacing: launcher.rowSpacing
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false

                        add: container.settled ? listAddTrans : null
                        remove: container.settled ? listRemoveTrans : null
                        displaced: container.settled ? listMoveTrans : null
                        move: container.settled ? listMoveTrans : null
                        moveDisplaced: container.settled ? listMoveTrans : null

                        onCurrentIndexChanged: { if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain); }

                        // Lagging morphing highlight.
                        highlight: Item {
                            z: 0
                            Rectangle {
                                id: activeHighlight
                                x: 0
                                width: appList.width
                                radius: Radius.outer(launcher.s(12))
                                color: launcher.mauve

                                property int prevIdx: 0
                                property int curIdx: appList.currentIndex
                                onCurIdxChanged: {
                                    if (curIdx === -1) return;
                                    if (curIdx > prevIdx) { bottomAnim.duration = 250; topAnim.duration = 450; }
                                    else if (curIdx < prevIdx) { topAnim.duration = 250; bottomAnim.duration = 450; }
                                    prevIdx = curIdx;
                                }

                                property real targetTop: appList.currentItem ? appList.currentItem.y : 0
                                property real targetBottom: appList.currentItem ? (appList.currentItem.y + appList.currentItem.height) : 0
                                property real actualTop: targetTop
                                property real actualBottom: targetBottom
                                Behavior on actualTop { enabled: launcher.isKeyboardNav && container.settled; NumberAnimation { id: topAnim; easing.type: Easing.OutExpo } }
                                Behavior on actualBottom { enabled: launcher.isKeyboardNav && container.settled; NumberAnimation { id: bottomAnim; easing.type: Easing.OutExpo } }

                                y: actualTop
                                height: actualBottom - actualTop
                                scale: appList.currentItem ? appList.currentItem.scale : 1
                                opacity: appList.count > 0 && appList.currentIndex >= 0 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 170 } }
                            }
                        }

                        delegate: Item {
                            id: row
                            width: ListView.view.width
                            height: launcher.rowHeight
                            z: 1
                            readonly property bool selected: index === appList.currentIndex

                            Item {
                                anchors.fill: parent
                                scale: ma.pressed ? 0.98 : 1
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Radius.outer(launcher.s(12))
                                    color: launcher.surface0
                                    opacity: ma.containsMouse && !row.selected ? 0.45 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutSine } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: launcher.s(6)
                                    anchors.leftMargin: launcher.s(10) + (row.selected ? launcher.s(2) : 0)
                                    anchors.rightMargin: launcher.s(10)
                                    spacing: launcher.s(10)
                                    Behavior on anchors.leftMargin { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

                                    // Icon box.
                                    Item {
                                        Layout.preferredWidth: launcher.s(32)
                                        Layout.preferredHeight: launcher.s(32)
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: launcher.s(1.5)
                                            anchors.bottomMargin: -launcher.s(1.5)
                                            radius: Radius.inset(launcher.s(8), launcher.s(4))
                                            color: Qt.rgba(0, 0, 0, 0.12)
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Radius.inset(launcher.s(8), launcher.s(4))
                                            color: row.selected
                                                   ? Qt.tint(launcher.surface2, Qt.rgba(launcher.mauve.r, launcher.mauve.g, launcher.mauve.b, 0.2))
                                                   : launcher.surface2
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: launcher.s(4)
                                            readonly property bool themed: model.type === "app" || model.type === "file" || model.type === "dir"
                                            visible: themed
                                            source: !themed ? "" : Quickshell.iconPath(model.icon,
                                                model.type === "dir" ? "folder" : model.type === "file" ? "text-x-generic" : "application-x-executable")
                                            sourceSize: Qt.size(64, 64)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; smooth: true; mipmap: true
                                        }
                                        // No explicit font family, so fontconfig falls back to the colour emoji font.
                                        Text {
                                            anchors.centerIn: parent
                                            visible: model.type === "emoji"
                                            text: model.type === "emoji" ? (model.emoji || "") : ""
                                            font.pixelSize: launcher.s(18)
                                        }
                                        // Command and result rows carry a Nerd Font glyph in the emoji role.
                                        Text {
                                            anchors.centerIn: parent
                                            visible: model.type === "command" || model.type === "calc"
                                            text: visible ? (model.emoji || "") : ""
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: launcher.s(20)
                                            color: launcher.mauve
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: launcher.s(1)

                                        Text {
                                            Layout.fillWidth: true
                                            text: model.name
                                            font.family: Fonts.ui
                                            font.pixelSize: launcher.s(12)
                                            font.weight: row.selected ? Font.Bold : Font.Medium
                                            color: row.selected ? launcher.crust : launcher.text
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: model.desc !== ""
                                            text: model.desc
                                            font.family: Fonts.ui
                                            font.pixelSize: launcher.s(10)
                                            color: row.selected ? launcher.crust : launcher.subtext0
                                            opacity: row.selected ? 0.9 : 0.85
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { Sounds.playSfx("system/quick_click.wav"); appList.currentIndex = index; launcher.activateIndex(index, (mouse.modifiers & launcher.folderModifier) !== 0); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
