import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Interface scale"
        glyph: "\u{f004c}"
        desc: "Multiplies every size in the shell"
        SettingsSlider {
            host: page.host
            from: 0.6; to: 1.6; step: 0.05
            value: ShellSettings.value("ui.scale", 1.0)
            onCommitted: v => ShellSettings.setValue("ui.scale", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Sound effects"
        glyph: "\u{f057e}"
        desc: "serpantinum v2's clicks and toggles on the shell's own controls"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("ui.sfx", false) === true
            onToggled: v => ShellSettings.setValue("ui.sfx", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Super key"
        glyph: "\u{f030c}"
        desc: "Glyph drawn for Meta in the cheat sheet"
        SettingsChips {
            host: page.host
            options: ["arch", "tux", "windows", "apple", "text"]
            current: ShellSettings.superKeyName
            onPicked: v => ShellSettings.setValue("cheatsheet.superKey", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Settings position"
        glyph: "\u{f0463}"
        desc: "center floats this card; an edge attaches it there, opposite is across from the bar"
        SettingsChips {
            host: page.host
            options: ["center", "opposite", "top", "bottom", "left", "right"]
            current: "" + ShellSettings.value("settings.position", "center")
            onPicked: v => ShellSettings.setValue("settings.position", v)
        }
    }
}
