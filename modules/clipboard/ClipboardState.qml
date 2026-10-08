// ClipboardState — open/closed state for the edge-attached clipboard (Clipboard.qml),
// toggled via IPC from a KDE global shortcut (see shell.qml IpcHandler).
pragma Singleton

import QtQuick

Item {
    property bool open: false

    // Held shortcuts re-fire on some keyboards; a toggle settles briefly, as in LauncherState.
    property double lastToggle: 0
    readonly property int settleMs: 500

    function toggle() {
        var now = Date.now();
        if (now - lastToggle < settleMs) return;
        lastToggle = now;
        open = !open
    }
    function show()   { lastToggle = Date.now(); open = true }
    function hide()   { lastToggle = 0; open = false }
}
