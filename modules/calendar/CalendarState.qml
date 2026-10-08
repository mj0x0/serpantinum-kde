// CalendarState — open/closed state for the calendar/weather control-center,
// toggled from the TopBar clock (direct call, same instance) or via IPC.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "calendar"
    function toggle() { Popups.toggle("calendar") }
    function show()   { Popups.show("calendar") }
    function hide()   { Popups.hideIf("calendar") }
}
