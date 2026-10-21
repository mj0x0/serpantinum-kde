import "../../services/settings"
import QtQuick

BarModuleCard {
    id: card
    moduleId: "sysmon"

    SettingsRow {
        host: card.host
        label: "Vitals shape"
        glyph: "\u{f035b}"
        desc: "pill is the liquid-fill default; wave and circle are ring gauges"
        SettingsChips {
            host: card.host
            options: ["pill", "wave", "circle"]
            current: "" + ShellSettings.value("bar.sysmonStyle", "pill")
            onPicked: v => ShellSettings.setValue("bar.sysmonStyle", v)
        }
    }
}
