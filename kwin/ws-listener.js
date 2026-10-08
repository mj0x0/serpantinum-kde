// Persistent KWin listener -> io.quickshell.ws: the workspace array for the TopBar
// pills, and whether the active window is fullscreen. Loaded by helpers/ws-bridge.py.

function emit() {
    var desks = workspace.desktops;
    var curId = workspace.currentDesktop ? workspace.currentDesktop.id : "";

    // Occupancy: which desktops hold at least one real (taskbar) window.
    var occ = {};
    var wins = workspace.windowList ? workspace.windowList() : workspace.stackingOrder;
    for (var w = 0; w < wins.length; w++) {
        var win = wins[w];
        if (!win || win.skipTaskbar || win.specialWindow) continue;
        if (win.onAllDesktops) continue;           // ubiquitous → not a per-desktop marker
        var ds = win.desktops || [];
        for (var d = 0; d < ds.length; d++) occ[ds[d].id] = true;
    }

    var out = [];
    for (var i = 0; i < desks.length; i++) {
        var id = desks[i].id;
        var state = (id === curId) ? "active" : (occ[id] ? "occupied" : "empty");
        out.push({ id: i + 1, state: state });
    }
    callDBus("io.quickshell.ws", "/ws", "io.quickshell.ws", "update", JSON.stringify(out));
}

// Hide-on-fullscreen: report whether the focused window is fullscreen.
function fsEmit() {
    var a = workspace.activeWindow;
    var fs = !!(a && a.fullScreen && !a.minimized);
    callDBus("io.quickshell.ws", "/ws", "io.quickshell.ws", "fullscreen", fs ? "1" : "0");
}

// Re-emit when a window moves between desktops or toggles fullscreen.
var watched = {};
function watch(w) {
    if (!w) return;
    var key = String(w.internalId);
    if (watched[key]) return;
    watched[key] = true;
    if (w.desktopsChanged) w.desktopsChanged.connect(emit);
    if (w.fullScreenChanged) w.fullScreenChanged.connect(fsEmit);
}

if (workspace.currentDesktopChanged) workspace.currentDesktopChanged.connect(function () { emit(); fsEmit(); });
if (workspace.desktopsChanged) workspace.desktopsChanged.connect(emit);
if (workspace.numberDesktopsChanged) workspace.numberDesktopsChanged.connect(emit);
if (workspace.windowActivated) workspace.windowActivated.connect(fsEmit);
workspace.windowAdded.connect(function (w) { watch(w); emit(); fsEmit(); });
workspace.windowRemoved.connect(function (w) { emit(); fsEmit(); });

var initial = workspace.windowList ? workspace.windowList() : workspace.stackingOrder;
for (var i = 0; i < initial.length; i++) watch(initial[i]);
emit();
fsEmit();
