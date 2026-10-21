// Which apps matugen themes as well, and where each one's config lives.

import "../../services/settings"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    // The matugen app catalog install.sh ships; null means missing or unreadable.
    property var appCatalog: null
    FileView {
        path: Quickshell.env("HOME") + "/.config/matugen/apps.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var a = (JSON.parse(text()) || {}).apps;
                root.appCatalog = (a && typeof a.length === "number") ? a : null;
            } catch (e) { root.appCatalog = null; }
        }
        onLoadFailed: root.appCatalog = null
    }
    readonly property var themedApps: {
        var v = ShellSettings.value("appearance.apps", null);
        return (v && typeof v.length === "number") ? v : [];
    }
    readonly property var pathApps: (root.appCatalog || []).filter(
        a => a.path && root.themedApps.indexOf(a.key) !== -1)

    SettingsRow {
        host: root.host
        label: "Application themes"
        glyph: "\u{f03d8}"
        desc: root.appCatalog
            ? "Apps matugen themes as well. Install what each one needs first"
            : "No app catalog yet: run ./install.sh matugen"
    }

    SettingsAppChips {
        host: root.host
        Layout.fillWidth: true
        visible: root.appCatalog !== null
        options: root.appCatalog || []
        current: root.themedApps
        onChanged: v => ShellSettings.setValue("appearance.apps", v)
    }

    Repeater {
        model: root.pathApps
        delegate: SettingsRow {
            id: pathRow
            host: root.host
            required property var modelData
            readonly property string path:
                "" + ShellSettings.value("appearance.appPaths." + modelData.key, "")
            label: modelData.label + ": " + (modelData.path.label || "Path")
            glyph: modelData.glyph || ""
            desc: pathRow.path === "" ? "Skipped until a path is set" : ""
            SettingsPathField {
                host: root.host
                placeholder: pathRow.modelData.path.placeholder || ""
                value: pathRow.path
                onCommitted: v => ShellSettings.setValue(
                    "appearance.appPaths." + pathRow.modelData.key, v)
            }
        }
    }

    SettingsRow {
        host: root.host
        label: "Extra templates"
        glyph: "\u{f0219}"
        desc: "A TOML file in ~/.config/matugen, appended to what matugen renders. Yours to write"
        SettingsPathField {
            host: root.host
            placeholder: "user.toml"
            value: "" + ShellSettings.value("appearance.userToml", "")
            onCommitted: v => ShellSettings.setValue("appearance.userToml", v.trim() || null)
        }
    }
}
