import "../../services/settings"
import QtQuick

BarModuleCard {
    id: card
    moduleId: "media"

    SettingsRow {
        host: card.host
        label: "Media player"
        glyph: "\u{f075a}"
        desc: "mini is v2's compact player with a popout; side bars always use mini"
        SettingsChips {
            host: card.host
            options: ["full", "mini"]
            current: "" + ShellSettings.value("bar.media.style", "full")
            onPicked: v => ShellSettings.setValue("bar.media.style", v)
        }
    }
}
