// Live colours (matugen or a static theme) from ~/.local/state/quickshell/generated/colors.json,
// watched so the shell re-themes live. Typed `color`, not `string`, so Qt.rgba() tinting works.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    property alias md3: jsonAdapter.md3
    property alias base16: jsonAdapter.base16
    property alias palette: jsonAdapter.palette
    property alias named: jsonAdapter.named
    property alias theme: jsonAdapter.theme
    // A static theme ships its own 22 roles in `named`; under matugen it is empty.
    readonly property bool isStatic: theme.name !== "matugen"

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: jsonAdapter

            readonly property Md3 md3: Md3 {}
            readonly property Base16 base16: Base16 {}
            readonly property Palette palette: Palette {}
            readonly property Theme theme: Theme {}
            readonly property Named named: Named {}
        }
    }

    component Theme: JsonObject {
        property string name: "matugen"
    }

    component Named: JsonObject {
        property color base: "transparent"
        property color mantle: "transparent"
        property color crust: "transparent"
        property color text: "transparent"
        property color subtext0: "transparent"
        property color subtext1: "transparent"
        property color surface0: "transparent"
        property color surface1: "transparent"
        property color surface2: "transparent"
        property color overlay0: "transparent"
        property color overlay1: "transparent"
        property color overlay2: "transparent"
        property color blue: "transparent"
        property color sapphire: "transparent"
        property color peach: "transparent"
        property color green: "transparent"
        property color red: "transparent"
        property color mauve: "transparent"
        property color pink: "transparent"
        property color yellow: "transparent"
        property color maroon: "transparent"
        property color teal: "transparent"
    }

    component Md3: JsonObject {
        property color background: "transparent"
        property color error: "transparent"
        property color error_container: "transparent"
        property color inverse_on_surface: "transparent"
        property color inverse_primary: "transparent"
        property color inverse_surface: "transparent"
        property color on_background: "transparent"
        property color on_error: "transparent"
        property color on_error_container: "transparent"
        property color on_primary: "transparent"
        property color on_primary_container: "transparent"
        property color on_primary_fixed: "transparent"
        property color on_primary_fixed_variant: "transparent"
        property color on_secondary: "transparent"
        property color on_secondary_container: "transparent"
        property color on_secondary_fixed: "transparent"
        property color on_secondary_fixed_variant: "transparent"
        property color on_surface: "transparent"
        property color on_surface_variant: "transparent"
        property color on_tertiary: "transparent"
        property color on_tertiary_container: "transparent"
        property color on_tertiary_fixed: "transparent"
        property color on_tertiary_fixed_variant: "transparent"
        property color outline: "transparent"
        property color outline_variant: "transparent"
        property color primary: "transparent"
        property color primary_container: "transparent"
        property color primary_fixed: "transparent"
        property color primary_fixed_dim: "transparent"
        property color scrim: "transparent"
        property color secondary: "transparent"
        property color secondary_container: "transparent"
        property color secondary_fixed: "transparent"
        property color secondary_fixed_dim: "transparent"
        property color shadow: "transparent"
        property color surface: "transparent"
        property color surface_bright: "transparent"
        property color surface_container: "transparent"
        property color surface_container_high: "transparent"
        property color surface_container_highest: "transparent"
        property color surface_container_low: "transparent"
        property color surface_container_lowest: "transparent"
        property color surface_dim: "transparent"
        property color surface_tint: "transparent"
        property color surface_variant: "transparent"
        property color tertiary: "transparent"
        property color tertiary_container: "transparent"
        property color tertiary_fixed: "transparent"
        property color tertiary_fixed_dim: "transparent"
    }

    component Palette: JsonObject {
        property color error0: "transparent"
        property color error5: "transparent"
        property color error10: "transparent"
        property color error15: "transparent"
        property color error20: "transparent"
        property color error25: "transparent"
        property color error30: "transparent"
        property color error35: "transparent"
        property color error40: "transparent"
        property color error50: "transparent"
        property color error60: "transparent"
        property color error70: "transparent"
        property color error80: "transparent"
        property color error90: "transparent"
        property color error95: "transparent"
        property color error98: "transparent"
        property color error99: "transparent"
        property color error100: "transparent"

        property color neutral0: "transparent"
        property color neutral5: "transparent"
        property color neutral10: "transparent"
        property color neutral15: "transparent"
        property color neutral20: "transparent"
        property color neutral25: "transparent"
        property color neutral30: "transparent"
        property color neutral35: "transparent"
        property color neutral40: "transparent"
        property color neutral50: "transparent"
        property color neutral60: "transparent"
        property color neutral70: "transparent"
        property color neutral80: "transparent"
        property color neutral90: "transparent"
        property color neutral95: "transparent"
        property color neutral98: "transparent"
        property color neutral99: "transparent"
        property color neutral100: "transparent"

        property color neutral_variant0: "transparent"
        property color neutral_variant5: "transparent"
        property color neutral_variant10: "transparent"
        property color neutral_variant15: "transparent"
        property color neutral_variant20: "transparent"
        property color neutral_variant25: "transparent"
        property color neutral_variant30: "transparent"
        property color neutral_variant35: "transparent"
        property color neutral_variant40: "transparent"
        property color neutral_variant50: "transparent"
        property color neutral_variant60: "transparent"
        property color neutral_variant70: "transparent"
        property color neutral_variant80: "transparent"
        property color neutral_variant90: "transparent"
        property color neutral_variant95: "transparent"
        property color neutral_variant98: "transparent"
        property color neutral_variant99: "transparent"
        property color neutral_variant100: "transparent"

        property color primary0: "transparent"
        property color primary5: "transparent"
        property color primary10: "transparent"
        property color primary15: "transparent"
        property color primary20: "transparent"
        property color primary25: "transparent"
        property color primary30: "transparent"
        property color primary35: "transparent"
        property color primary40: "transparent"
        property color primary50: "transparent"
        property color primary60: "transparent"
        property color primary70: "transparent"
        property color primary80: "transparent"
        property color primary90: "transparent"
        property color primary95: "transparent"
        property color primary98: "transparent"
        property color primary99: "transparent"
        property color primary100: "transparent"

        property color secondary0: "transparent"
        property color secondary5: "transparent"
        property color secondary10: "transparent"
        property color secondary15: "transparent"
        property color secondary20: "transparent"
        property color secondary25: "transparent"
        property color secondary30: "transparent"
        property color secondary35: "transparent"
        property color secondary40: "transparent"
        property color secondary50: "transparent"
        property color secondary60: "transparent"
        property color secondary70: "transparent"
        property color secondary80: "transparent"
        property color secondary90: "transparent"
        property color secondary95: "transparent"
        property color secondary98: "transparent"
        property color secondary99: "transparent"
        property color secondary100: "transparent"

        property color tertiary0: "transparent"
        property color tertiary5: "transparent"
        property color tertiary10: "transparent"
        property color tertiary15: "transparent"
        property color tertiary20: "transparent"
        property color tertiary25: "transparent"
        property color tertiary30: "transparent"
        property color tertiary35: "transparent"
        property color tertiary40: "transparent"
        property color tertiary50: "transparent"
        property color tertiary60: "transparent"
        property color tertiary70: "transparent"
        property color tertiary80: "transparent"
        property color tertiary90: "transparent"
        property color tertiary95: "transparent"
        property color tertiary98: "transparent"
        property color tertiary99: "transparent"
        property color tertiary100: "transparent"
    }

    component Base16: JsonObject {
        property color base00: "transparent"
        property color base01: "transparent"
        property color base02: "transparent"
        property color base03: "transparent"
        property color base04: "transparent"
        property color base05: "transparent"
        property color base06: "transparent"
        property color base07: "transparent"
        property color base08: "transparent"
        property color base09: "transparent"
        property color base0a: "transparent"
        property color base0b: "transparent"
        property color base0c: "transparent"
        property color base0d: "transparent"
        property color base0e: "transparent"
        property color base0f: "transparent"
    }
}
