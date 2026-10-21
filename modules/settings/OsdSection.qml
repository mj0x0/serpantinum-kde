// On-screen display, upstream's OnScreenDisplayTab.qml.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    SettingsRow {
        host: root.host
        label: "Volume OSD"
        glyph: "\u{f057e}"
        desc: "Shows volume and mic changes near the bar. Turn Plasma's own volume OSD "
            + "off in System Settings -> Sound, or the two will stack"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.enabled", true) !== false
            onToggled: v => ShellSettings.setValue("osd.enabled", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "OSD attaches to the bar"
        glyph: "\u{f0176}"
        desc: "Only takes effect on a solid or fill bar at full opacity, with a matching "
            + "orientation; otherwise the position below is used"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.attachToBar", true) !== false
            onToggled: v => ShellSettings.setValue("osd.attachToBar", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "OSD orientation"
        glyph: "\u{f0bbf}"
        desc: "A side bar only attaches a vertical OSD; a top or bottom bar only a horizontal one"
        SettingsChips {
            host: root.host
            options: ["horizontal", "vertical"]
            current: "" + ShellSettings.value("osd.orientation", "horizontal")
            onPicked: v => ShellSettings.setValue("osd.orientation", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "OSD across"
        glyph: "\u{f04c1}"
        desc: "Horizontal position when it is not attached: 0 is the left edge, 100 the right"
        SettingsSlider {
            host: root.host
            from: 0; to: 100; step: 5
            value: Number(ShellSettings.value("osd.horizontalPosition", 50))
            onCommitted: v => ShellSettings.setValue("osd.horizontalPosition", Math.round(v))
        }
    }

    SettingsRow {
        host: root.host
        label: "OSD down"
        glyph: "\u{f04c0}"
        desc: "Vertical position when it is not attached: 0 is the top, 100 the bottom"
        SettingsSlider {
            host: root.host
            from: 0; to: 100; step: 5
            value: Number(ShellSettings.value("osd.verticalPosition", 90))
            onCommitted: v => ShellSettings.setValue("osd.verticalPosition", Math.round(v))
        }
    }
}
