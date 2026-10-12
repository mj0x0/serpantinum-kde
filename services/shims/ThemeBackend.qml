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
    readonly property color overlay2: c.overlay2
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
    readonly property string iconFont: Fonts.icons

    // The 22 Catppuccin keys upstream's matugen template renders, as hex strings and nothing
    // more: no M3 keys, so the Material faces' resolveColor falls back exactly as upstream.
    readonly property var matugenColors: ({
        base:     String(c.base),
        mantle:   String(c.mantle),
        crust:    String(c.crust),
        text:     String(c.text),
        subtext0: String(c.subtext0),
        subtext1: String(c.subtext1),
        surface0: String(c.surface0),
        surface1: String(c.surface1),
        surface2: String(c.surface2),
        overlay0: String(c.overlay0),
        overlay1: String(c.overlay1),
        overlay2: String(c.overlay2),
        blue:     String(c.blue),
        sapphire: String(c.sapphire),
        peach:    String(c.peach),
        green:    String(c.green),
        red:      String(c.red),
        mauve:    String(c.mauve),
        pink:     String(c.pink),
        yellow:   String(c.yellow),
        maroon:   String(c.maroon),
        teal:     String(c.teal)
    })
}
