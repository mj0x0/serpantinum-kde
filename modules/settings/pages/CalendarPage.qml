import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Week starts"
        glyph: "\u{f00ed}"
        desc: "Locale follows your system"
        SettingsChips {
            host: page.host
            options: ["locale", "sunday", "monday"]
            current: "" + ShellSettings.value("calendar.weekStart", "locale")
            onPicked: v => ShellSettings.setValue("calendar.weekStart", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Astronomical events"
        glyph: "\u{f0594}"
        desc: "Solstices, equinoxes and the four moon phases, beside the holidays"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("calendar.astro", false) === true
            onToggled: v => ShellSettings.setValue("calendar.astro", v)
        }
    }
}
