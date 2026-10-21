// Bar placement, upstream's bar/general/BarPlacementSection.qml.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    SettingsRow {
        host: root.host
        label: "Position"
        glyph: "\u{f0053}"
        desc: "Which screen edge holds the bar"
        SettingsChips {
            host: root.host
            options: ["top", "bottom", "left", "right"]
            current: "" + ShellSettings.value("bar.position", "top")
            onPicked: v => ShellSettings.setValue("bar.position", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Size"
        glyph: "\u{f084e}"
        desc: "Scales the bar and every widget in it"
        SettingsSlider {
            host: root.host
            from: 0.6; to: 1.4; step: 0.05
            value: Number(ShellSettings.value("bar.size", 1.0))
            onCommitted: v => ShellSettings.setValue("bar.size", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Width"
        glyph: "\u{f046b}"
        desc: "Percent of the screen edge; never below the content. fill ignores it"
        SettingsSlider {
            host: root.host
            from: 25; to: 100; step: 5
            value: Number(ShellSettings.value("bar.width", 100))
            onCommitted: v => ShellSettings.setValue("bar.width", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Fit width"
        glyph: "\u{f084c}"
        desc: "Bar hugs its content — no dead space; Width is ignored"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("bar.fitWidth", false) === true
            onToggled: v => ShellSettings.setValue("bar.fitWidth", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Make room for the panel"
        glyph: "\u{f04e1}"
        desc: "Centre and right sections slide left while the System Panel is open"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("bar.packForPanel", false) === true
            onToggled: v => ShellSettings.setValue("bar.packForPanel", v)
        }
    }
}
