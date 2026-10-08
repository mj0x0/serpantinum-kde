// PowerState — open/closed state for the power panel. Toggled from the TopBar power
// pill (direct call, same instance) or via IPC.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "power"

    // Screen centre of the TopBar power pill, published by TopBar; -1 until reported.
    property real iconCenterX: -1
    property real iconCenterY: -1
    function toggle() { Popups.toggle("power") }
    function show()   { Popups.show("power") }
    function hide()   { Popups.hideIf("power") }
}
