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
    // Installed tesseract packs, read once; empty when tesseract is missing.
    property var ocrLangs: []
    property bool ocrProbed: false
    readonly property var ocrLangOptions: window.ocrLangs.map(l => ({ key: l, label: l, glyph: "" }))
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
                window.ocrLangs = out;
                window.ocrProbed = true;
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

    // Deep link: SettingsState.section names a tab, matched case-insensitively.
    // A child tab only shows while its parent is the current page, or it is.
    function tabShown(i) {
        var t = window.tabs[i];
        if (!t || !t.under) return true;
        var cur = window.tabs[window.currentTab];
        // The whole group stays open while the parent or any sibling is current.
        return !!cur && (cur.name === t.under || cur.under === t.under);
    }
    function shownBefore(i) {
        var n = 0;
        for (var k = 0; k < i; k++) if (window.tabShown(k)) n++;
        return n;
    }
    function tabIsChild(i) {
        var t = window.tabs[i];
        return !!(t && t.under);
    }

    function tabIndexOf(name) {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].name.toLowerCase() === ("" + name).toLowerCase()) return i;
        return -1;
    }
    function syncSection() {
        var i = tabIndexOf(SettingsState.section);
        if (i >= 0) currentTab = i;
    }
    Component.onCompleted: { syncSection(); intro.start(); ocrLangProbe.running = true; }
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
        { name: "Modules",     icon: "\u{f12a8}", under: "Bar" },
        { name: "Tray",       icon: "\u{f0f1d}", under: "Bar" },
        { name: "Notifications", icon: "\u{f009a}" },
        { name: "Launcher",   icon: "\u{f0349}" },
        { name: "Dock",       icon: "\u{f10a9}" },
        { name: "On-Screen Display", icon: "\u{f057e}" },
        { name: "Wallpaper",  icon: "\u{f05e2}" },
        { name: "Capture",    icon: "\u{f0100}" },
        { name: "Text recognition", icon: "\u{f113d}", under: "Capture" },
        { name: "Recording",  icon: "\u{f0567}", under: "Capture" },
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
                        y: window.shownBefore(window.currentTab) * (window.s(44) + window.s(4))
                        x: window.tabIsChild(window.currentTab) ? window.s(16) : 0
                        width: tabsCol.width - x
                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
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
                                Layout.leftMargin: modelData.under ? window.s(16) : 0
                                visible: window.tabShown(index)
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
                        SettingsHeading { host: window; text: "Themes" }
                        ThemeGrid {
                            Layout.fillWidth: true
                            host: window
                        }
                        SettingsHeading { host: window; text: "Shell look" }
                        ThemeAppearanceSection {
                            Layout.fillWidth: true
                            host: window
                        }
                        SettingsHeading { host: window; text: "Colour generation" }
                        ThemeMatugenSection {
                            Layout.fillWidth: true
                            host: window
                        }
                        SettingsHeading { host: window; text: "Applications" }
                        ThemeAppsSection {
                            Layout.fillWidth: true
                            host: window
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
                        BarPlacementSection {
                            Layout.fillWidth: true
                            host: window
                        }
                        BarStyleSection {
                            Layout.fillWidth: true
                            host: window
                        }
                        BarAutohideSection {
                            Layout.fillWidth: true
                            host: window
                        }
                        BarLayoutSection {
                            Layout.fillWidth: true
                            host: window
                        }
                    }

                    // Bar modules
                    Page {
                        title: "Bar modules"
                        BarMenuCard { host: window }
                        BarWorkspacesCard { host: window }
                        BarTimeDateCard { host: window }
                        BarSysmonCard { host: window }
                        BarBatteryCard { host: window }
                        BarMediaCard { host: window }
                    }

                    // Tray
                    Page {
                        title: "Tray"
                        Row {
                            label: "Icon overrides"
                            desc: "The switch lifts an app out of the drawer and into the bar. Type a Nerd Font "
                                + "glyph to replace its icon; empty keeps its own. The colour is a palette role, "
                                + "so it follows the theme. Saved to tray-icons.json"
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
                                    Toggle {
                                        checked: modelData.pinned
                                        onToggled: v => TrayOverrides.setPinned(modelData.key, v)
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

                    // On-Screen Display
                    Page {
                        title: "On-Screen Display"
                        OsdSection {
                            Layout.fillWidth: true
                            host: window
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

                    // Capture
                    Page {
                        title: "Capture"
                        Row {
                            label: "Capture on release"
                            glyph: "\u{f0100}"
                            desc: "Take the shot as soon as the drag ends instead of a second click"
                            Toggle {
                                checked: ShellSettings.value("screenshot.captureOnRelease", false) === true
                                onToggled: v => ShellSettings.setValue("screenshot.captureOnRelease", v)
                            }
                        }
                        SettingsHeading { host: window; text: "Overlay keys" }
                        Row { label: "Tab, Left, Right"; glyph: "\u{f030c}"; desc: "Switch between screenshot and recording" }
                        Row { label: "Space, Return"; glyph: "\u{f030c}"; desc: "Take the shot, or start and stop the recording" }
                        Row { label: "F"; glyph: "\u{f030c}"; desc: "Whole screen; in video mode it records right away" }
                        Row { label: "T"; glyph: "\u{f030c}"; desc: "Recognise the text in the selection" }
                        Row { label: "F11"; glyph: "\u{f030c}"; desc: "Maximise the selection" }
                        Row { label: "Escape"; glyph: "\u{f030c}"; desc: "Close a result card, then the overlay" }
                    }

                    // Text recognition
                    Page {
                        title: "Text recognition"
                        Row {
                            label: "Languages"
                            glyph: "\u{f113d}"
                            desc: !window.ocrProbed ? "Looking for installed packs"
                                : window.ocrLangs.length === 0
                                ? "tesseract is not installed; packs are tesseract-data-<lang>"
                                : "Installed tesseract packs; tesseract-data-<lang> adds more"
                            ToggleChips {
                                options: window.ocrLangOptions
                                current: window.ocrLangsCurrent
                                onChanged: v => { if (v.length > 0) ShellSettings.setValue("screenshot.ocr.langs", v.join("+")) }
                            }
                        }
                        Row {
                            label: "Upscale before recognising"
                            glyph: "\u{f0a93}"
                            desc: "2x makes UI-sized text readable"
                            Chips {
                                options: ["1", "2", "3"]
                                current: "" + ShellSettings.value("screenshot.ocr.upscale", 2)
                                onPicked: v => ShellSettings.setValue("screenshot.ocr.upscale", Number(v))
                            }
                        }
                        Row {
                            label: "Copy text automatically"
                            glyph: "\u{f018f}"
                            desc: "Recognised text lands on the clipboard as soon as it arrives"
                            Toggle {
                                checked: ShellSettings.value("screenshot.ocr.autoCopy", true) !== false
                                onToggled: v => ShellSettings.setValue("screenshot.ocr.autoCopy", v)
                            }
                        }
                    }

                    // Recording
                    Page {
                        title: "Recording"
                        Row {
                            label: "HDR"
                            glyph: "\u{f0d7d}"
                            desc: "Keep HDR on HDR outputs (hevc_hdr, mkv); needs an HDR-aware player, mpv tonemaps it right. Off lets GSR tonemap to SDR, which plays anywhere"
                            Toggle {
                                checked: ShellSettings.value("record.hdr", true) !== false
                                onToggled: v => ShellSettings.setValue("record.hdr", v)
                            }
                        }
                        Row {
                            label: "Audio"
                            glyph: "\u{f057e}"
                            desc: "What the recording hears"
                            Chips {
                                options: ["off", "system", "system+mic"]
                                current: "" + ShellSettings.value("record.audio", "system")
                                onPicked: v => ShellSettings.setValue("record.audio", v)
                            }
                        }
                        Row {
                            label: "Frame rate"
                            glyph: "\u{f04c5}"
                            desc: "Maximum fps; variable pacing by default"
                            Chips {
                                options: ["30", "60", "120", "144"]
                                current: "" + ShellSettings.value("record.fps", 60)
                                onPicked: v => ShellSettings.setValue("record.fps", Number(v))
                            }
                        }
                        Row {
                            label: "Quality"
                            glyph: "\u{f0435}"
                            desc: "GSR quality preset"
                            Chips {
                                options: ["medium", "high", "very_high", "ultra"]
                                current: "" + ShellSettings.value("record.quality", "very_high")
                                onPicked: v => ShellSettings.setValue("record.quality", v)
                            }
                        }
                        Row {
                            label: "SDR codec"
                            glyph: "\u{f061a}"
                            desc: "Encoder for SDR files"
                            Chips {
                                options: ["h264", "hevc", "av1"]
                                current: "" + ShellSettings.value("record.codec", "h264")
                                onPicked: v => ShellSettings.setValue("record.codec", v)
                            }
                        }
                        Row {
                            label: "HDR codec"
                            glyph: "\u{f061a}"
                            desc: "Encoder for HDR files"
                            Chips {
                                options: ["hevc_hdr", "av1_hdr"]
                                current: "" + ShellSettings.value("record.hdrCodec", "hevc_hdr")
                                onPicked: v => ShellSettings.setValue("record.hdrCodec", v)
                            }
                        }
                        Row {
                            label: "Container"
                            glyph: "\u{f03d7}"
                            desc: "SDR files; HDR files use the HDR container"
                            Chips {
                                options: ["mp4", "mkv", "webm"]
                                current: "" + ShellSettings.value("record.container", "mp4")
                                onPicked: v => ShellSettings.setValue("record.container", v)
                            }
                        }
                        Row {
                            label: "HDR container"
                            glyph: "\u{f03d7}"
                            desc: "mkv carries the HDR metadata reliably"
                            Chips {
                                options: ["mkv", "mp4"]
                                current: "" + ShellSettings.value("record.hdrContainer", "mkv")
                                onPicked: v => ShellSettings.setValue("record.hdrContainer", v)
                            }
                        }
                        Row {
                            label: "Cursor"
                            glyph: "\u{f01c0}"
                            desc: "Include the pointer"
                            Toggle {
                                checked: ShellSettings.value("record.cursor", true) !== false
                                onToggled: v => ShellSettings.setValue("record.cursor", v)
                            }
                        }
                        Row {
                            label: "Frame pacing"
                            glyph: "\u{f07da}"
                            desc: "cfr for editors that dislike variable frame rate"
                            Chips {
                                options: ["vfr", "cfr"]
                                current: "" + ShellSettings.value("record.frameMode", "vfr")
                                onPicked: v => ShellSettings.setValue("record.frameMode", v)
                            }
                        }
                        Row {
                            label: "Colour range"
                            glyph: "\u{f0195}"
                            desc: "SDR only; HDR always records full range"
                            Chips {
                                options: ["limited", "full"]
                                current: "" + ShellSettings.value("record.colorRange", "limited")
                                onPicked: v => ShellSettings.setValue("record.colorRange", v)
                            }
                        }
                        Row {
                            label: "Save folder"
                            glyph: "\u{f024b}"
                            desc: "Screencast_<date>.<ext> lands here"
                            PathField {
                                value: "" + ShellSettings.value("record.dir", "~/Videos/Screencasts")
                                onCommitted: v => ShellSettings.setValue("record.dir", v)
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
                        Row {
                            label: "Lyrics size"
                            glyph: "\u{f0b64}"
                            desc: "Scales the lyric text; Ctrl+= and Ctrl+- do it from the popup, Ctrl+0 resets"
                            Slider {
                                from: 0.7; to: 2.0; step: 0.1
                                value: Number(ShellSettings.value("lyrics.scale", 1.0))
                                onCommitted: v => ShellSettings.setValue("lyrics.scale", v)
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

    component Row : SettingsRow { host: window }

    component Toggle : SettingsToggle { host: window }

    component Swatches : SettingsSwatches { host: window }

    component Chips : SettingsChips { host: window }

    component Stepper : SettingsStepper { host: window }

    component Slider : SettingsSlider { host: window }

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

    component ToggleChips : SettingsToggleChips { host: window }

    component AppChips : SettingsAppChips { host: window }

    component GlyphSlots : SettingsGlyphSlots { host: window }

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

    component Btn : SettingsBtn { host: window }

    component FontPicker : SettingsFontPicker { host: window }

    component PathField : SettingsPathField { host: window }
}
