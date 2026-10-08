pragma Singleton

import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

// wallhaven.cc search state behind the picker's Wallhaven tab. Lives here rather than in
// the picker so results, filters and paging survive the popup being rebuilt on every open.
Singleton {
    id: root

    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/wallhaven.py"

    readonly property string screenRes: {
        var scr = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        if (!scr) return "";
        var dpr = scr.devicePixelRatio || 1;
        return Math.round(scr.width * dpr) + "x" + Math.round(scr.height * dpr);
    }

    property string query: ""
    property string categories: "111"
    property string purity: "100"
    property string sorting: "date_added"
    property string topRange: "1M"
    property string atleast: root.screenRes

    // Filters and the last query live in the state dir: QtCore Settings ignores categories here.
    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.local/state/quickshell/wallhaven.json"
        blockLoading: true
        atomicWrites: true
        JsonAdapter {
            id: saved
            property string query: ""
            property string categories: "111"
            property string purity: "100"
            property string sorting: "date_added"
            property string topRange: "1M"
            property string atleast: "screen"
        }
    }

    Component.onCompleted: root.restore()

    function restore() {
        root.query = saved.query;
        root.categories = saved.categories || "111";
        root.purity = saved.purity || "100";
        root.sorting = saved.sorting || "date_added";
        root.topRange = saved.topRange || "1M";
        root.atleast = saved.atleast === "screen" ? root.screenRes : saved.atleast;
    }

    function persist() {
        saved.query = root.query;
        saved.categories = root.categories;
        saved.purity = root.purity;
        saved.sorting = root.sorting;
        saved.topRange = root.topRange;
        saved.atleast = root.atleast === root.screenRes ? "screen" : root.atleast;
        store.writeAdapter();
    }

    property int page: 0
    property int lastPage: 1
    property int total: 0
    property string seed: ""
    property int pendingPage: 0
    property bool started: false
    property bool loading: false
    property string error: ""
    property string errorMessage: ""
    property int retryIn: 0
    property bool purityForced: false
    property bool keyUsed: false

    readonly property ListModel model: ListModel { id: results }
    property var indexById: ({})

    readonly property bool canLoadMore: started && !loading && error === "" && page < lastPage
    readonly property bool empty: started && !loading && error === "" && results.count === 0

    function setFilter(name, value) {
        if (root[name] === value) return;
        root[name] = value;
        root.search();
    }

    function toggleBit(name, i) {
        var bits = ("" + root[name]).split("");
        bits[i] = bits[i] === "1" ? "0" : "1";
        var next = bits.join("");
        if (next === "000") return;
        root.setFilter(name, next);
    }

    function typed(text) {
        root.query = text;
        debounce.restart();
    }

    function search() {
        debounce.stop();
        retryTimer.stop();
        root.page = 0;
        root.lastPage = 1;
        root.total = 0;
        root.seed = "";
        root.indexById = ({});
        results.clear();
        root.started = true;
        root.persist();
        root.fetch(1);
    }

    function loadMore() {
        if (root.canLoadMore) root.fetch(root.page + 1);
    }

    function retry() {
        if (results.count === 0) root.search();
        else root.fetch(root.pendingPage > 0 ? root.pendingPage : root.page + 1);
    }

    // One Process per fetch, tagged with a generation: output and the exit of a superseded
    // page are dropped instead of being mistaken for the current one.
    property int gen: 0
    property var active: null

    function fetch(p) {
        if (root.active) {
            var old = root.active;
            root.active = null;
            old.running = false;
        }
        root.gen++;
        root.pendingPage = p;
        root.error = "";
        root.errorMessage = "";
        root.loading = true;
        var args = ["python3", root.helper, "search",
                    "--q", root.query, "--categories", root.categories, "--purity", root.purity,
                    "--sorting", root.sorting, "--page", "" + p];
        if (root.sorting === "toplist") args.push("--top-range", root.topRange);
        if (root.atleast !== "") args.push("--atleast", root.atleast);
        if (root.seed !== "") args.push("--seed", root.seed);
        var proc = fetcher.createObject(root, { gen: root.gen, command: args });
        root.active = proc;
        proc.running = true;
    }

    function handle(line) {
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        switch (o.event) {
        case "meta":
            root.page = o.page || 1;
            root.lastPage = o.last_page || 1;
            root.total = o.total || 0;
            root.seed = o.seed || "";
            root.purityForced = o.purity_forced === true;
            root.keyUsed = o.key === true;
            break;
        case "result":
            if (root.indexById[o.id] !== undefined) break;
            root.indexById[o.id] = results.count;
            results.append({
                wid: "" + o.id, pageUrl: o.url || "", fullUrl: o.path || "",
                thumbUrl: o.thumb_url || "", thumb: o.thumb || "",
                resolution: o.resolution || "", dimX: o.dimension_x || 0, dimY: o.dimension_y || 0,
                fileSize: o.file_size || 0, fileType: o.file_type || "",
                colors: (o.colors || []).join(","), purity: o.purity || "", category: o.category || "",
                local: o.local || "", dlState: o.local ? "saved" : "", dlProgress: 0, dlMessage: "",
                full: o.full || "", pvState: "", pvProgress: 0
            });
            break;
        case "thumb": {
            var i = root.indexById[o.id];
            if (i !== undefined && o.file) results.setProperty(i, "thumb", o.file);
            break;
        }
        case "error":
            root.error = o.kind || "http";
            root.errorMessage = o.message || "";
            root.retryIn = o.retry_after || 0;
            root.loading = false;
            if (root.error === "ratelimit" && root.retryIn > 0) retryTimer.restart();
            break;
        case "end":
            root.loading = false;
            break;
        }
    }

    Component {
        id: fetcher
        Process {
            id: fp
            property int gen: 0
            stdout: SplitParser { onRead: line => { if (fp.gen === root.gen) root.handle(line) } }
            onExited: (code, status) => {
                if (fp.gen === root.gen) {
                    root.active = null;
                    if (root.loading) {
                        root.loading = false;
                        if (root.error === "" && code !== 0) {
                            root.error = "http";
                            root.errorMessage = "The wallhaven helper stopped unexpectedly";
                        }
                    }
                }
                fp.destroy();
            }
        }
    }

    // --- downloads ---------------------------------------------------------------
    property var downloads: ({})
    property string notice: ""
    Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }
    function say(msg) { root.notice = msg; noticeTimer.restart(); }

    function shortPath(f) {
        var home = Quickshell.env("HOME");
        return ("" + f).indexOf(home + "/") === 0 ? "~" + ("" + f).substring(home.length) : "" + f;
    }

    function setRow(wid, props) {
        var i = root.indexById[wid];
        if (i === undefined) return;
        for (var k in props) results.setProperty(i, k, props[k]);
    }

    // A saved tile applies straight away; anything else downloads first.
    function download(wid) {
        var i = root.indexById[wid];
        if (i === undefined || root.downloads[wid]) return;
        var row = results.get(i);
        if (row.local !== "") { root.applyFile(wid, row.local); return; }
        root.setRow(wid, { dlState: "downloading", dlProgress: 0, dlMessage: "" });
        var proc = getter.createObject(root, {
            wid: wid,
            command: ["python3", root.helper, "get", wid, "--dest", ShellSettings.wallhavenDir]
        });
        root.downloads[wid] = proc;
        proc.running = true;
    }

    function applyFile(wid, file) {
        WallpaperService.apply(file);
        root.setRow(wid, { dlState: "applied", local: file });
        root.say("Applied " + root.shortPath(file));
    }

    function handleDownload(wid, line) {
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        switch (o.event) {
        case "progress":
            root.setRow(wid, { dlProgress: o.pct || 0 });
            break;
        case "done":
            root.setRow(wid, { dlState: "saved", dlProgress: 100, local: o.file || "" });
            if (ShellSettings.wallhavenApplyOnDownload) {
                root.applyFile(wid, o.file);
            } else {
                var where = root.shortPath(o.file);
                root.say((o.existed ? "Already saved at " : "Saved to ") + where
                         + (o.dest_fallback ? " (download folder not writable)" : "")
                         + (o.in_picker ? "" : " · outside the Images folder, so not in the local tabs"));
            }
            break;
        case "error":
            root.setRow(wid, { dlState: "error", dlMessage: o.message || "Download failed" });
            root.say(o.message || "Download failed");
            break;
        }
    }

    Component {
        id: getter
        Process {
            id: gp
            property string wid: ""
            stdout: SplitParser { onRead: line => root.handleDownload(gp.wid, line) }
            onExited: (code, status) => {
                delete root.downloads[gp.wid];
                var i = root.indexById[gp.wid];
                if (i !== undefined && results.get(i).dlState === "downloading")
                    root.setRow(gp.wid, { dlState: "error", dlMessage: "The download helper stopped unexpectedly" });
                gp.destroy();
            }
        }
    }

    // --- previews: the full image into the cache, one at a time --------------------------
    property var previewProc: null

    function preview(wid) {
        var i = root.indexById[wid];
        if (i === undefined) return;
        var row = results.get(i);
        if (row.full !== "" || row.local !== "" || row.pvState === "loading") return;
        if (root.previewProc) {
            var old = root.previewProc;
            root.previewProc = null;
            old.running = false;
        }
        root.setRow(wid, { pvState: "loading", pvProgress: 0 });
        var proc = previewer.createObject(root, {
            wid: wid, command: ["python3", root.helper, "preview", wid]
        });
        root.previewProc = proc;
        proc.running = true;
    }

    function handlePreview(wid, line) {
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        if (o.event === "progress") {
            root.setRow(wid, { pvProgress: o.pct || 0 });
        } else if (o.event === "preview") {
            root.setRow(wid, { pvState: "ready", pvProgress: 100, full: o.file || "" });
        } else if (o.event === "error") {
            root.setRow(wid, { pvState: "error" });
            root.say(o.message || "Preview failed");
        }
    }

    Component {
        id: previewer
        Process {
            id: pp
            property string wid: ""
            stdout: SplitParser { onRead: line => root.handlePreview(pp.wid, line) }
            onExited: (code, status) => {
                if (root.previewProc === pp) root.previewProc = null;
                var i = root.indexById[pp.wid];
                if (i !== undefined && results.get(i).pvState === "loading")
                    root.setRow(pp.wid, { pvState: "" });
                pp.destroy();
            }
        }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: root.search()
    }

    // A 429 answer carries how long to wait; count it down and retry once on its own.
    Timer {
        id: retryTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.retryIn = Math.max(0, root.retryIn - 1);
            if (root.retryIn === 0) {
                retryTimer.stop();
                root.retry();
            }
        }
    }
}
