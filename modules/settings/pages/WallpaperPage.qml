import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Images"
        glyph: "\u{f024f}"
        desc: ""
        SettingsPathField {
            host: page.host
            value: "" + ShellSettings.value("wallpaper.imageDir", "~/Pictures/Wallpapers")
            onCommitted: v => ShellSettings.setValue("wallpaper.imageDir", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Videos"
        glyph: "\u{f0567}"
        desc: "Told apart by extension, not folder"
        SettingsPathField {
            host: page.host
            value: "" + ShellSettings.value("wallpaper.videoDir", "~/Pictures/Wallpapers")
            onCommitted: v => ShellSettings.setValue("wallpaper.videoDir", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Hand card size"
        glyph: "\u{f0831}"
        desc: "Percent of the default card size in the card-hand picker"
        SettingsSlider {
            host: page.host
            from: 50; to: 200; step: 10
            value: Number(ShellSettings.value("wallpaper.hand.cardSize", 100)) || 100
            onCommitted: v => ShellSettings.setValue("wallpaper.hand.cardSize", Math.round(v))
        }
    }
    SettingsRow {
        host: page.host
        label: "Wall columns"
        glyph: "\u{f0831}"
        desc: "Cards per row in the wall picker"
        SettingsStepper {
            host: page.host
            from: 3; to: 8
            value: Number(ShellSettings.value("wallpaper.wall.columns", 5)) || 5
            onCommitted: v => ShellSettings.setValue("wallpaper.wall.columns", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Preview: transition"
        glyph: "\u{f0831}"
        desc: "Name the transition playing in the Space preview"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("wallpaper.preview.shader", true) !== false
            onToggled: v => ShellSettings.setValue("wallpaper.preview.shader", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Preview: file name"
        glyph: "\u{f0831}"
        desc: "Show the wallpaper's file name in the preview"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("wallpaper.preview.name", true) !== false
            onToggled: v => ShellSettings.setValue("wallpaper.preview.name", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Preview: colours"
        glyph: "\u{f0831}"
        desc: "Five dominant colours, extracted once per wallpaper"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("wallpaper.preview.colors", true) !== false
            onToggled: v => ShellSettings.setValue("wallpaper.preview.colors", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Wallhaven downloads"
        glyph: "\u{f024d}"
        desc: "Empty follows Images, so downloads show up in the local tabs"
        SettingsPathField {
            host: page.host
            placeholder: "Same as Images"
            value: "" + ShellSettings.value("wallpaper.wallhaven.dir", "")
            onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.dir", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Apply on download"
        glyph: "\u{f1a00}"
        desc: "Set a wallhaven download as the wallpaper the moment it lands"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("wallpaper.wallhaven.applyOnDownload", false) === true
            onToggled: v => ShellSettings.setValue("wallpaper.wallhaven.applyOnDownload", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Wallhaven tiles per row"
        glyph: "\u{f11d9}"
        desc: "Columns in the picker's Wallhaven tab"
        SettingsStepper {
            host: page.host
            from: 3; to: 10
            value: Number(ShellSettings.value("wallpaper.wallhaven.columns", 5))
            onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.columns", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Wallhaven API key"
        glyph: "\u{f0306}"
        desc: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
            ? "Set. Unlocks NSFW results; type a new one to replace it."
            : "Optional, only for NSFW results."
        Item {
            implicitWidth: whKeyField.implicitWidth + whClearKey.implicitWidth + page.host.s(10)
            implicitHeight: whKeyField.implicitHeight

            SettingsSecretField {
                id: whKeyField
                host: page.host
                anchors.verticalCenter: parent.verticalCenter
                placeholder: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                    ? "••••••••  press Enter to replace" : "paste key, press Enter"
                onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.apiKey", ("" + v).trim())
            }
            SettingsBtn {
                id: whClearKey
                host: page.host
                anchors.left: whKeyField.right
                anchors.leftMargin: page.host.s(10)
                anchors.verticalCenter: parent.verticalCenter
                label: "Clear"
                visible: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                onClicked: ShellSettings.setValue("wallpaper.wallhaven.apiKey", "")
            }
        }
    }
}
