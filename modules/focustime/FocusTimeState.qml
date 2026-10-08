// FocusTimeState — open/closed state for the FocusTime (screen-time) popup,
// toggled from a TopBar entry (later) or via IPC.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "focustime"
    function toggle() { Popups.toggle("focustime") }
    function show()   { Popups.show("focustime") }
    function hide()   { Popups.hideIf("focustime") }
}
