// BluetoothState — open/closed state for the Bluetooth panel. Toggled from the
// TopBar status icon (direct call, same instance) or via IPC.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "bluetooth"

    // Screen x of the TopBar bluetooth pill's centre, published by TopBar so the panel
    // opens beneath its icon. -1 until reported, and the panel falls back to right-aligned.
    property real iconCenterX: -1
    property real iconCenterY: -1
    function toggle() { Popups.toggle("bluetooth") }
    function show()   { Popups.show("bluetooth") }
    function hide()   { Popups.hideIf("bluetooth") }
}
