// Settings in serpantinum v2's guide look (guide/GuidePopup.qml): a centred card, the
// sidebar with a gliding highlight, one page of card rows per tab, v2's own controls.

import "../../services/dnd"
import "../../services/reusables" as V2
import "../../services/layout"
import "../../services/polkit"
import "../../services/settings"
import "../../services/theme"
import "../../services/tray"
import "../../services/wallpaper"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

Item {
    id: window

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    MatugenColors { id: _theme }

    function s(v) { return scaler.s(v) }

    readonly property color base:     _theme.base
    readonly property color mantle:   _theme.mantle
    readonly property color crust:    _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color accent:   _theme.mauve

    // Accent roles offered as pickable tints.
    readonly property color mauve:    _theme.mauve
    readonly property color sapphire: _theme.sapphire
    readonly property color green:    _theme.green
    readonly property color yellow:   _theme.yellow
    readonly property color peach:    _theme.peach
    readonly property color pink:     _theme.pink
    readonly property color red:      _theme.red

    readonly property string fontFamily: Fonts.ui
    readonly property string glyphFamily: "Iosevka Nerd Font"

    // Nerd Font MDI glyphs keep a one-cell advance but ink past it, so centring the
    // advance box lands them right of centre. boundingRect IS the advance box (always
    // centred, i.e. no nudge at all) — the ink is tightBoundingRect.
    FontMetrics { id: glyphMetrics; font.family: window.glyphFamily; font.pixelSize: window.s(16) }
    function glyphNudge(g, px) {
        if (!g) return 0;
        var br = glyphMetrics.tightBoundingRect(g);
        var dx = glyphMetrics.advanceWidth(g) / 2 - (br.x + br.width / 2);
        return Math.round(dx * (px === undefined ? 1 : px / window.s(16)));
    }

    property int currentTab: 0

    // The bar's pips follow KWin, so the Workspaces stepper edits KWin's desktops, not a setting.
    property int desktopCount: 0
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell/workspaces/workspaces.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { window.desktopCount = JSON.parse(text()).length; } catch (e) {} }
    }
    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"
    function setDesktops(n) { Quickshell.execDetached(["python3", window.helpersDir + "/desktops.py", "set", "" + n]); }

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

    readonly property var actionOptions: [
        { key: "settings", label: "Settings", glyph: "\u{f0493}" },
        { key: "search",   label: "Search",   glyph: "\u{f0349}" },
        { key: "focus",    label: "Focus",    glyph: "\u{f0109}" }
    ]
    readonly property var enabledActions: {
        var v = ShellSettings.value("bar.actions", null);
        return (v && typeof v.length === "number") ? v : ["settings", "search", "focus"];
    }

    // Polkit allows one agent per session: KDE's unit has to be masked before ours can register.
    property string kdeAgentState: ""
    Process {
        id: kdeAgentProbe
        running: true
        command: ["systemctl", "--user", "is-enabled", "plasma-polkit-agent.service"]
        stdout: StdioCollector {
            onStreamFinished: {
                var was = window.kdeAgentState;
                window.kdeAgentState = this.text.trim();
                // Our agent only registers at construction, and polkit allows one per session.
                // The guard matters: naming PolkitService builds it, and an unwanted agent
                // would take the slot KDE is meant to keep.
                if (was !== "" && was !== "masked" && window.kdeAgentState === "masked"
                    && ShellSettings.value("polkit.enabled", false) === true)
                    PolkitService.reregister();
            }
        }
    }
    // `mask --now` is detached, so the unit takes a moment to go; re-probe a few times.
    Timer {
        id: kdeAgentRefresh
        interval: 1500
        repeat: true
        property int left: 0
        onTriggered: {
            kdeAgentProbe.running = false;
            kdeAgentProbe.running = true;
            if (--kdeAgentRefresh.left <= 0)
                kdeAgentRefresh.stop();
        }
    }
    function kdeAgent(mask) {
        Quickshell.execDetached(["sh", "-c", mask
            ? "systemctl --user mask --now plasma-polkit-agent.service"
            : "systemctl --user unmask plasma-polkit-agent.service && systemctl --user start plasma-polkit-agent.service"]);
        kdeAgentRefresh.left = 4;
        kdeAgentRefresh.restart();
    }

    // Scheme, seed, mode and contrast only steer matugen; a palette carries its own.
    readonly property bool staticTheme: ("" + ShellSettings.value("appearance.theme", "matugen")) !== "matugen"

    // matugen's candidate seeds for the current wallpaper, written by the hook.
    property var seeds: []
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/seeds.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { window.seeds = (JSON.parse(text()) || {}).seeds || []; }
            catch (e) { window.seeds = []; }
        }
    }

    // The matugen app catalog install.sh ships; null means missing or unreadable.
    property var appCatalog: null
    FileView {
        path: Quickshell.env("HOME") + "/.config/matugen/apps.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var a = (JSON.parse(text()) || {}).apps;
                window.appCatalog = (a && typeof a.length === "number") ? a : null;
            } catch (e) { window.appCatalog = null; }
        }
        onLoadFailed: window.appCatalog = null
    }
    readonly property var themedApps: {
        var v = ShellSettings.value("appearance.apps", null);
        return (v && typeof v.length === "number") ? v : [];
    }
    readonly property var pathApps: (window.appCatalog || []).filter(
        a => a.path && window.themedApps.indexOf(a.key) !== -1)

    // Deep link: SettingsState.section names a tab, matched case-insensitively.
    function tabIndexOf(name) {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].name.toLowerCase() === ("" + name).toLowerCase()) return i;
        return -1;
    }
    function syncSection() {
        var i = tabIndexOf(SettingsState.section);
        if (i >= 0) currentTab = i;
    }
    Component.onCompleted: { syncSection(); intro.start(); }
    Connections {
        target: SettingsState
        function onSectionChanged() { window.syncSection() }
    }

    // "red"/"pink"/"green" are also CSS colour names, so a role must be resolved
    // against the palette or the preview silently shows the wrong colour.
    function tintOf(name) {
        if (!name) return window.text;
        for (var i = 0; i < window.trayTints.length; i++)
            if (window.trayTints[i].key === name) return window.trayTints[i].color;
        return name;
    }

    // Empty key = no colour stored, i.e. the tray's own default.
    readonly property var trayTints: [
        { key: "",         color: window.overlay0 },
        { key: "text",     color: window.text },
        { key: "mauve",    color: window.mauve },
        { key: "sapphire", color: window.sapphire },
        { key: "green",    color: window.green },
        { key: "yellow",   color: window.yellow },
        { key: "peach",    color: window.peach },
        { key: "pink",     color: window.pink },
        { key: "red",      color: window.red }
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
                        glyph: ov ? ov.glyph : "", color: ov ? ov.color : "" });
        }
        for (var k in TrayOverrides.map) {
            if (seen[k]) continue;
            var v = TrayOverrides.map[k];
            var isStr = (typeof v === "string");
            rows.push({ key: k, title: k, running: false,
                        glyph: isStr ? v : (v && v.glyph ? v.glyph : ""),
                        color: isStr ? "" : (v && v.color ? v.color : "") });
        }
        return rows;
    }

    // "user:foo.service" / "system:bar.service"; the Servers tab merges these with the
    // containers and the listening ports it recognises on its own.
    readonly property var serverUnits: {
        var v = ShellSettings.value("servers.units", null);
        // Strings only, as the helper reads them: a row it would skip must not be listed.
        return Array.isArray(v) ? v.filter(e => typeof e === "string") : [];
    }
    readonly property var serverPorts: {
        var v = ShellSettings.value("servers.ports", null);
        return (v && typeof v === "object" && !Array.isArray(v)) ? v : ({});
    }
    // As the helper reads them: only a user: prefix is a user unit, a bare name is a system one.
    function serverKind(entry) { return ("" + entry).indexOf("user:") === 0 ? "user" : "system" }
    function serverUnit(entry) {
        var i = ("" + entry).indexOf(":");
        return i < 0 ? "" + entry : ("" + entry).substring(i + 1);
    }
    // Every form the helper accepts: a number, a string, a list of either, under the full
    // unit name or its bare base. A hand-edited override has to be visible to be editable.
    function serverPort(unit) {
        var v = serverPorts[unit];
        if (v === undefined)
            v = serverPorts[serverBase(unit)];
        var list = Array.isArray(v) ? v : [v];
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var n = parseInt(list[i], 10);
            if (isFinite(n) && n > 0 && n < 65536 && out.indexOf(n) === -1)
                out.push(n);
        }
        return out.join(" ");
    }
    function serverBase(unit) { return ("" + unit).replace(/\.[a-z]+$/, "") }
    function addServer(kind, name) {
        var n = ("" + name).trim();
        if (n === "") return;
        if (n.indexOf(".") < 0) n += ".service";
        var entry = kind + ":" + n;
        var arr = serverUnits.slice();
        if (arr.indexOf(entry) !== -1) return;
        arr.push(entry);
        ShellSettings.setValue("servers.units", arr);
    }
    function dropServer(entry) {
        var arr = serverUnits.filter(e => e !== entry);
        ShellSettings.setValue("servers.units", arr);
        // A port left behind has no row to clear it from.
        var unit = serverUnit(entry);
        var held = serverPorts[unit] !== undefined || serverPorts[serverBase(unit)] !== undefined;
        if (held && !arr.some(e => serverUnit(e) === unit))
            setServerPort(unit, "");
    }
    // Unit names carry dots, so the map is rewritten whole: a dotted setValue path
    // would nest "jellyfin" above "service". Returns what was stored, so a field holding a
    // value this threw away can clear itself instead of lying.
    function setServerPort(unit, port) {
        var base = serverBase(unit);
        var next = ({});
        for (var k in serverPorts)
            if (k !== unit && k !== base) next[k] = serverPorts[k];
        var ports = [];
        var bits = ("" + port).split(/[^0-9]+/);
        for (var i = 0; i < bits.length; i++) {
            var n = parseInt(bits[i], 10);
            if (isFinite(n) && n > 0 && n < 65536 && ports.indexOf(n) === -1)
                ports.push(n);
        }
        if (ports.length === 1) next[unit] = ports[0];
        else if (ports.length > 1) next[unit] = ports;
        ShellSettings.setValue("servers.ports", next);
        return ports.join(" ");
    }

    readonly property var tabs: [
        { name: "General",    icon: "\u{f0493}" },
        { name: "Appearance", icon: "\u{f0765}" },
        { name: "Bar",        icon: "\u{f0309}" },
        { name: "Tray",       icon: "\u{f0f1d}" },
        { name: "Notifications", icon: "\u{f009a}" },
        { name: "Launcher",   icon: "\u{f0349}" },
        { name: "Dock",       icon: "\u{f10a9}" },
        { name: "Wallpaper",  icon: "\u{f05e2}" },
        { name: "Music",      icon: "\u{f075a}" },
        { name: "Calendar",   icon: "\u{f00ed}" },
        { name: "Weather",    icon: "\u{f0590}" },
        { name: "Network",    icon: "\u{f0317}" },
        { name: "System",     icon: "\u{f0ad1}" }
    ]

    // v2's guide intro: the card settles, the sidebar slides in, tabs stagger, content rises.
    property real introBase: 0
    property real introSidebar: 0
    property real introTabs: 0
    property real introContent: 0

    function tabProgress(i) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        var p = Math.min(1, Math.max(0, (introTabs - i * 0.04) / 0.42));
        if (p <= 0) return 0;
        if (p >= 1) return 1;
        var c1 = 0.85, c3 = c1 + 1;
        return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2);
    }
    function tabOpacity(i) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        return Math.min(1, Math.max(0, (introTabs - i * 0.04) / 0.28));
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: window; property: "introBase"; from: 0; to: 1; duration: 650; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: window; property: "introSidebar"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTabs"; from: 0; to: 1; duration: 550 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
        }
    }

    Item {
        anchors.fill: parent
        opacity: window.introBase
        scale: 0.95 + 0.05 * window.introBase

        Rectangle {
            anchors.fill: parent
            color: window.base
            radius: Radius.eased(window.s(18))
            border.color: window.surface0
            border.width: 1

            // --- sidebar ---
            Rectangle {
                id: sidebar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: window.s(260)
                topLeftRadius: Radius.eased(window.s(18))
                bottomLeftRadius: Radius.eased(window.s(18))
                color: Qt.alpha(window.surface0, 0.4)
                opacity: window.introSidebar
                transform: Translate { x: window.s(-30) * (1.0 - window.introSidebar) }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(15)
                    spacing: window.s(10)

                Flickable {
                    id: tabsFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: tabsCol.implicitHeight + window.s(20)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    // One highlight glides between tabs instead of each tab colouring itself.
                    Rectangle {
                        z: 0
                        radius: Radius.outer(window.s(8))
                        color: window.accent
                        y: window.currentTab * (window.s(44) + window.s(4))
                        width: tabsCol.width
                        height: window.s(44)
                        opacity: window.tabOpacity(window.currentTab)
                        transform: Translate { x: window.s(-24) * (1.0 - window.tabProgress(window.currentTab)) }
                        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    }

                    ColumnLayout {
                        id: tabsCol
                        width: tabsFlick.width
                        spacing: window.s(4)
                        z: 1

                        Repeater {
                            model: window.tabs
                            delegate: NavItem {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                slot: index
                                label: modelData.name
                                glyph: modelData.icon
                                active: window.currentTab === index
                                onPicked: window.currentTab = index
                            }
                        }
                    }
                }

                NavItem {
                    Layout.fillWidth: true
                    slot: window.tabs.length
                    label: "Close"
                    hint: "Esc"
                    glyph: "\u{f0156}"
                    onPicked: SettingsState.hide()
                }
                }
            }

            // --- content ---
            Item {
                anchors.left: sidebar.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                opacity: window.introContent
                scale: 0.95 + 0.05 * window.introContent
                transform: Translate { y: window.s(20) * (1.0 - window.introContent) }

                StackLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(8)
                    currentIndex: window.currentTab

                    // General
                    Page {
                        title: "General"
                        Row {
                            label: "Interface scale"
                            glyph: "\u{f004c}"
                            desc: "Multiplies every size in the shell"
                            Slider {
                                from: 0.6; to: 1.6; step: 0.05
                                value: ShellSettings.value("ui.scale", 1.0)
                                onCommitted: v => ShellSettings.setValue("ui.scale", v)
                            }
                        }
                        Row {
                            label: "Sound effects"
                            glyph: "\u{f057e}"
                            desc: "serpantinum v2's clicks and toggles on the shell's own controls"
                            Toggle {
                                checked: ShellSettings.value("ui.sfx", false) === true
                                onToggled: v => ShellSettings.setValue("ui.sfx", v)
                            }
                        }
                        Row {
                            label: "Super key"
                            glyph: "\u{f030c}"
                            desc: "Glyph drawn for Meta in the cheat sheet"
                            Chips {
                                options: ["arch", "tux", "windows", "apple", "text"]
                                current: ShellSettings.superKeyName
                                onPicked: v => ShellSettings.setValue("cheatsheet.superKey", v)
                            }
                        }
                    }

                    // Appearance
                    Page {
                        title: "Appearance"
                        ThemeGrid {
                            Layout.fillWidth: true
                            host: window
                        }
                        Row {
                            label: "Corner radius"
                            glyph: "\u{f0607}"
                            desc: Radius.active
                                ? "serpantinum v2's rounded style, in px: 0 is square, 64 the roundest"
                                : "Off: each popup keeps its own corners"
                            RowLayout {
                                spacing: window.s(12)
                                Slider {
                                    visible: Radius.active
                                    from: 0; to: 64; step: 1
                                    value: Radius.value
                                    onCommitted: v => ShellSettings.setValue("ui.radius", v)
                                }
                                Toggle {
                                    checked: Radius.active
                                    onToggled: v => ShellSettings.setValue("ui.radius", v ? 8 : null)
                                }
                            }
                        }
                        Row {
                            label: "Font"
                            glyph: "\u{f06d6}"
                            desc: "Text across the shell; icons stay on Iosevka Nerd Font. Now: " + Fonts.ui
                            ColumnLayout {
                                spacing: window.s(6)
                                FontPicker {
                                    current: Fonts.ui
                                    onPicked: f => ShellSettings.setValue("ui.font", f)
                                }
                                Btn {
                                    label: "Reset to " + Fonts.defaultUi
                                    onClicked: ShellSettings.setValue("ui.font", null)
                                }
                            }
                        }
                        Row {
                            label: "Scheme"
                            glyph: "\u{f08b5}"
                            visible: !window.staticTheme
                            desc: "How matugen derives the palette from the seed colour"
                            Chips {
                                width: window.s(470)
                                options: ["tonal-spot", "vibrant", "expressive", "content",
                                          "fidelity", "neutral", "monochrome", "rainbow",
                                          "fruit-salad", "smart"]
                                current: "" + ShellSettings.value("appearance.schemeType", "tonal-spot")
                                onPicked: v => ShellSettings.setValue("appearance.schemeType", v)
                            }
                        }
                        Row {
                            label: "Seed"
                            glyph: "\u{f020a}"
                            visible: !window.staticTheme
                            desc: window.seeds.length
                                ? "matugen's candidates for this wallpaper, most dominant first"
                                : "Change the wallpaper once to populate these"
                            Swatches {
                                options: window.seeds.map((c, i) => ({ key: "dominant " + (i + 1), color: c }))
                                current: "" + ShellSettings.value("appearance.prefer", "dominant 1")
                                onPicked: v => ShellSettings.setValue("appearance.prefer", v)
                            }
                        }
                        Row {
                            label: "Or by rule"
                            glyph: "\u{f062e}"
                            visible: !window.staticTheme
                            desc: "Picks without regard to area. No single rule suits every wallpaper"
                            Chips {
                                width: window.s(330)
                                options: ["saturation", "less-saturation", "lightness",
                                          "darkness", "value"]
                                current: "" + ShellSettings.value("appearance.prefer", "dominant 1")
                                onPicked: v => ShellSettings.setValue("appearance.prefer", v)
                            }
                        }
                        Row {
                            label: "Mode"
                            glyph: "\u{f0510}"
                            visible: !window.staticTheme
                            desc: ""
                            Chips {
                                options: ["dark", "light", "smart"]
                                current: "" + ShellSettings.value("appearance.mode", "dark")
                                onPicked: v => ShellSettings.setValue("appearance.mode", v)
                            }
                        }
                        Row {
                            label: "Contrast"
                            glyph: "\u{f00df}"
                            visible: !window.staticTheme
                            desc: "0 is the Material spec; 1 is maximum"
                            Slider {
                                from: -1; to: 1; step: 0.1
                                value: ShellSettings.value("appearance.contrast", 0)
                                onCommitted: v => ShellSettings.setValue("appearance.contrast", v)
                            }
                        }
                        Row {
                            label: "Application themes"
                            glyph: "\u{f03d8}"
                            desc: window.appCatalog
                                ? "Apps matugen themes as well. Install what each one needs first"
                                : "No app catalog yet: run ./install.sh matugen"
                        }
                        AppChips {
                            Layout.fillWidth: true
                            visible: window.appCatalog !== null
                            options: window.appCatalog || []
                            current: window.themedApps
                            onChanged: v => ShellSettings.setValue("appearance.apps", v)
                        }
                        Repeater {
                            model: window.pathApps
                            delegate: Row {
                                id: pathRow
                                required property var modelData
                                readonly property string path:
                                    "" + ShellSettings.value("appearance.appPaths." + modelData.key, "")
                                label: modelData.label + ": " + (modelData.path.label || "Path")
                                glyph: modelData.glyph || ""
                                desc: pathRow.path === "" ? "Skipped until a path is set" : ""
                                PathField {
                                    placeholder: pathRow.modelData.path.placeholder || ""
                                    value: pathRow.path
                                    onCommitted: v => ShellSettings.setValue(
                                        "appearance.appPaths." + pathRow.modelData.key, v)
                                }
                            }
                        }
                        Row {
                            label: "Extra templates"
                            glyph: "\u{f0219}"
                            desc: "A TOML file in ~/.config/matugen, appended to what matugen renders. Yours to write"
                            PathField {
                                placeholder: "user.toml"
                                value: "" + ShellSettings.value("appearance.userToml", "")
                                onCommitted: v => ShellSettings.setValue("appearance.userToml", v.trim() || null)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Changes apply at once: the matugen hook re-renders every template in the background"
                            font.family: window.fontFamily
                            font.pixelSize: window.s(9)
                            color: window.overlay0
                            wrapMode: Text.Wrap
                        }
                    }

                    // Bar
                    Page {
                        title: "Bar"
                        Row {
                            label: "Style"
                            glyph: "\u{f0831}"
                            desc: "modular is the segmented default; fill hugs the screen edge"
                            Chips {
                                options: ["modular", "solid", "fill"]
                                current: "" + ShellSettings.value("bar.style", "modular")
                                onPicked: v => ShellSettings.setValue("bar.style", v)
                            }
                        }
                        Row {
                            label: "Position"
                            glyph: "\u{f0053}"
                            desc: "Which screen edge holds the bar"
                            Chips {
                                options: ["top", "bottom", "left", "right"]
                                current: "" + ShellSettings.value("bar.position", "top")
                                onPicked: v => ShellSettings.setValue("bar.position", v)
                            }
                        }
                        Row {
                            label: "Size"
                            glyph: "\u{f084e}"
                            desc: "Scales the bar and every widget in it"
                            Slider {
                                from: 0.6; to: 1.4; step: 0.05
                                value: Number(ShellSettings.value("bar.size", 1.0))
                                onCommitted: v => ShellSettings.setValue("bar.size", v)
                            }
                        }
                        Row {
                            label: "Opacity"
                            glyph: "\u{f05cc}"
                            desc: "Background alpha of the bar surfaces"
                            Slider {
                                from: 20; to: 100; step: 5
                                value: Number(ShellSettings.value("bar.opacity", 85))
                                onCommitted: v => ShellSettings.setValue("bar.opacity", v)
                            }
                        }
                        Row {
                            label: "Blur"
                            glyph: "\u{f00a3}"
                            desc: "Frost what sits behind the bar surfaces"
                            Toggle {
                                checked: ShellSettings.value("bar.blur", false) === true
                                onToggled: v => ShellSettings.setValue("bar.blur", v)
                            }
                        }
                        Row {
                            label: "Width"
                            glyph: "\u{f046b}"
                            desc: "Percent of the screen edge; never below the content. fill ignores it"
                            Slider {
                                from: 25; to: 100; step: 5
                                value: Number(ShellSettings.value("bar.width", 100))
                                onCommitted: v => ShellSettings.setValue("bar.width", v)
                            }
                        }
                        Row {
                            label: "Fit width"
                            glyph: "\u{f084c}"
                            desc: "Bar hugs its content — no dead space; Width is ignored"
                            Toggle {
                                checked: ShellSettings.value("bar.fitWidth", false) === true
                                onToggled: v => ShellSettings.setValue("bar.fitWidth", v)
                            }
                        }
                        Row {
                            label: "Distinct pills"
                            glyph: "\u{f0409}"
                            desc: "Keep the segmented tint on solid and fill"
                            Toggle {
                                checked: ShellSettings.value("bar.distinctPills", false) === true
                                onToggled: v => ShellSettings.setValue("bar.distinctPills", v)
                            }
                        }
                        Row {
                            label: "Autohide"
                            glyph: "\u{f0209}"
                            desc: "Bar slides away; hover the screen edge to reveal"
                            Toggle {
                                checked: ShellSettings.value("bar.autohide", false) === true
                                onToggled: v => ShellSettings.setValue("bar.autohide", v)
                            }
                        }
                        Row {
                            label: "Autohide delay"
                            glyph: "\u{f051f}"
                            desc: "How long the bar lingers, in milliseconds"
                            Slider {
                                from: 0; to: 3000; step: 100
                                value: Number(ShellSettings.value("bar.autohideTimeout", 1000))
                                onCommitted: v => ShellSettings.setValue("bar.autohideTimeout", v)
                            }
                        }
                        Row {
                            label: "Workspaces"
                            glyph: "\u{f0570}"
                            desc: "KDE's virtual desktops, added or removed at the end over D-Bus; the pips follow"
                            Stepper {
                                from: 1; to: 20
                                value: window.desktopCount
                                onCommitted: v => window.setDesktops(v)
                            }
                        }
                        Row {
                            label: "Workspace style"
                            glyph: "\u{f0139}"
                            desc: "pills are v2's; glyphs puts an icon on each desktop; shapes rolls a Material shape per focus"
                            Chips {
                                options: ["pills", "dots", "squares", "numbers", "glyphs", "shapes", "underline", "pacman"]
                                current: "" + ShellSettings.value("bar.workspaces.style", "pills")
                                onPicked: v => ShellSettings.setValue("bar.workspaces.style", v)
                            }
                        }
                        Row {
                            label: "Workspace glyphs"
                            glyph: "\u{f0832}"
                            visible: ShellSettings.value("bar.workspaces.style", "pills") === "glyphs"
                            desc: "Click a desktop to pick its icon. # shows the number instead"
                            ColumnLayout {
                                spacing: window.s(8)
                                GlyphSlots {
                                    Layout.preferredWidth: window.s(360)
                                    width: window.s(360)
                                    count: window.desktopCount > 0 ? window.desktopCount : window.defaultGlyphs.length
                                    glyphs: window.wsGlyphs
                                    onPicked: (i, g) => window.setWsGlyph(i, g)
                                }
                                Btn {
                                    Layout.alignment: Qt.AlignRight
                                    label: "Reset icons"
                                    onClicked: ShellSettings.setValue("bar.workspaces.glyphs", null)
                                }
                            }
                        }
                        Row {
                            label: "Active indicator"
                            glyph: "\u{f04fe}"
                            desc: "Sliding highlight (pills, numbers, glyphs) or bar (underline) behind the active one"
                            Toggle {
                                checked: ShellSettings.value("bar.workspaces.activeIndicator", true) !== false
                                onToggled: v => ShellSettings.setValue("bar.workspaces.activeIndicator", v)
                            }
                        }
                        Row {
                            label: "Occupied tint"
                            glyph: "\u{f0266}"
                            desc: "Occupied workspaces read differently from empty ones"
                            Toggle {
                                checked: ShellSettings.value("bar.workspaces.occupiedBg", true) !== false
                                onToggled: v => ShellSettings.setValue("bar.workspaces.occupiedBg", v)
                            }
                        }
                        Row {
                            label: "Tint colour"
                            glyph: "\u{f00e9}"
                            desc: "Palette roles, so it re-themes with the wallpaper"
                            Swatches {
                                width: window.s(300)
                                options: [
                                    { key: "text",     color: window.text },
                                    { key: "mauve",    color: window.mauve },
                                    { key: "sapphire", color: window.sapphire },
                                    { key: "green",    color: window.green },
                                    { key: "yellow",   color: window.yellow },
                                    { key: "peach",    color: window.peach },
                                    { key: "pink",     color: window.pink },
                                    { key: "red",      color: window.red }
                                ]
                                current: "" + ShellSettings.value("bar.workspaces.occupiedColor", "text")
                                onPicked: v => ShellSettings.setValue("bar.workspaces.occupiedColor", v)
                                enabled: ShellSettings.value("bar.workspaces.occupiedBg", true) !== false
                                opacity: enabled ? 1 : 0.4
                            }
                        }
                        Row {
                            label: "Media player"
                            glyph: "\u{f075a}"
                            desc: "mini is v2's compact player with a popout; side bars always use mini"
                            Chips {
                                options: ["full", "mini"]
                                current: "" + ShellSettings.value("bar.media.style", "full")
                                onPicked: v => ShellSettings.setValue("bar.media.style", v)
                            }
                        }
                        Row {
                            label: "Actions"
                            glyph: "\u{f12a8}"
                            desc: "Buttons in the Actions widget; with none picked it leaves the bar"
                            ToggleChips {
                                options: window.actionOptions
                                current: window.enabledActions
                                onChanged: v => ShellSettings.setValue("bar.actions", v)
                            }
                        }
                        Row {
                            label: "Make room for the panel"
                            glyph: "\u{f04e1}"
                            desc: "Centre and right sections slide left while the System Panel is open"
                            Toggle {
                                checked: ShellSettings.value("bar.packForPanel", false) === true
                                onToggled: v => ShellSettings.setValue("bar.packForPanel", v)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: window.s(8)
                            text: "Layout"
                            font.family: window.fontFamily
                            font.pixelSize: window.s(12)
                            color: window.text
                        }
                        BarArranger {
                            Layout.fillWidth: true
                            host: window
                        }
                    }

                    // Tray
                    Page {
                        title: "Tray"
                        Row {
                            label: "Icon overrides"
                            desc: "Type a Nerd Font glyph to replace an app's tray icon; empty keeps its own. "
                                + "The colour is a palette role, so it follows the theme. Saved to tray-icons.json"
                            glyph: "\u{f129e}"
                        }

                        Repeater {
                            model: window.trayRows
                            delegate: Row {
                                required property var modelData
                                label: modelData.title || modelData.key
                                desc: modelData.running ? modelData.key : modelData.key + "  •  not running"
                                glyph: "\u{f003b}"
                                opacity: modelData.running ? 1 : 0.6

                                RowLayout {
                                    spacing: window.s(10)

                                    // Previewed in its override colour, so the field is its own swatch.
                                    Item {
                                        Layout.preferredWidth: window.s(24)
                                        Layout.preferredHeight: window.s(20)
                                        Text {
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: window.glyphNudge(modelData.glyph, window.s(15))
                                            text: modelData.glyph || "—"
                                            font.family: window.glyphFamily
                                            font.pixelSize: window.s(15)
                                            color: modelData.glyph ? window.tintOf(modelData.color) : window.overlay0
                                        }
                                    }
                                    PathField {
                                        implicitWidth: window.s(96)
                                        placeholder: "glyph"
                                        value: modelData.glyph
                                        onCommitted: v => TrayOverrides.setEntry(modelData.key, v, modelData.color)
                                    }
                                    TintPick {
                                        visible: modelData.glyph !== ""
                                        options: window.trayTints
                                        current: modelData.color
                                        onPicked: v => TrayOverrides.setEntry(modelData.key, modelData.glyph, v)
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: window.trayRows.length === 0
                            text: "No tray items and no overrides yet."
                            font.family: window.fontFamily
                            font.pixelSize: window.s(10)
                            color: window.overlay0
                        }
                    }

                    // Notifications
                    Page {
                        title: "Notifications"
                        Row {
                            label: "Position"
                            glyph: "\u{f009a}"
                            desc: "Where toasts stack, clear of the bar; bottom presets grow upward"
                            Chips {
                                width: window.s(430)
                                options: ["top left", "top center", "top right",
                                          "bottom left", "bottom center", "bottom right", "custom"]
                                current: "" + ShellSettings.value("notifications.position", "top right")
                                onPicked: v => ShellSettings.setValue("notifications.position", v)
                            }
                        }
                        Row {
                            visible: ShellSettings.value("notifications.position", "top right") === "custom"
                            label: "Custom position"
                            glyph: "\u{f01a3}"
                            desc: "Percent across, then down the screen"
                            RowLayout {
                                spacing: window.s(12)
                                Slider {
                                    from: 0; to: 100; step: 1
                                    value: Number(ShellSettings.value("notifications.horizontalPosition", 95))
                                    onCommitted: v => ShellSettings.setValue("notifications.horizontalPosition", v)
                                }
                                Slider {
                                    from: 0; to: 100; step: 1
                                    value: Number(ShellSettings.value("notifications.verticalPosition", 5))
                                    onCommitted: v => ShellSettings.setValue("notifications.verticalPosition", v)
                                }
                            }
                        }
                        Row {
                            label: "Do not disturb"
                            glyph: "\u{f009c}"
                            desc: DndState.enabled && DndState.until > 0
                                ? "Silenced for " + Math.ceil(DndState.remainingSecs / 60) + " min more"
                                : "Toasts stay quiet, critical ones still show. Kept out of settings.json"
                            Toggle {
                                checked: DndState.enabled
                                onToggled: v => { if (v) DndState.enable(); else DndState.disable(); }
                            }
                        }
                        Row {
                            label: "Empty graphic"
                            glyph: "\u{f02e9}"
                            desc: "Animated mascot in the panel when there is nothing to show"
                            Toggle {
                                checked: ShellSettings.value("notifications.showEmptyGraphic", true) !== false
                                onToggled: v => ShellSettings.setValue("notifications.showEmptyGraphic", v)
                            }
                        }
                        Row {
                            label: "Test"
                            glyph: "\u{f048a}"
                            desc: "Sent over the bus like any app's. The action one lingers until dismissed"
                            RowLayout {
                                spacing: window.s(8)
                                Btn {
                                    label: "Send test"
                                    onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "dialog-information",
                                                                        "Test notification", "Lands at the chosen preset."])
                                }
                                Btn {
                                    label: "With action"
                                    onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "dialog-information",
                                                                        "-A", "open=Open", "Test with action", "Expand the card for the button."])
                                }
                                Btn {
                                    label: "Critical"
                                    onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "critical", "-i", "dialog-warning",
                                                                        "Critical test", "Stays until dismissed, even under Do not disturb."])
                                }
                            }
                        }
                    }

                    // Launcher
                    Page {
                        title: "Launcher"
                        Row {
                            label: "Position"
                            glyph: "\u{f0463}"
                            desc: "follow sits flush against the bar; center grows out of the search field"
                            Chips {
                                options: ["follow", "top", "bottom", "left", "right", "center"]
                                current: "" + ShellSettings.value("launcher.position", "follow")
                                onPicked: v => ShellSettings.setValue("launcher.position", v)
                            }
                        }
                        Row {
                            label: "Width"
                            glyph: "\u{f046b}"
                            desc: "Pixels, before interface scale"
                            Slider {
                                from: 320; to: 1400; step: 10
                                value: Number(ShellSettings.value("launcher.width", 600))
                                onCommitted: v => ShellSettings.setValue("launcher.width", v)
                            }
                        }
                        Row {
                            label: "Visible items"
                            glyph: "\u{f0279}"
                            desc: "Rows shown before the list scrolls"
                            Stepper {
                                from: 3; to: 15
                                value: Number(ShellSettings.value("launcher.itemCount", 6))
                                onCommitted: v => ShellSettings.setValue("launcher.itemCount", v)
                            }
                        }
                        Row {
                            label: "Clipboard position"
                            glyph: "\u{f018f}"
                            desc: "opposite sits across from the bar, clear of the launcher"
                            Chips {
                                options: ["opposite", "top", "bottom", "left", "right"]
                                current: "" + ShellSettings.value("clipboard.position", "opposite")
                                onPicked: v => ShellSettings.setValue("clipboard.position", v)
                            }
                        }
                    }

                    // Dock
                    Page {
                        title: "Dock"
                        Row {
                            label: "Position"
                            glyph: "\u{f03ca}"
                            desc: "Screen edge the dock is grounded on. On the bar's edge it draws over the bar"
                            Chips {
                                options: ["bottom", "top", "left", "right"]
                                current: "" + ShellSettings.value("dock.position", "bottom")
                                onPicked: v => ShellSettings.setValue("dock.position", v)
                            }
                        }
                        Row {
                            label: "Frosted"
                            glyph: "\u{f00a3}"
                            desc: "Translucent island with the compositor blur behind it"
                            Toggle {
                                checked: ShellSettings.value("dock.frosted", false) === true
                                onToggled: v => ShellSettings.setValue("dock.frosted", v)
                            }
                        }
                        Row {
                            label: "Tinted icons"
                            glyph: "\u{f0301}"
                            desc: "Recolour app icons with the accent"
                            Toggle {
                                checked: ShellSettings.value("dock.tintIcons", false) === true
                                onToggled: v => ShellSettings.setValue("dock.tintIcons", v)
                            }
                        }
                        Row {
                            label: "Live thumbnails"
                            glyph: "\u{f0379}"
                            desc: "Stream window previews through KWin; needs the screencast grant (extra/README.md)"
                            Toggle {
                                checked: ShellSettings.value("dock.thumbnails", false) === true
                                onToggled: v => ShellSettings.setValue("dock.thumbnails", v)
                            }
                        }
                        Row {
                            label: "Disable auto-hide"
                            glyph: "\u{f0403}"
                            desc: "Keep the dock on screen"
                            Toggle {
                                checked: ShellSettings.value("dock.autoHide", false) !== true
                                onToggled: v => ShellSettings.setValue("dock.autoHide", !v)
                            }
                        }
                        Row {
                            label: "Auto-hide delay"
                            glyph: "\u{f051f}"
                            desc: "Seconds the dock stays after the pointer leaves"
                            Stepper {
                                from: 1; to: 30
                                value: Number(ShellSettings.value("dock.hideDelay", 5)) || 5
                                enabled: ShellSettings.value("dock.autoHide", false) === true
                                opacity: enabled ? 1 : 0.4
                                onCommitted: v => ShellSettings.setValue("dock.hideDelay", v)
                            }
                        }
                    }

                    // Wallpaper
                    Page {
                        title: "Wallpaper"
                        Row {
                            label: "Images"
                            glyph: "\u{f024f}"
                            desc: ""
                            PathField {
                                value: "" + ShellSettings.value("wallpaper.imageDir", "~/Pictures/Wallpapers")
                                onCommitted: v => ShellSettings.setValue("wallpaper.imageDir", v)
                            }
                        }
                        Row {
                            label: "Videos"
                            glyph: "\u{f0567}"
                            desc: "Told apart by extension, not folder"
                            PathField {
                                value: "" + ShellSettings.value("wallpaper.videoDir", "~/Pictures/Wallpapers")
                                onCommitted: v => ShellSettings.setValue("wallpaper.videoDir", v)
                            }
                        }
                        Row {
                            label: "Hand card size"
                            glyph: "\u{f0831}"
                            desc: "Percent of the default card size in the card-hand picker"
                            Slider {
                                from: 50; to: 200; step: 10
                                value: Number(ShellSettings.value("wallpaper.hand.cardSize", 100)) || 100
                                onCommitted: v => ShellSettings.setValue("wallpaper.hand.cardSize", Math.round(v))
                            }
                        }
                        Row {
                            label: "Wall columns"
                            glyph: "\u{f0831}"
                            desc: "Cards per row in the wall picker"
                            Stepper {
                                from: 3; to: 8
                                value: Number(ShellSettings.value("wallpaper.wall.columns", 5)) || 5
                                onCommitted: v => ShellSettings.setValue("wallpaper.wall.columns", v)
                            }
                        }
                        Row {
                            label: "Preview: transition"
                            glyph: "\u{f0831}"
                            desc: "Name the transition playing in the Space preview"
                            Toggle {
                                checked: ShellSettings.value("wallpaper.preview.shader", true) !== false
                                onToggled: v => ShellSettings.setValue("wallpaper.preview.shader", v)
                            }
                        }
                        Row {
                            label: "Preview: file name"
                            glyph: "\u{f0831}"
                            desc: "Show the wallpaper's file name in the preview"
                            Toggle {
                                checked: ShellSettings.value("wallpaper.preview.name", true) !== false
                                onToggled: v => ShellSettings.setValue("wallpaper.preview.name", v)
                            }
                        }
                        Row {
                            label: "Preview: colours"
                            glyph: "\u{f0831}"
                            desc: "Five dominant colours, extracted once per wallpaper"
                            Toggle {
                                checked: ShellSettings.value("wallpaper.preview.colors", true) !== false
                                onToggled: v => ShellSettings.setValue("wallpaper.preview.colors", v)
                            }
                        }
                        Row {
                            label: "Wallhaven downloads"
                            glyph: "\u{f024d}"
                            desc: "Empty follows Images, so downloads show up in the local tabs"
                            PathField {
                                placeholder: "Same as Images"
                                value: "" + ShellSettings.value("wallpaper.wallhaven.dir", "")
                                onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.dir", v)
                            }
                        }
                        Row {
                            label: "Apply on download"
                            glyph: "\u{f1a00}"
                            desc: "Set a wallhaven download as the wallpaper the moment it lands"
                            Toggle {
                                checked: ShellSettings.value("wallpaper.wallhaven.applyOnDownload", false) === true
                                onToggled: v => ShellSettings.setValue("wallpaper.wallhaven.applyOnDownload", v)
                            }
                        }
                        Row {
                            label: "Wallhaven tiles per row"
                            glyph: "\u{f11d9}"
                            desc: "Columns in the picker's Wallhaven tab"
                            Stepper {
                                from: 3; to: 10
                                value: Number(ShellSettings.value("wallpaper.wallhaven.columns", 5))
                                onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.columns", v)
                            }
                        }
                        Row {
                            label: "Wallhaven API key"
                            glyph: "\u{f0306}"
                            desc: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                                ? "Set. Unlocks NSFW results; type a new one to replace it."
                                : "Optional, only for NSFW results."
                            Item {
                                implicitWidth: whKeyField.implicitWidth + whClearKey.implicitWidth + window.s(10)
                                implicitHeight: whKeyField.implicitHeight

                                SecretField {
                                    id: whKeyField
                                    anchors.verticalCenter: parent.verticalCenter
                                    placeholder: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                                        ? "••••••••  press Enter to replace" : "paste key, press Enter"
                                    onCommitted: v => ShellSettings.setValue("wallpaper.wallhaven.apiKey", ("" + v).trim())
                                }
                                Btn {
                                    id: whClearKey
                                    anchors.left: whKeyField.right
                                    anchors.leftMargin: window.s(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Clear"
                                    visible: ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                                    onClicked: ShellSettings.setValue("wallpaper.wallhaven.apiKey", "")
                                }
                            }
                        }
                    }

                    // Music
                    Page {
                        title: "Music"
                        Row {
                            label: "Lyrics highlight"
                            glyph: "\u{f0370}"
                            desc: "sing-along lights each word when the track has word timings, lines otherwise"
                            Chips {
                                options: ["lines", "sing-along"]
                                current: "" + ShellSettings.value("lyrics.highlight", "sing-along")
                                onPicked: v => ShellSettings.setValue("lyrics.highlight", v)
                            }
                        }
                    }

                    // Calendar
                    Page {
                        title: "Calendar"
                        Row {
                            label: "Week starts"
                            glyph: "\u{f00ed}"
                            desc: "Locale follows your system"
                            Chips {
                                options: ["locale", "sunday", "monday"]
                                current: "" + ShellSettings.value("calendar.weekStart", "locale")
                                onPicked: v => ShellSettings.setValue("calendar.weekStart", v)
                            }
                        }
                        Row {
                            label: "Astronomical events"
                            glyph: "\u{f0594}"
                            desc: "Solstices, equinoxes and the four moon phases, beside the holidays"
                            Toggle {
                                checked: ShellSettings.value("calendar.astro", false) === true
                                onToggled: v => ShellSettings.setValue("calendar.astro", v)
                            }
                        }
                    }

                    // Weather
                    Page {
                        title: "Weather"
                        Row {
                            label: "City ID"
                            glyph: "\u{f0146}"
                            desc: "OpenWeather numeric id, from openweathermap.org/city"
                            PathField {
                                implicitWidth: window.s(180)
                                value: "" + ShellSettings.value("weather.cityId", "")
                                onCommitted: v => ShellSettings.setValue("weather.cityId", v)
                            }
                        }
                        Row {
                            label: "Units"
                            glyph: "\u{f050f}"
                            desc: "metric °C, imperial °F, standard K"
                            Chips {
                                options: ["metric", "imperial", "standard"]
                                current: "" + ShellSettings.value("weather.unit", "metric")
                                onPicked: v => ShellSettings.setValue("weather.unit", v)
                            }
                        }
                        Row {
                            label: "API key"
                            glyph: "\u{f0306}"
                            desc: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
                                ? "Set. Type a new one to replace it."
                                : "Not set. openweathermap.org gives you one free."
                            Item {
                                implicitWidth: keyField.implicitWidth + clearKey.implicitWidth + window.s(10)
                                implicitHeight: keyField.implicitHeight

                                SecretField {
                                    id: keyField
                                    anchors.verticalCenter: parent.verticalCenter
                                    placeholder: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
                                        ? "••••••••  press Enter to replace" : "paste key, press Enter"
                                    onCommitted: v => ShellSettings.setValue("weather.apiKey", ("" + v).trim())
                                }
                                Btn {
                                    id: clearKey
                                    anchors.left: keyField.right
                                    anchors.leftMargin: window.s(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Clear"
                                    visible: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
                                    onClicked: ShellSettings.setValue("weather.apiKey", "")
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Stored in settings.json. helpers/.env still works as a fallback for all three."
                            font.family: window.fontFamily
                            font.pixelSize: window.s(9)
                            color: window.overlay0
                            wrapMode: Text.Wrap
                        }
                    }

                    // Network
                    Page {
                        title: "Network"
                        Row {
                            label: "Docker containers"
                            glyph: "\u{f0868}"
                            desc: "Shown in the Servers tab with the ports they publish. Off skips Docker altogether"
                            Toggle {
                                checked: ShellSettings.value("servers.docker", true) !== false
                                onToggled: v => ShellSettings.setValue("servers.docker", v)
                            }
                        }
                        Row {
                            label: "Services"
                            glyph: "\u{f048b}"
                            desc: "systemd units the Servers tab watches and can stop. A port is only "
                                + "needed when it cannot be read off the listening socket"
                        }

                        Repeater {
                            model: window.serverUnits
                            delegate: Row {
                                id: unitRow
                                required property string modelData
                                readonly property string unit: window.serverUnit(modelData)
                                readonly property bool privileged: window.serverKind(modelData) === "system"
                                label: unitRow.unit
                                glyph: unitRow.privileged ? "\u{f099d}" : "\u{f0004}"
                                desc: unitRow.privileged
                                    ? "system unit  •  stopping it asks for authentication"
                                    : "user unit"

                                RowLayout {
                                    spacing: window.s(10)
                                    PathField {
                                        id: portField
                                        implicitWidth: window.s(96)
                                        placeholder: "port"
                                        value: window.serverPort(unitRow.unit)
                                        onCommitted: v => portField.reset(window.setServerPort(unitRow.unit, v))
                                    }
                                    Btn {
                                        label: "Remove"
                                        onClicked: window.dropServer(unitRow.modelData)
                                    }
                                }
                            }
                        }

                        Row {
                            id: addUnit
                            property string kind: "user"
                            label: "Add a service"
                            glyph: "\u{f0415}"
                            desc: "Name it as systemd does; .service is assumed. A user unit stops without "
                                + "a prompt, a system one asks polkit"
                            RowLayout {
                                spacing: window.s(10)
                                Chips {
                                    options: ["user", "system"]
                                    current: addUnit.kind
                                    onPicked: v => addUnit.kind = v
                                }
                                PathField {
                                    id: unitDraft
                                    implicitWidth: window.s(200)
                                    placeholder: "jellyfin.service"
                                    // Enter or a click away adds it; the field clears either way.
                                    onCommitted: v => {
                                        window.addServer(addUnit.kind, v);
                                        unitDraft.reset("");
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Stored in settings.json. Containers and the listening ports the shell "
                                + "recognises need no entry here."
                            font.family: window.fontFamily
                            font.pixelSize: window.s(9)
                            color: window.overlay0
                            wrapMode: Text.Wrap
                        }
                    }

                    // System
                    Page {
                        title: "System"
                        Row {
                            label: "Polkit agent"
                            glyph: "\u{f0498}"
                            desc: "This shell answers authentication prompts with its own dialog. Registers as "
                                + "soon as it is on, provided KDE's agent below is masked"
                            Toggle {
                                checked: ShellSettings.value("polkit.enabled", false) === true
                                onToggled: v => ShellSettings.setValue("polkit.enabled", v)
                            }
                        }
                        Row {
                            label: "KDE's polkit agent"
                            glyph: "\u{f0582}"
                            desc: window.kdeAgentState === "masked"
                                ? "Masked, so this shell's agent can register. Unmask to hand prompts back to KDE"
                                : (window.kdeAgentState === "" ? "Checking the user unit…"
                                   : "Active (" + window.kdeAgentState + "). Polkit allows one agent per session, "
                                     + "so mask it to let this shell's agent take over")
                            RowLayout {
                                spacing: window.s(8)
                                Btn {
                                    label: "Mask"
                                    enabled: window.kdeAgentState !== "masked"
                                    opacity: enabled ? 1 : 0.4
                                    onClicked: window.kdeAgent(true)
                                }
                                Btn {
                                    label: "Unmask"
                                    enabled: window.kdeAgentState === "masked"
                                    opacity: enabled ? 1 : 0.4
                                    onClicked: window.kdeAgent(false)
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // --- building blocks (serpantinum v2's guide look on the same page API) ---

    component NavItem : Rectangle {
        id: nav
        property string label
        property string glyph
        property bool active: false
        property int slot: 0
        property string hint: ""
        signal picked()

        implicitHeight: window.s(44)
        radius: Radius.outer(window.s(8))
        color: navMa.containsMouse && !nav.active ? Qt.alpha(window.surface1, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: navMa.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
        opacity: window.tabOpacity(nav.slot)
        transform: Translate { x: window.s(-24) * (1.0 - window.tabProgress(nav.slot)) }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: window.s(10) + (nav.active ? window.s(4) : 0)
            anchors.rightMargin: window.s(14)
            spacing: window.s(10)
            Behavior on anchors.leftMargin { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

            V2.IconButton {
                enabled: false
                size: window.s(32)
                Layout.preferredWidth: window.s(32)
                Layout.preferredHeight: window.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: Radius.outer(window.s(8))
                buttonIcon: nav.glyph
                centerInk: true
                iconFontSize: window.s(16)
                accentColor: window.surface0
                textColor: window.text
            }
            Text {
                Layout.fillWidth: true
                text: nav.label
                font.family: window.fontFamily
                font.weight: nav.active ? Font.Bold : Font.Medium
                font.pixelSize: window.s(13)
                color: nav.active ? window.crust : (navMa.containsMouse ? window.text : window.subtext0)
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                visible: nav.hint !== ""
                text: nav.hint
                font.family: window.fontFamily
                font.pixelSize: window.s(10)
                color: window.overlay0
            }
        }
        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.picked()
        }
    }

    component Page : ColumnLayout {
        property string title
        default property alias content: body.data
        spacing: 0

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight
            interactive: contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: window.s(6)
            }
        }
    }

    component Row : Rectangle {
        id: row
        property string label
        property string desc
        property string glyph: ""
        default property alias content: holder.data

        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + window.s(24)
        radius: Radius.outer(window.s(8))
        color: Qt.alpha(window.surface0, 0.4)

        RowLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: window.s(14)
            anchors.rightMargin: window.s(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: window.s(12)

            V2.IconButton {
                visible: row.glyph !== ""
                enabled: false
                size: window.s(32)
                Layout.preferredWidth: window.s(32)
                Layout.preferredHeight: window.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: Radius.outer(window.s(8))
                buttonIcon: row.glyph
                centerInk: true
                iconFontSize: window.s(16)
                accentColor: window.surface0
                textColor: window.text
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: window.s(2)
                Text {
                    Layout.fillWidth: true
                    text: row.label
                    font.family: window.fontFamily
                    font.pixelSize: window.s(13)
                    color: window.text
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: row.desc
                    visible: row.desc !== ""
                    font.family: window.fontFamily
                    font.pixelSize: window.s(11)
                    color: window.subtext0
                    wrapMode: Text.Wrap
                }
            }
            Item {
                id: holder
                Layout.preferredWidth: childrenRect.width
                Layout.preferredHeight: childrenRect.height
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
        }
    }

    component Toggle : Item {
        id: tg
        property bool checked: false
        signal toggled(bool value)
        implicitWidth: tgInner.implicitWidth
        implicitHeight: tgInner.implicitHeight
        // v2's Toggle flips its own `checked` on click, which would sever the binding above.
        onCheckedChanged: tgInner.checked = tg.checked

        V2.Toggle {
            id: tgInner
            checked: tg.checked
            accentColor: window.accent
            baseColor: window.surface1
            handleColor: window.crust
            handleOffColor: window.text
            onToggled: c => tg.toggled(c)
        }
    }

    component Swatches : Flow {
        id: swf
        property var options: []      // [{ key, color }]
        property string current: ""
        property bool enabled: true
        property bool compact: false
        signal picked(string value)

        spacing: window.s(compact ? 5 : 7)

        // Hoisted: `window` does not resolve inside the delegate, only out here.
        readonly property real cell: window.s(compact ? 20 : 26)
        readonly property real ring: window.s(2)
        readonly property real pad: window.s(4)
        readonly property color ringOn: window.text
        readonly property color ringOff: Qt.alpha(window.surface2, 0.8)

        Repeater {
            model: swf.options
            delegate: Item {
                required property var modelData
                readonly property bool active: modelData.key === swf.current
                width: swf.cell
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: parent.active ? swf.ring : 1
                    border.color: parent.active ? swf.ringOn : swf.ringOff
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - (parent.active ? 2 * swf.pad : swf.pad)
                    height: width
                    radius: width / 2
                    color: parent.modelData.color
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: swf.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: swf.picked(parent.modelData.key)
                }
            }
        }
    }

    // Up to four options: v2's segmented Switch; more: its Dropdown. Same API either way.
    component Chips : Item {
        id: ch
        property var options: []
        property string current: ""
        property bool enabled: true
        signal picked(string value)

        readonly property int sel: options.indexOf(current)
        readonly property bool compact: options.length <= 4
        implicitWidth: pick.item ? pick.item.implicitWidth : 0
        implicitHeight: pick.item ? pick.item.implicitHeight : 0
        opacity: enabled ? 1 : 0.4

        // Hoisted for the components below, where `window` may not resolve.
        readonly property color cAccent: window.accent
        readonly property color cBase: window.surface0
        readonly property color cHover: window.surface1
        readonly property color cBorder: Qt.alpha(window.surface2, 0.6)
        readonly property color cText: window.text
        readonly property color cSub: window.subtext0
        readonly property color cOn: window.crust
        readonly property real cRadius: Radius.outer(window.s(8))
        readonly property real cFont: window.s(11)
        readonly property real cH: window.s(32)
        readonly property real segW: window.s(Math.max(120, 58 * options.length))
        property real dropW: window.s(220)

        Loader {
            id: pick
            sourceComponent: ch.compact ? seg : drop
        }
        Component {
            id: seg
            V2.Switch {
                id: sw
                implicitWidth: ch.segW
                implicitHeight: ch.cH
                options: ch.options
                currentIndex: Math.max(0, ch.sel)
                enabled: ch.enabled
                accentColor: ch.cAccent
                baseColor: ch.cBase
                textColor: ch.cSub
                activeTextColor: ch.cOn
                cornerRadius: ch.cRadius
                fontPixelSize: ch.cFont
                onToggled: i => ch.picked(ch.options[i])
                Connections { target: ch; function onSelChanged() { sw.currentIndex = Math.max(0, ch.sel) } }
            }
        }
        Component {
            id: drop
            V2.Dropdown {
                id: dd
                implicitWidth: ch.dropW
                implicitHeight: ch.cH
                options: ch.options
                currentIndex: ch.sel
                placeholderText: "—"
                enabled: ch.enabled
                accentColor: ch.cAccent
                baseColor: ch.cBase
                hoverColor: ch.cHover
                dropdownColor: ch.cBase
                borderColor: ch.cBorder
                textColor: ch.cText
                activeTextColor: ch.cOn
                cornerRadius: ch.cRadius
                fontPixelSize: ch.cFont
                onValueChanged: (i, v) => ch.picked(v)
                Connections { target: ch; function onSelChanged() { dd.currentIndex = ch.sel } }
            }
        }
    }

    component Stepper : Item {
        id: st
        property int from: 0
        property int to: 99
        property int value: 0
        signal committed(int v)
        implicitWidth: window.s(120)
        implicitHeight: window.s(32)
        onValueChanged: num.value = st.value

        V2.NumberSelector {
            id: num
            anchors.fill: parent
            from: st.from
            to: st.to
            stepSize: 1
            decimals: 0
            value: st.value
            enabled: st.enabled
            baseColor: window.surface0
            accentColor: window.accent
            buttonColor: window.surface1
            buttonTextColor: window.text
            textColor: window.text
            subTextColor: window.subtext0
            borderColor: Qt.alpha(window.surface2, 0.6)
            cornerRadius: Radius.outer(window.s(8))
            fontFamily: window.fontFamily
            fontPixelSize: window.s(11)
            onTriggered: { var v = Math.round(num.value); if (v !== st.value) st.committed(v); }
        }
    }

    component Slider : Item {
        id: sl
        property real from: 0
        property real to: 1
        property real step: 0.05
        property real value: 0
        signal committed(real v)
        implicitWidth: window.s(180)
        implicitHeight: window.s(18)

        // The handle shows what was dropped until settings.json catches up, or it snaps back.
        property real pending: NaN
        readonly property real shown: isNaN(sl.pending) ? sl.value : sl.pending
        onValueChanged: sl.pending = NaN      // the file has caught up (or someone else wrote it)
        function snap(v) { return Math.round((sl.from + Math.round((v - sl.from) / sl.step) * sl.step) * 1000) / 1000; }
        function push(v) {
            var x = sl.snap(v);
            if (x === sl.shown) return;
            sl.pending = x;
            sl.committed(x);
        }

        V2.Draggable {
            id: drag
            anchors.fill: parent
            from: sl.from
            to: sl.to
            stepSize: sl.step
            value: sl.shown
            showValueBubble: true
            valueFormatter: v => sl.step >= 1 ? Math.round(v).toString() : Number(v).toFixed(2)
            backgroundColor: window.surface0
            accentColor: window.accent
            handleColor: window.text
            handleBorderColor: window.mantle
            onMoved: v => sl.push(v)
            onDragFinished: sl.push(drag.dragPreview)
        }
    }

    // The current tint as a circle; the palette's circles drop down from it.
    component TintPick : Item {
        id: tp
        property var options: []      // [{ key, color }]
        property string current: ""
        signal picked(string value)
        implicitWidth: window.s(44)
        implicitHeight: window.s(32)

        readonly property real cell: window.s(26)
        readonly property real gap: window.s(7)
        function colorOf(k) {
            for (var i = 0; i < options.length; i++) if (options[i].key === k) return options[i].color;
            return window.overlay0;
        }

        Rectangle {
            anchors.fill: parent
            radius: Radius.outer(window.s(8))
            color: tpMa.containsMouse || pop.opened ? window.surface1 : window.surface0
            border.color: Qt.alpha(window.surface2, 0.6)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Rectangle {
                anchors.centerIn: parent
                width: window.s(16)
                height: width
                radius: width / 2
                color: tp.colorOf(tp.current)
            }
        }
        MouseArea {
            id: tpMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.opened ? pop.close() : pop.open()
        }
        Popup {
            id: pop
            y: tp.height + window.s(6)
            x: tp.width - width
            padding: window.s(8)
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            background: Rectangle {
                radius: Radius.outer(window.s(8))
                color: window.surface0
                border.color: Qt.alpha(window.surface2, 0.6)
                border.width: 1
            }
            contentItem: Item {
                implicitWidth: tp.options.length * (tp.cell + tp.gap) - tp.gap
                implicitHeight: tp.cell
                Swatches {
                    anchors.fill: parent
                    options: tp.options
                    current: tp.current
                    onPicked: v => { tp.picked(v); pop.close(); }
                }
            }
        }
    }

    // Multi-select chips: each option toggles in or out of the list, kept in option order.
    component ToggleChips : RowLayout {
        id: tc
        property var options: []      // [{ key, label, glyph }]
        property var current: []
        signal changed(var value)
        spacing: window.s(6)

        readonly property color cOn: window.accent
        readonly property color cOff: window.surface0
        readonly property color cTextOn: window.crust
        readonly property color cText: window.text
        readonly property real cRadius: Radius.outer(window.s(8))
        readonly property real cH: window.s(32)
        readonly property real cPad: window.s(12)
        readonly property real cFont: window.s(11)

        function flip(key) {
            var next = [];
            for (var i = 0; i < options.length; i++) {
                var k = options[i].key;
                var on = current.indexOf(k) !== -1;
                if (k === key) on = !on;
                if (on) next.push(k);
            }
            changed(next);
        }

        Repeater {
            model: tc.options
            delegate: V2.ClickButton {
                required property var modelData
                readonly property bool on: tc.current.indexOf(modelData.key) !== -1
                implicitHeight: tc.cH
                horizontalPadding: tc.cPad
                cornerRadius: tc.cRadius
                buttonText: modelData.label
                buttonIcon: modelData.glyph
                textFontSize: tc.cFont
                accentColor: on ? tc.cOn : tc.cOff
                textColor: on ? tc.cTextOn : tc.cText
                onClicked: tc.flip(modelData.key)
            }
        }
    }

    // ToggleChips that wrap, with a caption naming what the hovered app needs.
    component AppChips : ColumnLayout {
        id: ac
        property var options: []      // catalog apps: { key, label, glyph, packages, note }
        property var current: []
        property var hovered: null
        signal changed(var value)
        spacing: window.s(6)

        function flip(key) {
            var next = [];
            for (var i = 0; i < options.length; i++) {
                var k = options[i].key;
                var on = current.indexOf(k) !== -1;
                if (k === key) on = !on;
                if (on) next.push(k);
            }
            changed(next);
        }

        Flow {
            Layout.fillWidth: true
            spacing: window.s(6)
            Repeater {
                model: ac.options
                delegate: V2.ClickButton {
                    required property var modelData
                    readonly property bool on: ac.current.indexOf(modelData.key) !== -1
                    implicitHeight: window.s(32)
                    horizontalPadding: window.s(12)
                    cornerRadius: Radius.outer(window.s(8))
                    buttonText: modelData.label
                    buttonIcon: modelData.glyph || ""
                    textFontSize: window.s(11)
                    accentColor: on ? window.accent : window.surface0
                    textColor: on ? window.crust : window.text
                    onClicked: ac.flip(modelData.key)
                    onIsHoveredOrHighlightedChanged: {
                        if (isHoveredOrHighlighted) ac.hovered = modelData;
                        else if (ac.hovered && ac.hovered.key === modelData.key) ac.hovered = null;
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumHeight: window.s(30)
            text: {
                var a = ac.hovered;
                if (!a) return "Hover an app for the packages it needs and any manual step";
                var p = (a.packages || []).join(", ");
                return "Needs: " + (p || "nothing extra") + (a.note ? "\n" + a.note : "");
            }
            font.family: window.fontFamily
            font.pixelSize: window.s(11)
            color: window.subtext0
            wrapMode: Text.Wrap
        }
    }

    // One tile per desktop; clicking one drops a glyph grid, a paste field and #.
    component GlyphSlots : Flow {
        id: gs
        property int count: 10
        property var glyphs: []
        signal picked(int index, string glyph)
        spacing: window.s(6)

        readonly property real cell: window.s(38)
        readonly property real pickCell: window.s(32)
        readonly property int pickCols: 8
        readonly property color cBase: window.surface0
        readonly property color cHover: window.surface1
        readonly property color cBorder: Qt.alpha(window.surface2, 0.6)
        readonly property color cAccent: window.accent
        readonly property color cText: window.text
        readonly property color cSub: window.overlay0
        readonly property real cRadius: Radius.outer(window.s(8))
        readonly property string gFont: window.glyphFamily
        readonly property string tFont: window.fontFamily
        readonly property real gSize: window.s(18)
        readonly property real nSize: window.s(12)
        readonly property real tagSize: window.s(8)
        readonly property real tagPad: window.s(3)

        // console web code folder chat music gamepad image email cog, then more apps and moods.
        readonly property var library: [
            "\u{f018d}", "\u{f059f}", "\u{f0169}", "\u{f024b}", "\u{f0b79}", "\u{f075a}", "\u{f0297}", "\u{f02e9}",
            "\u{f01ee}", "\u{f0493}", "\u{f0239}", "\u{f02a4}", "\u{f14f7}", "\u{f082e}", "\u{f03d8}", "\u{f00e3}",
            "\u{f0567}", "\u{f02cb}", "\u{f04c7}", "\u{f04d3}", "\u{f066f}", "\u{f00ed}", "\u{f04ce}", "\u{f02d1}",
            "\u{f14de}", "\u{f0093}", "\u{f140b}", "\u{f0320}", "\u{f01a7}", "\u{f0431}", "\u{f02dc}", "\u{f00d6}",
            "\u{f0474}", "\u{f03eb}", "\u{f01bc}", "\u{f048b}", "\u{f015f}", "\u{f032a}", "\u{f0238}", "\u{f0176}"
        ]

        property int editing: -1
        function glyphAt(i) { return i < glyphs.length ? "" + glyphs[i] : ""; }
        function choose(g) { if (editing >= 0) picked(editing, g); pop.close(); }

        Repeater {
            model: gs.count
            delegate: Item {
                id: slot
                required property int index
                readonly property string g: gs.glyphAt(index)
                width: gs.cell
                height: gs.cell

                Rectangle {
                    anchors.fill: parent
                    radius: gs.cRadius
                    color: slotMa.containsMouse || gs.editing === slot.index && pop.opened ? gs.cHover : gs.cBase
                    border.width: gs.editing === slot.index && pop.opened ? 2 : 1
                    border.color: gs.editing === slot.index && pop.opened ? gs.cAccent : gs.cBorder
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: slot.g !== "" ? window.glyphNudge(slot.g, gs.gSize) : 0
                    text: slot.g !== "" ? slot.g : "" + (slot.index + 1)
                    font.family: slot.g !== "" ? gs.gFont : gs.tFont
                    font.pixelSize: slot.g !== "" ? gs.gSize : gs.nSize
                    color: gs.cText
                }
                Text {
                    visible: slot.g !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: gs.tagPad
                    text: "" + (slot.index + 1)
                    font.family: gs.tFont
                    font.pixelSize: gs.tagSize
                    color: gs.cSub
                }
                MouseArea {
                    id: slotMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        gs.editing = slot.index;
                        pop.x = slot.x;
                        pop.y = slot.y + slot.height + gs.spacing;
                        pop.open();
                    }
                }
            }
        }

        Popup {
            id: pop
            padding: window.s(8)
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            onClosed: gs.editing = -1
            background: Rectangle {
                radius: gs.cRadius
                color: gs.cBase
                border.color: gs.cBorder
                border.width: 1
            }
            contentItem: ColumnLayout {
                spacing: window.s(8)

                Grid {
                    columns: gs.pickCols
                    spacing: window.s(4)
                    Repeater {
                        model: gs.library
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isCurrent: gs.editing >= 0 && gs.glyphAt(gs.editing) === modelData
                            width: gs.pickCell
                            height: gs.pickCell
                            radius: gs.cRadius
                            color: isCurrent ? gs.cAccent : (pickMa.containsMouse ? gs.cHover : "transparent")
                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: window.glyphNudge(parent.modelData, gs.gSize)
                                text: parent.modelData
                                font.family: gs.gFont
                                font.pixelSize: gs.gSize
                                color: parent.isCurrent ? window.crust : gs.cText
                            }
                            MouseArea {
                                id: pickMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gs.choose(parent.modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(6)
                    PathField {
                        Layout.fillWidth: true
                        placeholder: "Paste any Nerd Font glyph"
                        value: gs.editing >= 0 ? gs.glyphAt(gs.editing) : ""
                        onCommitted: v => { if (v.trim() !== "") gs.choose(v.trim()); }
                    }
                    Btn {
                        label: "#"
                        onClicked: gs.choose("")
                    }
                }
            }
        }
    }

    // Masked, and clears itself on commit so a typed key never lingers on screen.
    component SecretField : Item {
        property string placeholder: ""
        signal committed(string v)
        implicitWidth: window.s(200)
        implicitHeight: window.s(32)
        PathField {
            anchors.fill: parent
            secret: true
            placeholder: parent.placeholder
            onCommitted: v => parent.committed(v)
        }
    }

    component Btn : V2.ClickButton {
        property string label: ""
        buttonText: label
        buttonIcon: ""
        implicitHeight: window.s(30)
        horizontalPadding: window.s(14)
        cornerRadius: Radius.outer(window.s(8))
        textFontSize: window.s(11)
        accentColor: window.surface1
        textColor: window.text
    }

    // Searchable list of installed families, each row drawn in its own font.
    component FontPicker : ColumnLayout {
        id: fp
        property string current: ""
        property string query: ""
        signal picked(string family)
        spacing: window.s(6)

        readonly property var families: {
            let seen = {};
            let out = [];
            let all = Qt.fontFamilies();
            for (let i = 0; i < all.length; i++) {
                if (!seen[all[i]]) { seen[all[i]] = true; out.push(all[i]); }
            }
            return out;
        }
        readonly property var matches: {
            let q = fp.query.trim().toLowerCase();
            return q === "" ? fp.families : fp.families.filter(f => f.toLowerCase().indexOf(q) !== -1);
        }

        V2.Input {
            Layout.preferredWidth: window.s(280)
            Layout.preferredHeight: window.s(32)
            placeholderText: "Search " + fp.families.length + " fonts"
            baseColor: window.surface0
            accentColor: window.accent
            textColor: window.text
            subTextColor: window.subtext0
            borderColor: Qt.alpha(window.surface2, 0.6)
            cornerRadius: Radius.outer(window.s(8))
            fontPixelSize: window.s(11)
            onTextEdited: t => fp.query = t
        }

        ListView {
            Layout.preferredWidth: window.s(280)
            Layout.preferredHeight: window.s(180)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: fp.matches
            delegate: Rectangle {
                required property string modelData
                readonly property bool isCurrent: modelData === fp.current
                width: ListView.view.width
                height: window.s(26)
                radius: Radius.outer(window.s(6))
                color: isCurrent ? Qt.alpha(window.accent, 0.18) : (rowMa.containsMouse ? window.surface2 : "transparent")
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: window.s(10)
                    anchors.rightMargin: window.s(10)
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: parent.modelData
                    font.family: parent.modelData
                    font.pixelSize: window.s(11)
                    color: parent.isCurrent ? window.accent : window.text
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fp.picked(parent.modelData)
                }
            }
        }
    }

    component PathField : Item {
        id: pf
        property string value: ""
        property string placeholder: ""
        property bool secret: false
        signal committed(string v)
        implicitWidth: window.s(220)
        implicitHeight: window.s(32)
        onValueChanged: inp.text = pf.value

        // For a committed handler that stored something other than what was typed: `value`
        // still lags behind the settings file, so it cannot clear the field on its own.
        function reset(text) { inp.text = text }

        // Enter commits; so does leaving the field, as a pasted key must survive a click away.
        function commit() {
            var t = inp.text;
            if (pf.secret) { if (t !== "") { pf.committed(t); inp.text = ""; } }
            else if (t !== pf.value) pf.committed(t);
        }

        V2.Input {
            id: inp
            anchors.fill: parent
            text: pf.value
            placeholderText: pf.placeholder
            masked: pf.secret
            baseColor: window.surface0
            accentColor: window.accent
            textColor: window.text
            subTextColor: window.subtext0
            borderColor: Qt.alpha(window.surface2, 0.6)
            cornerRadius: Radius.outer(window.s(8))
            fontPixelSize: window.s(11)
            onAccepted: pf.commit()
            onHasFocusChanged: if (!hasFocus) pf.commit()
        }
    }
}
