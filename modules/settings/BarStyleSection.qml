// Bar style, upstream's bar/general/BarStyleSection.qml. Opacity and blur have no
// upstream bar-level counterpart; they stay here so no control changes tab.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    SettingsRow {
        host: root.host
        label: "Style"
        glyph: "\u{f0831}"
        desc: "modular is the segmented default; fill hugs the screen edge"
        SettingsChips {
            host: root.host
            options: ["modular", "solid", "fill"]
            current: "" + ShellSettings.value("bar.style", "modular")
            onPicked: v => ShellSettings.setValue("bar.style", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Opacity"
        glyph: "\u{f05cc}"
        desc: "Background alpha of the bar surfaces"
        SettingsSlider {
            host: root.host
            from: 20; to: 100; step: 5
            value: Number(ShellSettings.value("bar.opacity", 85))
            onCommitted: v => ShellSettings.setValue("bar.opacity", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Blur"
        glyph: "\u{f00a3}"
        desc: "Frost what sits behind the bar surfaces"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("bar.blur", false) === true
            onToggled: v => ShellSettings.setValue("bar.blur", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Distinct pills"
        glyph: "\u{f0409}"
        desc: "Keep the segmented tint on solid and fill"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("bar.distinctPills", false) === true
            onToggled: v => ShellSettings.setValue("bar.distinctPills", v)
        }
    }
}
