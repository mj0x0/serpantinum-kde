import "../../services/settings"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

BarModuleCard {
    id: card
    moduleId: "workspaces"

    // The bar's pips follow KWin, so the Workspaces stepper edits KWin's desktops, not a setting.
    property int desktopCount: 0
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell/workspaces/workspaces.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { card.desktopCount = JSON.parse(text()).length; } catch (e) {} }
    }
    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"
    function setDesktops(n) { Quickshell.execDetached(["python3", card.helpersDir + "/desktops.py", "set", "" + n]); }

    // Mirrors Workspaces.qml; the bar falls back to the number past the list or on "".
    readonly property var defaultGlyphs: ["\u{f018d}", "\u{f059f}", "\u{f0169}", "\u{f024b}", "\u{f0b79}",
                                          "\u{f075a}", "\u{f0297}", "\u{f02e9}", "\u{f01ee}", "\u{f0493}"]
    readonly property var wsGlyphs: {
        var g = ShellSettings.value("bar.workspaces.glyphs", null);
        return (g && typeof g.length === "number" && g.length > 0) ? g : defaultGlyphs;
    }
    function setWsGlyph(i, g) {
        var arr = wsGlyphs.slice();
        while (arr.length <= i) arr.push("");
        arr[i] = g;
        ShellSettings.setValue("bar.workspaces.glyphs", arr);
    }

    SettingsRow {
        host: card.host
        label: "Workspaces"
        glyph: "\u{f0570}"
        desc: "KDE's virtual desktops, added or removed at the end over D-Bus; the pips follow"
        SettingsStepper {
            host: card.host
            from: 1; to: 20
            value: card.desktopCount
            onCommitted: v => card.setDesktops(v)
        }
    }

    SettingsRow {
        host: card.host
        label: "Workspace style"
        glyph: "\u{f0139}"
        desc: "pills are v2's; glyphs puts an icon on each desktop; shapes rolls a Material shape per focus"
        SettingsChips {
            host: card.host
            options: ["pills", "dots", "squares", "numbers", "glyphs", "shapes", "underline", "pacman"]
            current: "" + ShellSettings.value("bar.workspaces.style", "pills")
            onPicked: v => ShellSettings.setValue("bar.workspaces.style", v)
        }
    }

    SettingsRow {
        host: card.host
        label: "Workspace glyphs"
        glyph: "\u{f0832}"
        visible: ShellSettings.value("bar.workspaces.style", "pills") === "glyphs"
        desc: "Click a desktop to pick its icon. # shows the number instead"
        ColumnLayout {
            spacing: card.host.s(8)
            SettingsGlyphSlots {
                host: card.host
                Layout.preferredWidth: card.host.s(360)
                width: card.host.s(360)
                count: card.desktopCount > 0 ? card.desktopCount : card.defaultGlyphs.length
                glyphs: card.wsGlyphs
                onPicked: (i, g) => card.setWsGlyph(i, g)
            }
            SettingsBtn {
                host: card.host
                Layout.alignment: Qt.AlignRight
                label: "Reset icons"
                onClicked: ShellSettings.setValue("bar.workspaces.glyphs", null)
            }
        }
    }

    SettingsRow {
        host: card.host
        label: "Active indicator"
        glyph: "\u{f04fe}"
        desc: "Sliding highlight (pills, numbers, glyphs) or bar (underline) behind the active one"
        SettingsToggle {
            host: card.host
            checked: ShellSettings.value("bar.workspaces.activeIndicator", true) !== false
            onToggled: v => ShellSettings.setValue("bar.workspaces.activeIndicator", v)
        }
    }

    SettingsRow {
        host: card.host
        label: "Occupied tint"
        glyph: "\u{f0266}"
        desc: "Occupied workspaces read differently from empty ones"
        SettingsToggle {
            host: card.host
            checked: ShellSettings.value("bar.workspaces.occupiedBg", true) !== false
            onToggled: v => ShellSettings.setValue("bar.workspaces.occupiedBg", v)
        }
    }

    SettingsRow {
        host: card.host
        label: "Tint colour"
        glyph: "\u{f00e9}"
        desc: "Palette roles, so it re-themes with the wallpaper"
        SettingsSwatches {
            host: card.host
            width: card.host.s(300)
            options: [
                { key: "text",     color: card.host.text },
                { key: "mauve",    color: card.host.mauve },
                { key: "sapphire", color: card.host.sapphire },
                { key: "green",    color: card.host.green },
                { key: "yellow",   color: card.host.yellow },
                { key: "peach",    color: card.host.peach },
                { key: "pink",     color: card.host.pink },
                { key: "red",      color: card.host.red }
            ]
            current: "" + ShellSettings.value("bar.workspaces.occupiedColor", "text")
            onPicked: v => ShellSettings.setValue("bar.workspaces.occupiedColor", v)
            enabled: ShellSettings.value("bar.workspaces.occupiedBg", true) !== false
            opacity: enabled ? 1 : 0.4
        }
    }

    SettingsRow {
        host: card.host
        label: "Hide empty workspaces"
        glyph: "\u{f05b0}"
        desc: "Only workspaces with windows show; the active one always does"
        SettingsToggle {
            host: card.host
            checked: ShellSettings.value("bar.hideEmptyWorkspaces", false) === true
            onToggled: v => ShellSettings.setValue("bar.hideEmptyWorkspaces", v)
        }
    }
}
