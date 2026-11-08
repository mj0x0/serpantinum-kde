import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Position"
        glyph: "\u{f03ca}"
        desc: "Screen edge the dock is grounded on. On the bar's edge it draws over the bar"
        SettingsChips {
            host: page.host
            options: ["bottom", "top", "left", "right"]
            current: "" + ShellSettings.value("dock.position", "bottom")
            onPicked: v => ShellSettings.setValue("dock.position", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Frosted"
        glyph: "\u{f00a3}"
        desc: "Translucent island with the compositor blur behind it"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("dock.frosted", false) === true
            onToggled: v => ShellSettings.setValue("dock.frosted", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Tinted icons"
        glyph: "\u{f0301}"
        desc: "Recolour app icons with the accent"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("dock.tintIcons", false) === true
            onToggled: v => ShellSettings.setValue("dock.tintIcons", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Live thumbnails"
        glyph: "\u{f0379}"
        desc: "Stream window previews through KWin; needs the screencast grant (extra/README.md)"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("dock.thumbnails", false) === true
            onToggled: v => ShellSettings.setValue("dock.thumbnails", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Disable auto-hide"
        glyph: "\u{f0403}"
        desc: "Keep the dock on screen"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("dock.autoHide", false) !== true
            onToggled: v => ShellSettings.setValue("dock.autoHide", !v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Auto-hide delay"
        glyph: "\u{f051f}"
        desc: "Seconds the dock stays after the pointer leaves"
        SettingsStepper {
            host: page.host
            from: 1; to: 30
            value: Number(ShellSettings.value("dock.hideDelay", 5)) || 5
            enabled: ShellSettings.value("dock.autoHide", false) === true
            opacity: enabled ? 1 : 0.4
            onCommitted: v => ShellSettings.setValue("dock.hideDelay", v)
        }
    }
}
