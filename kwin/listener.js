// Persistent KWin listener: KWin is the only thing that can see the window list here,
// so this runs inside it and pushes state out over D-Bus. Loaded by helpers/wm-bridge.py.

function classOf(w) {
    // desktopFileName is the reliable Wayland app id ("org.kde.dolphin"); fall
    // back to X11-ish class/name for apps that don't set it.
    return (w.desktopFileName || w.resourceClass || w.resourceName || "").toString().toLowerCase();
}

function manageable(w) {
    if (!w || !w.normalWindow || w.skipTaskbar) return false;
    var c = classOf(w);
    if (!c) return false;
    if (c === "quickshell" || c === "plasmashell" || c === "krunner") return false;
    return true;
}

function snapshot() {
    var list = workspace.windowList ? workspace.windowList() : workspace.stackingOrder;
    var active = workspace.activeWindow;
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (!manageable(w)) continue;
        var cg = w.clientGeometry;
        out.push({
            id: String(w.internalId),
            appId: classOf(w),
            caption: (w.caption || "").toString(),
            minimized: !!w.minimized,
            active: (w === active),
            w: cg ? cg.width : 0,
            h: cg ? cg.height : 0
        });
    }
    callDBus("io.quickshell.wm", "/wm", "io.quickshell.wm", "update", JSON.stringify(out));
    // The focused window for FocusTime, unfiltered: raw class + caption, as kdotool reported.
    callDBus("io.quickshell.wm", "/wm", "io.quickshell.wm", "active",
             active ? (active.resourceClass || "").toString() : "",
             active ? (active.caption || "").toString() : "");
}

// Watch per-window state changes (minimize/caption) in addition to the global
// add/remove/activate signals, so external minimizes reflect in the dock too.
var watched = {};
function watch(w) {
    if (!w) return;
    var key = String(w.internalId);
    if (watched[key]) return;
    watched[key] = true;
    if (w.minimizedChanged) w.minimizedChanged.connect(snapshot);
    if (w.captionChanged) w.captionChanged.connect(snapshot);
}

workspace.windowAdded.connect(function (w) { watch(w); snapshot(); });
workspace.windowRemoved.connect(function (w) { snapshot(); });
workspace.windowActivated.connect(function (w) { snapshot(); });

var initial = workspace.windowList ? workspace.windowList() : workspace.stackingOrder;
for (var i = 0; i < initial.length; i++) watch(initial[i]);
snapshot();
