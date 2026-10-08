// Shim, not a port: providing this name keeps the polkit files BYTE-IDENTICAL and
// the notification/reusable ports near-verbatim. Map a colour a ported file needs;
// never invent one upstream does not expose.
pragma Singleton

import "../layout"
import "../theme"
import QtQuick
import Quickshell

Singleton {
    id: root

    MatugenColors { id: c }

    // Names must match upstream EXACTLY - a missing one is undefined, and an undefined
    // colour renders BLACK. surface0/surface1/subtext0 were shimmed wrong once already.
    readonly property color base:     c.base
    readonly property color mantle:   c.mantle
    readonly property color crust:    c.crust
    readonly property color surface0: c.surface0
    readonly property color surface1: c.surface1
    readonly property color surface2: c.surface2
    readonly property color overlay0: c.overlay0
    readonly property color overlay1: c.overlay1
    readonly property color text:     c.text
    readonly property color subtext0: c.subtext0
    readonly property color subtext1: c.subtext1
    readonly property color blue:     c.blue
    readonly property color sapphire: c.sapphire
    readonly property color green:    c.green
    readonly property color teal:     c.teal
    readonly property color mauve:    c.mauve
    readonly property color pink:     c.pink
    readonly property color peach:    c.peach
    readonly property color yellow:   c.yellow
    readonly property color red:      c.red
    readonly property color maroon:   c.maroon

    // Upstream's corners follow ui.radius (8px unset); this shell's font is JetBrains Mono.
    readonly property int borderRadius: Radius.outer(8)
    readonly property int clampedBorderRadius: Radius.eased(8)
    readonly property string fontFamily: Fonts.ui
}
