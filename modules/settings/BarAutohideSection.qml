// Bar autohide, upstream's bar/general/BarAutohideSection.qml.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    SettingsRow {
        host: root.host
        label: "Autohide"
        glyph: "\u{f0209}"
        desc: "Bar slides away; hover the screen edge to reveal"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("bar.autohide", false) === true
            onToggled: v => ShellSettings.setValue("bar.autohide", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Autohide delay"
        glyph: "\u{f051f}"
        desc: "How long the bar lingers, in milliseconds"
        SettingsSlider {
            host: root.host
            from: 0; to: 3000; step: 100
            value: Number(ShellSettings.value("bar.autohideTimeout", 1000))
            onCommitted: v => ShellSettings.setValue("bar.autohideTimeout", v)
        }
    }
}
