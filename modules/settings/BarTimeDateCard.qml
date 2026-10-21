import "../../services/settings"
import QtQuick

BarModuleCard {
    id: card
    moduleId: "timedate"

    SettingsRow {
        host: card.host
        label: "Clock face"
        glyph: "\u{f00f0}"
        desc: "classic stacks time over date; material drops the minute on a diagonal; badge is a dot matrix"
        SettingsChips {
            host: card.host
            options: ["classic", "material", "badge"]
            current: "" + ShellSettings.value("bar.timeStyle", "classic")
            onPicked: v => ShellSettings.setValue("bar.timeStyle", v)
        }
    }
}
