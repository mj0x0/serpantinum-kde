// The Quickshell side of the KWin bridge: the live window list is Bridge.windows
// (helpers/rice-bridge.py's wm module); actions go back to it over busctl.

pragma Singleton
import "../bridge"
import QtQuick
import Quickshell

Item {
    id: root

    // Live window list: [{ id, appId, caption, minimized, active, w, h }, ...] (w/h: client size)
    readonly property var windows: Bridge.windows

    readonly property string activeAppId: {
        for (var i = 0; i < windows.length; i++)
            if (windows[i].active) return (windows[i].appId || "")
        return ""
    }

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
}
