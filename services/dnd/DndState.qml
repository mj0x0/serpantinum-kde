// Single source of truth for Do Not Disturb: the daemon, the toasts, the centre
// toggle and the TopBar bell all read this. Persisted to ~/.cache/quickshell/dnd/state
// as "<0|1> <until-epoch-ms>", so a timed DND survives a restart with its deadline.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: false
    property double until: 0            // epoch ms; 0 = indefinite

    // Ticks once a second only while a timed DND counts down, so any countdown UI
    // stays live.
    property double now: Date.now()
    readonly property int remainingSecs: (enabled && until > 0)
        ? Math.max(0, Math.round((until - now) / 1000)) : 0

    // Load persisted state on startup (direct assignment — not a mutator — so it
    // doesn't write straight back).
    Process {
        running: true
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/dnd/state\" 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(/\s+/);
                var on = parts[0] === "1";
                var deadline = Number(parts[1]) || 0;
                if (on && deadline > 0 && Date.now() >= deadline) on = false;
                root.until = on ? deadline : 0;
                root.enabled = on;
            }
        }
    }

    function _persist() {
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell/dnd\" && echo '"
            + (root.enabled ? "1" : "0") + " " + Math.round(root.until)
            + "' > \"$HOME/.cache/quickshell/dnd/state\""]);
    }

    Timer {
        interval: 1000; repeat: true
        running: root.enabled && root.until > 0
        onTriggered: {
            root.now = Date.now();
            if (Date.now() >= root.until)
                root.disable();
        }
    }

    function toggle()        { if (enabled) disable(); else enable(); }
    function enable()        { until = 0; enabled = true; _persist(); }            // indefinite
    function enableFor(mins) { now = Date.now(); until = now + mins * 60000; enabled = true; _persist(); }
    function disable()       { enabled = false; until = 0; _persist(); }
}
