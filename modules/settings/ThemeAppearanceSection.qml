// Shell-wide look, upstream's theme/ThemeAppearanceSection.qml.

import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    SettingsRow {
        host: root.host
        label: "Corner radius"
        glyph: "\u{f0607}"
        desc: Radius.active
            ? "serpantinum v2's rounded style, in px: 0 is square, 64 the roundest"
            : "Off: each popup keeps its own corners"
        RowLayout {
            spacing: root.host.s(12)
            SettingsSlider {
                host: root.host
                visible: Radius.active
                from: 0; to: 64; step: 1
                value: Radius.value
                onCommitted: v => ShellSettings.setValue("ui.radius", v)
            }
            SettingsToggle {
                host: root.host
                checked: Radius.active
                onToggled: v => ShellSettings.setValue("ui.radius", v ? 8 : null)
            }
        }
    }

    SettingsRow {
        host: root.host
        label: "Font"
        glyph: "\u{f06d6}"
        desc: "Text across the shell; icons stay on Iosevka Nerd Font. Now: " + Fonts.ui
        ColumnLayout {
            spacing: root.host.s(6)
            SettingsFontPicker {
                host: root.host
                current: Fonts.ui
                onPicked: f => ShellSettings.setValue("ui.font", f)
            }
            SettingsBtn {
                host: root.host
                label: "Reset to " + Fonts.defaultUi
                onClicked: ShellSettings.setValue("ui.font", null)
            }
        }
    }
}
