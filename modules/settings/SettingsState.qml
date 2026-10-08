pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "settings"
    property string section: ""      // reserved: deep-link to a section later

    function toggle() { Popups.toggle("settings") }
    function hide()   { Popups.hideIf("settings") }

    // show() or show("bar") - the popup maps the name onto its tab index.
    function show(name) {
        if (name !== undefined && name !== null && name !== "") section = "" + name;
        Popups.show("settings");
    }
}
