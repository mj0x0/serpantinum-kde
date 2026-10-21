import "../../services/settings"
import QtQuick

BarModuleCard {
    id: card
    moduleId: "actions"

    readonly property var actionOptions: [
        { key: "settings", label: "Settings", glyph: "\u{f0493}" },
        { key: "search",   label: "Search",   glyph: "\u{f0349}" },
        { key: "focus",    label: "Focus",    glyph: "\u{f0109}" }
    ]
    readonly property var enabledActions: {
        var v = ShellSettings.value("bar.actions", null);
        return (v && typeof v.length === "number") ? v : ["settings", "search", "focus"];
    }

    SettingsRow {
        host: card.host
        label: "Actions"
        glyph: "\u{f12a8}"
        desc: "Buttons in the Actions widget; with none picked it leaves the bar"
        SettingsToggleChips {
            host: card.host
            options: card.actionOptions
            current: card.enabledActions
            onChanged: v => ShellSettings.setValue("bar.actions", v)
        }
    }
}
