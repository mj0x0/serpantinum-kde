// One Python daemon (helpers/rice-bridge.py) in place of wm-bridge, ws-bridge, power-watch
// and the kb scripts. Each stdout line is "<tag>\t<payload>"; the slices land here and
// WindowService / PowerInfo / TopBar bind to them.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ id, appId, caption, minimized, active, w, h }, ...] from the wm module
    property var windows: []
    // power-watch's snapshot object, verbatim
    property var power: ({})
    // KDE keyboard layout short code (us / il / ...); "" until the daemon reports
    property string kbLayout: ""
    // one per org.kde.osdService method call Plasma would have drawn
    signal osdCall(string member, var args)
    property var brightness: ({})

    readonly property string shellPath: ("" + Quickshell.shellDir).replace(/^file:\/\//, "")

    // Restart stamps from the last minute; past 5 the next retry waits a full minute.
    property var _starts: []
    readonly property int maxRestartsPerMinute: 5

    Process {
        id: daemon
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "python3", "-u", root.shellPath + "/helpers/rice-bridge.py"]
        stdout: SplitParser {
            onRead: function (line) {
                var cut = line.indexOf("\t");
                if (cut < 0) return;
                var tag = line.substring(0, cut);
                var text = line.substring(cut + 1).trim();
                if (tag === "kb") {
                    if (text !== "") root.kbLayout = text;
                    return;
                }
                var parsed;
                try { parsed = JSON.parse(text); } catch (e) { return; }
                if (tag === "wm") {
                    if (Array.isArray(parsed)) root.windows = parsed;
                } else if (tag === "power") {
                    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) root.power = parsed;
                } else if (tag === "osd") {
                    if (parsed && typeof parsed.m === "string" && Array.isArray(parsed.a)) root.osdCall(parsed.m, parsed.a);
                } else if (tag === "bri") {
                    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) root.brightness = parsed;
                }
            }
        }
        onExited: root._scheduleRestart()
    }

    function _scheduleRestart() {
        var now = Date.now();
        _starts = _starts.filter(t => now - t < 60000);
        restart.interval = _starts.length >= maxRestartsPerMinute ? 60000 : 1000;
        restart.restart();
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: {
            root._starts = root._starts.concat([Date.now()]);
            daemon.running = true;
        }
    }
}
