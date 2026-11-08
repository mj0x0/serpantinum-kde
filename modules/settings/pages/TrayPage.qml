import ".."
import "../../../services/settings"
import "../../../services/tray"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

SettingsPage {
    id: page

    // "red"/"pink"/"green" are also CSS colour names, so a role must be resolved
    // against the palette or the preview silently shows the wrong colour.
    function tintOf(name) {
        if (!name) return page.host.text;
        for (var i = 0; i < page.trayTints.length; i++)
            if (page.trayTints[i].key === name) return page.trayTints[i].color;
        return name;
    }

    // Empty key = no colour stored, i.e. the tray's own default.
    readonly property var trayTints: [
        { key: "",         color: page.host.overlay0 },
        { key: "text",     color: page.host.text },
        { key: "mauve",    color: page.host.mauve },
        { key: "sapphire", color: page.host.sapphire },
        { key: "green",    color: page.host.green },
        { key: "yellow",   color: page.host.yellow },
        { key: "peach",    color: page.host.peach },
        { key: "pink",     color: page.host.pink },
        { key: "red",      color: page.host.red }
    ]

    // Live tray items first, then overrides whose app is not running -- otherwise a
    // stale entry is invisible here and can only be cleared by editing the file.
    readonly property var trayRows: {
        var rows = [], seen = ({});
        var items = SystemTray.items ? SystemTray.items.values : [];
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            var key = it.id || it.title || "";
            if (!key || seen[key]) continue;
            seen[key] = true;
            var ov = TrayOverrides.lookup(it.id, it.title);
            rows.push({ key: key, title: it.title || it.id, running: true,
                        glyph: ov ? ov.glyph : "", color: ov ? ov.color : "",
                        pinned: ov ? ov.pinned === true : false });
        }
        for (var k in TrayOverrides.map) {
            if (seen[k]) continue;
            var v = TrayOverrides.map[k];
            var isStr = (typeof v === "string");
            rows.push({ key: k, title: k, running: false,
                        glyph: isStr ? v : (v && v.glyph ? v.glyph : ""),
                        color: isStr ? "" : (v && v.color ? v.color : ""),
                        pinned: !isStr && v && v.pinned === true });
        }
        return rows;
    }


    SettingsRow {
        host: page.host
        label: "Icon overrides"
        desc: "The switch lifts an app out of the drawer and into the bar. Type a Nerd Font "
            + "glyph to replace its icon; empty keeps its own. The colour is a palette role, "
            + "so it follows the theme. Saved to tray-icons.json"
        glyph: "\u{f129e}"
    }

    Repeater {
        model: page.trayRows
        delegate: SettingsRow {
            host: page.host
            required property var modelData
            label: modelData.title || modelData.key
            desc: modelData.running ? modelData.key : modelData.key + "  •  not running"
            glyph: "\u{f003b}"
            opacity: modelData.running ? 1 : 0.6

            RowLayout {
                spacing: page.host.s(10)

                // Previewed in its override colour, so the field is its own swatch.
                Item {
                    Layout.preferredWidth: page.host.s(24)
                    Layout.preferredHeight: page.host.s(20)
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: page.host.glyphNudge(modelData.glyph, page.host.s(15))
                        text: modelData.glyph || "—"
                        font.family: page.host.glyphFamily
                        font.pixelSize: page.host.s(15)
                        color: modelData.glyph ? page.tintOf(modelData.color) : page.host.overlay0
                    }
                }
                SettingsToggle {
                    host: page.host
                    checked: modelData.pinned
                    onToggled: v => TrayOverrides.setPinned(modelData.key, v)
                }
                SettingsPathField {
                    host: page.host
                    implicitWidth: page.host.s(96)
                    placeholder: "glyph"
                    value: modelData.glyph
                    onCommitted: v => TrayOverrides.setEntry(modelData.key, v, modelData.color)
                }
                SettingsTintPick {
                    host: page.host
                    visible: modelData.glyph !== ""
                    options: page.trayTints
                    current: modelData.color
                    onPicked: v => TrayOverrides.setEntry(modelData.key, modelData.glyph, v)
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.trayRows.length === 0
        text: "No tray items and no overrides yet."
        font.family: page.host.fontFamily
        font.pixelSize: page.host.s(10)
        color: page.host.overlay0
    }
}
