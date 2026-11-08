pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool open: false
    property string section: ""      // deep link: a tab or subtab name, read by the popup

    // Held shortcuts re-fire on some keyboards; a toggle settles briefly, as in LauncherState.
    property double lastToggle: 0
    readonly property int settleMs: 500

    function toggle() {
        var now = Date.now();
        if (now - lastToggle < settleMs) return;
        lastToggle = now;
        open = !open
    }

    // show() or show("bar") - the popup maps the name onto its tab.
    function show(name) {
        if (name !== undefined && name !== null && name !== "") section = "" + name;
        lastToggle = Date.now();
        open = true
    }
    function hide() { lastToggle = 0; open = false }
}
