import "../../services/settings"
import QtQuick

BarModuleCard {
    id: card
    moduleId: "bat"

    SettingsRow {
        host: card.host
        label: "Battery shape"
        glyph: "\u{f0079}"
        desc: "classic is the gradient wave fill; minimal adds a cap; text drops the pill"
        SettingsChips {
            host: card.host
            options: ["classic", "minimal", "text"]
            current: "" + ShellSettings.value("bar.batStyle", "classic")
            onPicked: v => ShellSettings.setValue("bar.batStyle", v)
        }
    }
}
