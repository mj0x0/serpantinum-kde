import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "HDR"
        glyph: "\u{f0d7d}"
        desc: "Keep HDR on HDR outputs (hevc_hdr, mkv); needs an HDR-aware player, mpv tonemaps it right. Off lets GSR tonemap to SDR, which plays anywhere"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("record.hdr", true) !== false
            onToggled: v => ShellSettings.setValue("record.hdr", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Audio"
        glyph: "\u{f057e}"
        desc: "What the recording hears"
        SettingsChips {
            host: page.host
            options: ["off", "system", "system+mic"]
            current: "" + ShellSettings.value("record.audio", "system")
            onPicked: v => ShellSettings.setValue("record.audio", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Frame rate"
        glyph: "\u{f04c5}"
        desc: "Maximum fps; variable pacing by default"
        SettingsChips {
            host: page.host
            options: ["30", "60", "120", "144"]
            current: "" + ShellSettings.value("record.fps", 60)
            onPicked: v => ShellSettings.setValue("record.fps", Number(v))
        }
    }
    SettingsRow {
        host: page.host
        label: "Quality"
        glyph: "\u{f0435}"
        desc: "GSR quality preset"
        SettingsChips {
            host: page.host
            options: ["medium", "high", "very_high", "ultra"]
            current: "" + ShellSettings.value("record.quality", "very_high")
            onPicked: v => ShellSettings.setValue("record.quality", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "SDR codec"
        glyph: "\u{f061a}"
        desc: "Encoder for SDR files"
        SettingsChips {
            host: page.host
            options: ["h264", "hevc", "av1"]
            current: "" + ShellSettings.value("record.codec", "h264")
            onPicked: v => ShellSettings.setValue("record.codec", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "HDR codec"
        glyph: "\u{f061a}"
        desc: "Encoder for HDR files"
        SettingsChips {
            host: page.host
            options: ["hevc_hdr", "av1_hdr"]
            current: "" + ShellSettings.value("record.hdrCodec", "hevc_hdr")
            onPicked: v => ShellSettings.setValue("record.hdrCodec", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Container"
        glyph: "\u{f03d7}"
        desc: "SDR files; HDR files use the HDR container"
        SettingsChips {
            host: page.host
            options: ["mp4", "mkv", "webm"]
            current: "" + ShellSettings.value("record.container", "mp4")
            onPicked: v => ShellSettings.setValue("record.container", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "HDR container"
        glyph: "\u{f03d7}"
        desc: "mkv carries the HDR metadata reliably"
        SettingsChips {
            host: page.host
            options: ["mkv", "mp4"]
            current: "" + ShellSettings.value("record.hdrContainer", "mkv")
            onPicked: v => ShellSettings.setValue("record.hdrContainer", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Cursor"
        glyph: "\u{f01c0}"
        desc: "Include the pointer"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("record.cursor", true) !== false
            onToggled: v => ShellSettings.setValue("record.cursor", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Frame pacing"
        glyph: "\u{f07da}"
        desc: "cfr for editors that dislike variable frame rate"
        SettingsChips {
            host: page.host
            options: ["vfr", "cfr"]
            current: "" + ShellSettings.value("record.frameMode", "vfr")
            onPicked: v => ShellSettings.setValue("record.frameMode", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Colour range"
        glyph: "\u{f0195}"
        desc: "SDR only; HDR always records full range"
        SettingsChips {
            host: page.host
            options: ["limited", "full"]
            current: "" + ShellSettings.value("record.colorRange", "limited")
            onPicked: v => ShellSettings.setValue("record.colorRange", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Save folder"
        glyph: "\u{f024b}"
        desc: "Screencast_<date>.<ext> lands here"
        SettingsPathField {
            host: page.host
            value: "" + ShellSettings.value("record.dir", "~/Videos/Screencasts")
            onCommitted: v => ShellSettings.setValue("record.dir", v)
        }
    }
}
