// Where the bar sits, for everyone who is not the bar. Popup hosts anchor
// their cards against this instead of hardcoding "below the top bar".
pragma Singleton

import "../settings"
import QtQuick
import Quickshell

Singleton {
    readonly property string position: "" + ShellSettings.value("bar.position", "top")
    readonly property bool isVertical: position === "left" || position === "right"

    // Space a popup must leave to clear the bar: thickness + margin + gap.
    // Published scaled by the bar window; 68 matches the old hardcoded offsets.
    property real edgeGap: 68

    // Also published by the bar window. hidden = autohide or fullscreen: nothing on the edge.
    property bool solid: false
    property bool hidden: false
    // Screen edge -> the slab's inner edge (what a flush launcher butts against).
    property real slabThickness: 56
    // Screen edge -> the bar window's far edge: its whole input strip.
    property real bandThickness: 56

    // Per-edge clearance: the bar's edge needs edgeGap, the others a sliver.
    readonly property real topGap: position === "top" ? edgeGap : 12
    readonly property real bottomGap: position === "bottom" ? edgeGap : 12
    readonly property real leftGap: position === "left" ? edgeGap : 12
    readonly property real rightGap: position === "right" ? edgeGap : 12
}
