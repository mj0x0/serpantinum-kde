import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Position"
        glyph: "\u{f0463}"
        desc: "follow sits flush against the bar; center grows out of the search field"
        SettingsChips {
            host: page.host
            options: ["follow", "top", "bottom", "left", "right", "center"]
            current: "" + ShellSettings.value("launcher.position", "follow")
            onPicked: v => ShellSettings.setValue("launcher.position", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Width"
        glyph: "\u{f046b}"
        desc: "Pixels, before interface scale"
        SettingsSlider {
            host: page.host
            from: 320; to: 1400; step: 10
            value: Number(ShellSettings.value("launcher.width", 600))
            onCommitted: v => ShellSettings.setValue("launcher.width", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Visible items"
        glyph: "\u{f0279}"
        desc: "Rows shown before the list scrolls"
        SettingsStepper {
            host: page.host
            from: 3; to: 15
            value: Number(ShellSettings.value("launcher.itemCount", 6))
            onCommitted: v => ShellSettings.setValue("launcher.itemCount", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Clipboard position"
        glyph: "\u{f018f}"
        desc: "opposite sits across from the bar, clear of the launcher"
        SettingsChips {
            host: page.host
            options: ["opposite", "top", "bottom", "left", "right"]
            current: "" + ShellSettings.value("clipboard.position", "opposite")
            onPicked: v => ShellSettings.setValue("clipboard.position", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Theme picker position"
        glyph: "\u{f03d8}"
        desc: "center floats; an edge attaches the strip there"
        SettingsChips {
            host: page.host
            options: ["center", "top", "bottom", "left", "right"]
            current: "" + ShellSettings.value("themes.position", "center")
            onPicked: v => ShellSettings.setValue("themes.position", v)
        }
    }
}
