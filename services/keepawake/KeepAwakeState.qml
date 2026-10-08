// Holds inhibitions on both layers (systemd-inhibit idle:sleep + helpers/keep-awake.py);
// the state IS the process, because KDE's PolicyAgent never reports external ones.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    readonly property bool active: holder.running
    property string lastError: ""

    function enable()  { if (!holder.running) { lastError = ""; holder.running = true; } }
    function disable() { holder.running = false; }
    function toggle()  { if (holder.running) disable(); else enable(); }

    // shellDir is a file:// URL; a command needs a plain path.
    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/keep-awake.py"

    Process {
        id: holder
        running: false
        command: [
            // idle:sleep, not idle alone: a keep-awake that lets the lid suspend keeps nothing awake.
            "systemd-inhibit", "--what=idle:sleep", "--who=quickshell-rice",
            "--why=Keep awake",
            // -W ignore: GLib.unix_signal_add is deprecated and its warning would
            // otherwise land in stderr and read as a failure.
            "python3", "-W", "ignore", helper
        ]
        stderr: StdioCollector {
            onStreamFinished: {
                var t = ("" + this.text).trim();
                if (t !== "") lastError = t;
            }
        }
    }
}
