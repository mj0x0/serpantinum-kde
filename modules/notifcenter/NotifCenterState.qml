// NotifCenterState — open/closed state for the notification center, toggled via
// IPC from a KDE global shortcut (see shell.qml IpcHandler).
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "notifcenter"

    // Screen centre of the TopBar bell, published by the bar. -1 until reported.
    property real iconCenterX: -1
    property real iconCenterY: -1
    function toggle() { Popups.toggle("notifcenter") }
    function show()   { Popups.show("notifcenter") }
    function hide()   { Popups.hideIf("notifcenter") }
}
