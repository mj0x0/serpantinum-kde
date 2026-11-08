import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Capture on release"
        glyph: "\u{f0100}"
        desc: "Take the shot as soon as the drag ends instead of a second click"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("screenshot.captureOnRelease", false) === true
            onToggled: v => ShellSettings.setValue("screenshot.captureOnRelease", v)
        }
    }
    SettingsHeading { host: page.host; text: "Overlay keys" }
    SettingsRow { host: page.host; label: "Tab, Left, Right"; glyph: "\u{f030c}"; desc: "Switch between screenshot and recording" }
    SettingsRow { host: page.host; label: "Space, Return"; glyph: "\u{f030c}"; desc: "Take the shot, or start and stop the recording" }
    SettingsRow { host: page.host; label: "F"; glyph: "\u{f030c}"; desc: "Whole screen; in video mode it records right away" }
    SettingsRow { host: page.host; label: "T"; glyph: "\u{f030c}"; desc: "Recognise the text in the selection" }
    SettingsRow { host: page.host; label: "F11"; glyph: "\u{f030c}"; desc: "Maximise the selection" }
    SettingsRow { host: page.host; label: "Escape"; glyph: "\u{f030c}"; desc: "Close a result card, then the overlay" }
}
