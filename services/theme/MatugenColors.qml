// Compatibility shim: serpantinum's Catppuccin role names bound to our live Colors,
// so the ported bar re-themes with the wallpaper with no edits inside TopBar.qml.

import QtQuick

Item {
    id: root

    // A static theme carries its own 22 roles; matugen output is mapped onto them below.
    readonly property bool isStatic: Colors.isStatic

    // ── Neutrals / surfaces → md3 ─────────────────────────────────────────
    readonly property color base:     isStatic ? Colors.named.base     : Colors.md3.surface
    readonly property color mantle:   isStatic ? Colors.named.mantle   : Colors.md3.surface_container_lowest
    readonly property color crust:    isStatic ? Colors.named.crust    : Colors.md3.surface_dim
    readonly property color text:     isStatic ? Colors.named.text     : Colors.md3.on_surface
    readonly property color subtext0: isStatic ? Colors.named.subtext0 : Colors.md3.on_surface_variant
    readonly property color subtext1: isStatic ? Colors.named.subtext1 : Colors.md3.on_surface_variant
    readonly property color surface0: isStatic ? Colors.named.surface0 : Colors.md3.surface_container
    readonly property color surface1: isStatic ? Colors.named.surface1 : Colors.md3.surface_container_high
    readonly property color surface2: isStatic ? Colors.named.surface2 : Colors.md3.surface_container_highest
    readonly property color overlay0: isStatic ? Colors.named.overlay0 : Colors.md3.outline_variant
    readonly property color overlay1: isStatic ? Colors.named.overlay1 : Colors.md3.outline
    readonly property color overlay2: isStatic ? Colors.named.overlay2 : Colors.md3.outline

    // Catppuccin names from serpantinum; qs_colors.json.template is the source of truth.
    // Only red/maroon are error-derived - matugen's error palette is an M3 constant.
    readonly property color blue:     isStatic ? Colors.named.blue     : Colors.md3.primary
    readonly property color mauve:    isStatic ? Colors.named.mauve    : Colors.md3.primary
    readonly property color sapphire: isStatic ? Colors.named.sapphire : Colors.palette.primary70      // primary_container
    readonly property color peach:    isStatic ? Colors.named.peach    : Colors.md3.tertiary
    readonly property color green:    isStatic ? Colors.named.green    : Colors.md3.secondary
    readonly property color teal:     isStatic ? Colors.named.teal     : Colors.md3.secondary
    readonly property color yellow:   isStatic ? Colors.named.yellow   : Colors.palette.secondary70    // secondary_container
    readonly property color pink:     isStatic ? Colors.named.pink     : Colors.palette.tertiary70     // tertiary_container
    readonly property color red:      isStatic ? Colors.named.red      : Colors.md3.error
    readonly property color maroon:   isStatic ? Colors.named.maroon   : Colors.palette.error70        // error_container

    // Distinct md3 secondary (used by the calendar's big temperature readout).
    readonly property color secondary: Colors.md3.secondary
}
