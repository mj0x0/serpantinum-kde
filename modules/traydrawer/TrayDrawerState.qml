pragma Singleton

// The tray drawer: every tray icon in one card, opened from the bar's tray button.
import QtQuick
import Quickshell

Item {
    property bool open: false
    property real anchorX: 0
    property real anchorY: 0
    property var screen: null

    function toggle(x, y, scr) {
        if (open) { hide(); return; }
        anchorX = x;
        anchorY = y;
        screen = scr;
        open = true;
    }
    function hide() { open = false; }

    // Bar tray buttons, so IPC can open the drawer by one without a click position.
    property var buttons: []
    function register(b) { if (buttons.indexOf(b) === -1) buttons = buttons.concat([b]); }
    function unregister(b) { buttons = buttons.filter(x => x !== b); }

    function toggleAny() {
        if (open) { hide(); return; }
        var b = buttons.find(x => x.active && x.visible) || null;
        if (b) {
            var p = b.reportCenter();
            toggle(p.x, p.y, b.barWindow.screen);
        } else {
            var scr = Quickshell.screens.length ? Quickshell.screens[0] : null;
            toggle(scr ? scr.width / 2 : 0, scr ? scr.height / 2 : 0, scr);
        }
    }
}
