import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

SettingsPage {
    id: page

    // Installed tesseract packs, read once; empty when tesseract is missing.
    property var ocrLangs: []
    property bool ocrProbed: false
    readonly property var ocrLangOptions: page.ocrLangs.map(l => ({ key: l, label: l, glyph: "" }))
    readonly property var ocrLangsCurrent: ("" + ShellSettings.value("screenshot.ocr.langs", "eng")).split("+")
    Process {
        id: ocrLangProbe
        // Through sh so the stream still finishes when tesseract is absent.
        command: ["sh", "-c", "tesseract --list-langs 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                var lines = this.text.split("\n");
                for (var i = 1; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (l !== "" && l !== "osd") out.push(l);
                }
                page.ocrLangs = out;
                page.ocrProbed = true;
            }
        }
    }
    Component.onCompleted: ocrLangProbe.running = true

    SettingsRow {
        host: page.host
        label: "Languages"
        glyph: "\u{f113d}"
        desc: !page.ocrProbed ? "Looking for installed packs"
            : page.ocrLangs.length === 0
            ? "tesseract is not installed; packs are tesseract-data-<lang>"
            : "Installed tesseract packs; tesseract-data-<lang> adds more"
        SettingsToggleChips {
            host: page.host
            options: page.ocrLangOptions
            current: page.ocrLangsCurrent
            onChanged: v => { if (v.length > 0) ShellSettings.setValue("screenshot.ocr.langs", v.join("+")) }
        }
    }
    SettingsRow {
        host: page.host
        label: "Upscale before recognising"
        glyph: "\u{f0a93}"
        desc: "2x makes UI-sized text readable"
        SettingsChips {
            host: page.host
            options: ["1", "2", "3"]
            current: "" + ShellSettings.value("screenshot.ocr.upscale", 2)
            onPicked: v => ShellSettings.setValue("screenshot.ocr.upscale", Number(v))
        }
    }
    SettingsRow {
        host: page.host
        label: "Copy text automatically"
        glyph: "\u{f018f}"
        desc: "Recognised text lands on the clipboard as soon as it arrives"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("screenshot.ocr.autoCopy", true) !== false
            onToggled: v => ShellSettings.setValue("screenshot.ocr.autoCopy", v)
        }
    }
}
