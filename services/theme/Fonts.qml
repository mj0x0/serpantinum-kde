pragma Singleton

// The shell's text font (ui.font). Icon glyphs stay on the Nerd Font; only it can draw them.
import "../settings"
import QtQuick
import Quickshell

Singleton {
    readonly property string defaultUi: "JetBrains Mono"
    readonly property string ui: {
        let f = ShellSettings.value("ui.font", null);
        return (f && ("" + f).trim() !== "") ? "" + f : defaultUi;
    }
    readonly property string icons: "Iosevka Nerd Font"
}
