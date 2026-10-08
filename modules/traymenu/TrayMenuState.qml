pragma Singleton

// Which tray item's menu is open, and where its icon sits (bar-window coordinates).
import QtQuick

Item {
    property bool open: false
    property var item: null
    property real anchorX: 0
    property real anchorY: 0
    property var screen: null
    // Opened from the tray drawer: sits beside this card (screen coordinates) instead of by a bar icon.
    property bool beside: false
    property rect besideRect: Qt.rect(0, 0, 0, 0)
    signal triggered()

    function toggle(trayItem, x, y, scr) {
        if (open && item === trayItem) { hide(); return; }
        item = trayItem;
        anchorX = x;
        anchorY = y;
        screen = scr;
        beside = false;
        open = true;
    }
    function toggleBeside(trayItem, r, scr) {
        if (open && item === trayItem) { hide(); return; }
        item = trayItem;
        besideRect = r;
        screen = scr;
        beside = true;
        open = true;
    }
    function hide() { open = false; }
}
