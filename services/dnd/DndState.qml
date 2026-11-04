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

    // Ticks while a timed DND counts down, so any countdown UI stays live.
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
        interval: root.remainingSecs > 120 ? 60000 : 1000; repeat: true
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

    function enableUntil(epochMs) { if (epochMs <= Date.now()) return; now = Date.now(); until = epochMs; enabled = true; _persist(); }

    // Next hour:00 — today if still ahead, otherwise tomorrow.
    function hourDeadline(hour) {
        var d = new Date();
        d.setHours(hour, 0, 0, 0);
        if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1);
        return d.getTime();
    }

    function weekdayDeadline(day, hour) {   // day: 0 = Sunday
        var d = new Date();
        d.setHours(hour, 0, 0, 0);
        d.setDate(d.getDate() + ((day - d.getDay() + 7) % 7));
        if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 7);
        return d.getTime();
    }

    function enableUntilHour(hour)         { enableUntil(hourDeadline(hour)); }
    function enableUntilWeekday(day, hour) { enableUntil(weekdayDeadline(day, hour)); }

    // Called from a binding, so it reads `remainingSecs` to stay live.
    function remainingLabel() {
        var m = Math.ceil(root.remainingSecs / 60);
        if (m < 60) return m + " min";
        var h = Math.floor(m / 60);
        if (h < 24) return (m % 60) ? h + " h " + (m % 60) + " min" : h + " h";
        var d = Math.floor(h / 24);
        return (h % 24) ? d + " d " + (h % 24) + " h" : d + " d";
    }
}
