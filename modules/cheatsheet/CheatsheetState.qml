// CheatsheetState — open/closed state for the keybind cheat sheet.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "cheatsheet"
    function toggle() { Popups.toggle("cheatsheet") }
    function show()   { Popups.show("cheatsheet") }
    function hide()   { Popups.hideIf("cheatsheet") }
}
