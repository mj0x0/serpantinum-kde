// MusicState — open/closed state for the music/EQ popup, toggled by clicking
// the TopBar media pill (direct call, same instance) or via IPC.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "music"
    // Bar pill centre, reported by MediaPill; the popup opens near it.
    property real iconCenterX: -1
    property real iconCenterY: -1
    function toggle() { Popups.toggle("music") }
    function show()   { Popups.show("music") }
    function hide()   { Popups.hideIf("music") }
}
