// The Quickshell side of the KWin bridge: runs helpers/wm-bridge.py, reads the live
// window list from its stdout, and fires actions back at it over busctl.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Live window list: [{ id, appId, caption, minimized, active, w, h }, ...] (w/h: client size)
    property var windows: []

    readonly property string activeAppId: {
        for (var i = 0; i < windows.length; i++)
            if (windows[i].active) return (windows[i].appId || "")
        return ""
    }

    // Path to this shell (strip any file:// the API might hand back).
    readonly property string shellPath: ("" + Quickshell.shellDir).replace(/^file:\/\//, "")

    // ── Actions ───────────────────────────────────────────────────────────
    function _call(method, sig, args) {
        var cmd = ["busctl", "--user", "call",
                   "io.quickshell.wm", "/wm", "io.quickshell.wm", method, sig]
        Quickshell.execDetached(cmd.concat(args))
    }
    function activate(id) { if (id) _call("activate", "s", [id]) }
    function closeWindow(id) { if (id) _call("closeWindow", "s", [id]) }
    function minimize(ids, rect) {
        if (!ids || ids.length === 0) return
        _call("minimize", "ss", [JSON.stringify(ids), JSON.stringify(rect)])
    }

    // ── The helper process ────────────────────────────────────────────────
    Process {
        id: bridge
        command: ["python3", "-u", root.shellPath + "/helpers/wm-bridge.py"]
        running: true
        stdout: SplitParser {
            onRead: function (line) {
                var t = (line || "").trim()
                if (t === "") return
                try {
                    var parsed = JSON.parse(t)
                    if (Array.isArray(parsed)) root.windows = parsed
                } catch (e) { /* ignore partial/garbage lines */ }
            }
        }
    }

    Component.onCompleted: if (!bridge.running) bridge.running = true
}
