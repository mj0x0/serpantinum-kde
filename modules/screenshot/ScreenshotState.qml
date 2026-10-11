// ScreenshotState — open/closed state for the screenshot overlay (ScreenshotOverlay.qml),
// toggled via IPC from a KDE global shortcut (see shell.qml IpcHandler).
pragma Singleton

import QtQuick

Item {
    property bool open: false
    // Hand the region to swappy before saving it, as upstream's --edit does.
    property bool editMode: false

    // Held shortcuts re-fire on some keyboards; a toggle settles briefly, as in ClipboardState.
    property double lastToggle: 0
    readonly property int settleMs: 500

    function toggle(edit) {
        var now = Date.now();
        if (now - lastToggle < settleMs) return;
        lastToggle = now;
        if (open) { open = false; return; }
        editMode = edit === true;
        open = true;
    }
    function toggleEdit() { toggle(true) }
    function show(edit) { lastToggle = Date.now(); editMode = edit === true; open = true }
    function showEdit() { show(true) }
    function hide()     { lastToggle = 0; open = false }
}
