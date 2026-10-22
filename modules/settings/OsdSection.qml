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
        label: "On-screen display"
        glyph: "\u{f057e}"
        desc: "Volume, mic, brightness, keyboard layout, caps and num lock and airplane mode "
            + "near the bar. Plasma's own OSD must be off: plasmarc [OSD] Enabled=false, "
            + "and System Settings -> Sound for volume"
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
        label: "Caps lock OSD"
        glyph: "\u{f0b08}"
        desc: "Caps Lock on/off; never shown in the vertical layout"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.showCapsLock", true) !== false
            onToggled: v => ShellSettings.setValue("osd.showCapsLock", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Num lock OSD"
        glyph: "\u{f03a0}"
        desc: "Num Lock on/off; never shown in the vertical layout"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.showNumLock", true) !== false
            onToggled: v => ShellSettings.setValue("osd.showNumLock", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Airplane mode OSD"
        glyph: "\u{f001d}"
        desc: "When the airplane toggle switches the radios; never shown in the vertical layout"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.showAirplane", true) !== false
            onToggled: v => ShellSettings.setValue("osd.showAirplane", v)
        }
    }

    SettingsRow {
        host: root.host
        label: "Keyboard layout OSD"
        glyph: "\u{f030c}"
        desc: "The layout name when it switches; never shown in the vertical layout"
        SettingsToggle {
            host: root.host
            checked: ShellSettings.value("osd.showKeyboardLayout", true) !== false
            onToggled: v => ShellSettings.setValue("osd.showKeyboardLayout", v)
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
