import QtQuick
import org.kde.kirigami as Kirigami

// ThemeBackend's names, each read from the Kirigami role matugen fills with that Material colour.
// Must stay a visible child of the applet: Plasma's Kirigami style leaves invisible items black.
Item {
    id: theme

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string iconFont: "Iosevka Nerd Font"
    readonly property int borderRadius: 8
    readonly property int clampedBorderRadius: borderRadius <= 24 ? borderRadius : Math.floor(24 + Math.pow(borderRadius - 24, 0.55))

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    Item { id: view; Kirigami.Theme.colorSet: Kirigami.Theme.View; Kirigami.Theme.inherit: false }
    Item { id: button; Kirigami.Theme.colorSet: Kirigami.Theme.Button; Kirigami.Theme.inherit: false }
    Item { id: complementary; Kirigami.Theme.colorSet: Kirigami.Theme.Complementary; Kirigami.Theme.inherit: false }

    // Material container tone of an accent: same hue, more saturated, half as bright (calibrated on matugen output).
    function container(accent) {
        return Qt.hsva(accent.hsvHue, Math.min(1, accent.hsvSaturation + 0.3), Math.max(0, accent.hsvValue - 0.5), 1);
    }

    readonly property color base: view.Kirigami.Theme.backgroundColor
    readonly property color mantle: complementary.Kirigami.Theme.backgroundColor
    readonly property color crust: complementary.Kirigami.Theme.backgroundColor
    readonly property color text: Kirigami.Theme.textColor
    readonly property color subtext0: Kirigami.Theme.disabledTextColor
    readonly property color subtext1: Kirigami.Theme.disabledTextColor
    readonly property color surface0: Kirigami.Theme.backgroundColor
    readonly property color surface1: button.Kirigami.Theme.backgroundColor
    readonly property color surface2: button.Kirigami.Theme.backgroundColor
    readonly property color overlay0: Kirigami.Theme.textColor
    readonly property color overlay1: Kirigami.Theme.textColor
    readonly property color overlay2: Kirigami.Theme.textColor
    readonly property color blue: Kirigami.Theme.highlightColor
    readonly property color sapphire: container(blue)
    readonly property color peach: Kirigami.Theme.neutralTextColor
    readonly property color green: Kirigami.Theme.linkColor
    readonly property color red: Kirigami.Theme.negativeTextColor
    readonly property color mauve: Kirigami.Theme.highlightColor
    readonly property color pink: container(peach)
    readonly property color yellow: container(green)
    readonly property color maroon: container(red)
    readonly property color teal: Kirigami.Theme.linkColor

    // What upstream's Material faces read from matugen's JSON.
    // What upstream's Material faces read from matugen's JSON: hex strings, as their resolveColor expects.
    readonly property var matugenColors: ({
        background: String(base),
        surface: String(crust),
        surface_container_lowest: String(base),
        surface_container_low: String(mantle),
        surface_container: String(surface0),
        surface_container_high: String(surface1),
        surface_container_highest: String(surface2),
        surface_variant: String(surface1),
        on_surface: String(text),
        on_surface_variant: String(subtext0),
        on_background: String(text),
        outline: String(subtext1),
        outline_variant: String(surface2),
        inverse_surface: String(overlay0),
        inverse_on_surface: String(base),
        primary: String(blue),
        on_primary: String(Kirigami.Theme.highlightedTextColor),
        primary_container: String(sapphire),
        on_primary_container: String(view.Kirigami.Theme.focusColor),
        secondary: String(green),
        on_secondary: String(base),
        secondary_container: String(yellow),
        on_secondary_container: String(Kirigami.Theme.visitedLinkColor),
        tertiary: String(peach),
        on_tertiary: String(base),
        tertiary_container: String(pink),
        on_tertiary_container: String(text),
        error: String(red),
        on_error: String(base),
        error_container: String(maroon),
        on_error_container: String(text)
    })
}
