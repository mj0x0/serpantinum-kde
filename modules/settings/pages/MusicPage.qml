import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Lyrics highlight"
        glyph: "\u{f0370}"
        desc: "sing-along lights each word when the track has word timings, lines otherwise"
        SettingsChips {
            host: page.host
            options: ["lines", "sing-along"]
            current: "" + ShellSettings.value("lyrics.highlight", "sing-along")
            onPicked: v => ShellSettings.setValue("lyrics.highlight", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Lyrics size"
        glyph: "\u{f0b64}"
        desc: "Scales the lyric text; Ctrl+= and Ctrl+- do it from the popup, Ctrl+0 resets"
        SettingsSlider {
            host: page.host
            from: 0.7; to: 2.0; step: 0.1
            value: Number(ShellSettings.value("lyrics.scale", 1.0))
            onCommitted: v => ShellSettings.setValue("lyrics.scale", v)
        }
    }
}
