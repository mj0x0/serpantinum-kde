// LauncherState — shared open/closed state for the launcher overlay.
// Flipped by the IPC handler (Meta shortcut) and read by Launcher.qml.

pragma Singleton
import QtQuick

Item {
    property bool open: false

    // Some keyboards re-press a held key every ~0.5s and KDE re-fires the shortcut.
    // A toggle settles for a moment; fires inside that window are the same press.
    // Closing any other way (Esc, click, launch) ends the window at once.
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
