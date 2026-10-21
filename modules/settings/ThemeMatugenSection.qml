// What steers matugen. No upstream counterpart: upstream ships no generator.
// Seed and "Or by rule" write the same key, so they stay in one file.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    // Scheme, seed, mode and contrast only steer matugen; a palette carries its own.
    readonly property bool staticTheme: ("" + ShellSettings.value("appearance.theme", "matugen")) !== "matugen"

    // matugen's candidate seeds for the current wallpaper, written by the hook.
    property var seeds: []
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/seeds.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.seeds = (JSON.parse(text()) || {}).seeds || []; }
            catch (e) { root.seeds = []; }
        }
    }

    SettingsRow {
        host: root.host
        label: "Scheme"
        glyph: "\u{f08b5}"
        visible: !root.staticTheme
        desc: "How matugen derives the palette from the seed colour"
        SettingsChips {
            host: root.host
            width: root.host.s(470)
            options: ["tonal-spot", "vibrant", "expressive", "content",
                      "fidelity", "neutral", "monochrome", "rainbow",
                      "fruit-salad", "smart"]
            current: "" + ShellSettings.value("appearance.schemeType", "tonal-spot")
            onPicked: v => ShellSettings.setValue("appearance.schemeType", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Seed"
        glyph: "\u{f020a}"
        visible: !root.staticTheme
        desc: root.seeds.length
            ? "matugen's candidates for this wallpaper, most dominant first"
            : "Change the wallpaper once to populate these"
        SettingsSwatches {
            host: root.host
            options: root.seeds.map((c, i) => ({ key: "dominant " + (i + 1), color: c }))
            current: "" + ShellSettings.value("appearance.prefer", "dominant 1")
            onPicked: v => ShellSettings.setValue("appearance.prefer", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Or by rule"
        glyph: "\u{f062e}"
        visible: !root.staticTheme
        desc: "Picks without regard to area. No single rule suits every wallpaper"
        SettingsChips {
            host: root.host
            width: root.host.s(330)
            options: ["saturation", "less-saturation", "lightness",
                      "darkness", "value"]
            current: "" + ShellSettings.value("appearance.prefer", "dominant 1")
            onPicked: v => ShellSettings.setValue("appearance.prefer", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Mode"
        glyph: "\u{f0510}"
        visible: !root.staticTheme
        desc: ""
        SettingsChips {
            host: root.host
            options: ["dark", "light", "smart"]
            current: "" + ShellSettings.value("appearance.mode", "dark")
            onPicked: v => ShellSettings.setValue("appearance.mode", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Contrast"
        glyph: "\u{f00df}"
        visible: !root.staticTheme
        desc: "0 is the Material spec; 1 is maximum"
        SettingsSlider {
            host: root.host
            from: -1; to: 1; step: 0.1
            value: ShellSettings.value("appearance.contrast", 0)
            onCommitted: v => ShellSettings.setValue("appearance.contrast", v)
        }
    }
}
