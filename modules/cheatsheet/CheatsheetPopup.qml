// The user's real shortcuts, grouped into cards. Layout idea from end-4's
// dots-hyprland; KDE data from helpers/shortcuts.py, in-shell data from ShellShortcuts.js.

import "../../services/layout"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "ShellShortcuts.js" as ShellShortcuts

Item {
    id: window

    Scaler {
        id: scaler
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color accent: _theme.blue            // md3.primary, as everywhere else

    // --- Group tints --- SELECTED from matugen's palette, never generated. A matugen theme
    // often spans under 40 degrees of hue, so rotating one invents colours the shell never uses.
    readonly property var groupTints: [
        Colors.md3.primary,
        Colors.md3.tertiary,
        Colors.md3.secondary,
        Colors.palette.primary70,
        Colors.palette.tertiary70
    ]
    readonly property int tintCount: window.groupTints.length

    property int tabIndex: 0
    readonly property bool shellTab: window.tabIndex === 1

    // The in-shell catalogue is four times the KDE list, so its tab needs a wider sheet.
    readonly property real sheetWidth: Math.min(Screen.width * 0.95, s(window.shellTab ? 1700 : 1240))
    // Self-sizing: the sheet is exactly as tall as its tallest column, so a
    // group can never be clipped and there is never dead space to scroll.
    readonly property real sheetHeight: Math.min(Screen.height * 0.9, sheetBody.implicitHeight + s(48))

    width: window.sheetWidth
    height: window.sheetHeight

    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    property var rows: []
    readonly property var shellGroups: ShellShortcuts.groups
    property string filter: ""

    readonly property int totalCount: {
        if (!window.shellTab) return window.rows.length;
        var n = 0;
        for (var i = 0; i < window.shellGroups.length; i++) n += window.shellGroups[i].items.length;
        return n;
    }

    function clearSearch() { searchField.text = ""; }
    function focusSearch() { searchField.forceActiveFocus(); }
    function handleEscape() { if (window.filter !== "") { clearSearch(); return true; } return false; }

    // The popup host sizes us from these; height follows the tallest column.
    readonly property real targetMasterWidth: window.sheetWidth
    readonly property real targetMasterHeight: window.sheetHeight

    Process {
        id: fetcher
        running: true
        command: ["python3", window.helpersDir + "/shortcuts.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { window.rows = JSON.parse((this.text || "").trim() || "[]"); }
                catch (e) { window.rows = []; }
            }
        }
    }

    // Unknown groups (other people's kwin scripts) hash to a stable glyph and tint.
    readonly property var groupIcons: ({
        "Window Management": "\u{f10ac}",   // md-dock_window
        "Shell":             "\u{f018d}",   // md-console
        "Applications":      "\u{f003b}",   // md-apps
        "Polonium":          "\u{f0570}",   // md-view_grid
        "Media":             "\u{f075a}",   // md-music
        "Plasma":            "\u{f056e}",   // md-view_dashboard

        "Volume popup":                     "\u{f057e}",   // md-volume_high
        "Music popup":                      "\u{f075a}",   // md-music
        "Music popup — Lyrics tab":         "\u{f0370}",   // md-microphone_variant
        "Music popup — Audio tab":          "\u{f062e}",   // md-tune
        "Notification centre":              "\u{f009c}",   // md-bell_outline
        "Network panel":                    "\u{f05a9}",   // md-wifi
        "Clipboard panel":                  "\u{f0a38}",   // md-clipboard_text_outline
        "Floating sidebar":                 "\u{f10aa}",   // md-dock_left
        "Timer tab":                        "\u{f051b}",   // md-timer_outline
        "Screenshot overlay":               "\u{f0e51}",   // md-monitor_screenshot
        "Settings":                         "\u{f08bb}",   // md-cog_outline
        "Wallpaper picker":                 "\u{f0976}",   // md-image_outline
        "Wallpaper picker — Wallhaven tab": "\u{f0978}",   // md-image_search_outline
        "Power panel":                      "\u{f0906}",   // md-power_standby
        "Focus Time":                       "\u{f0150}",   // md-clock_outline
        "Theme picker":                     "\u{f0e0c}",   // md-palette_outline
        "Calendar":                         "\u{f0b66}",   // md-calendar_blank_outline
        "Bar popups":                       "\u{f1513}",   // md-dock_top
        "Widget redactor":                  "\u{f1355}",   // md-widgets_outline
    })
    readonly property var groupTintIndex: ({
        "Window Management": 0,
        "Shell":             1,
        "Polonium":          2,
        "Media":             3,
        "Applications":      4,

        // One tint per in-shell family, so the four Music cards read as one thing.
        "Volume popup":                     3,
        "Music popup":                      3,
        "Music popup — Lyrics tab":         3,
        "Music popup — Audio tab":          3,
        "Notification centre":              0,
        "Network panel":                    0,
        "Clipboard panel":                  0,
        "Power panel":                      0,
        "Floating sidebar":                 2,
        "Timer tab":                        2,
        "Focus Time":                       2,
        "Calendar":                         2,
        "Wallpaper picker":                 1,
        "Wallpaper picker — Wallhaven tab": 1,
        "Theme picker":                     1,
        "Widget redactor":                  1,
        "Screenshot overlay":               4,
        "Settings":                         4,
        "Bar popups":                       4,
    })

    function groupIcon(g) { return window.groupIcons[g] || "\u{f030c}"; }   // md-keyboard
    function groupTint(g) {
        var idx = window.groupTintIndex[g];
        if (idx === undefined) {
            var h = 0;
            for (var i = 0; i < g.length; i++) h = (h * 31 + g.charCodeAt(i)) | 0;
            idx = Math.abs(h);
        }
        return window.groupTints[idx % window.tintCount];
    }

    // --- Key rendering --- every codepoint was checked against Iosevka Nerd Font by
    // glyph NAME, not guessed. Super comes from ShellSettings so it can be re-skinned.
    readonly property string superGlyph: ShellSettings.superKeyGlyph
    readonly property var symMap: {
        var m = ({
            "Left":      "←",
            "Down":      "↓",
            "Up":        "↑",
            "Right":     "→",
            "Tab":       "\u{f0312}",   // md-keyboard_tab
            "Space":     "\u{f1050}",   // md-keyboard_space
            "Backspace": "\u{f030d}",   // md-keyboard_backspace
            "Return":    "\u{f0311}",   // md-keyboard_return
            "Enter":     "\u{f0311}",
        });
        if (window.superGlyph !== "") m["Super"] = window.superGlyph;
        return m;
    }

    // Collapsed families arrive as "Left/Down/Up/Right". A lone "/" is the slash
    // KEY (Super + /), so only split when every side is non-empty.
    function keyParts(tok) {
        var p = ("" + tok).split("/");
        if (p.length < 2) return [tok];
        for (var i = 0; i < p.length; i++) if (p[i] === "") return [tok];
        return p;
    }
    function keyText(tok) {
        var p = window.keyParts(tok), out = [];
        for (var i = 0; i < p.length; i++) out.push(window.symMap[p[i]] || p[i]);
        return out.join(" ");
    }
    function keyIsSymbol(tok) {
        var p = window.keyParts(tok);
        for (var i = 0; i < p.length; i++) if (!window.symMap[p[i]]) return false;
        return true;
    }

    // ---- model ------------------------------------------------------------
    readonly property var groupList: {
        var q = window.filter.toLowerCase().trim();
        if (window.shellTab) {
            if (q === "") return window.shellGroups;
            var shown = [];
            for (var gi = 0; gi < window.shellGroups.length; gi++) {
                var src = window.shellGroups[gi], keep = [];
                var groupHit = src.name.toLowerCase().indexOf(q) !== -1;
                for (var si = 0; si < src.items.length; si++) {
                    var it = src.items[si];
                    if (groupHit
                        || it.label.toLowerCase().indexOf(q) !== -1
                        || ("" + it.chords.join(" ")).toLowerCase().indexOf(q) !== -1)
                        keep.push(it);
                }
                if (keep.length > 0) shown.push({ name: src.name, items: keep });
            }
            return shown;
        }
        var out = [], byName = ({});
        for (var i = 0; i < window.rows.length; i++) {
            var r = window.rows[i];
            if (q !== ""
                && r.label.toLowerCase().indexOf(q) === -1
                && ("" + r.chords.join(" ")).toLowerCase().indexOf(q) === -1
                && r.group.toLowerCase().indexOf(q) === -1)
                continue;
            var g = byName[r.group];
            if (!g) { g = { name: r.group, items: [] }; byName[r.group] = g; out.push(g); }
            g.items.push(r);
        }
        return out;
    }

    readonly property int shownCount: {
        var n = 0;
        for (var i = 0; i < window.groupList.length; i++) n += window.groupList[i].items.length;
        return n;
    }

    // Families packed into columns, largest first into whichever column is currently
    // shortest — so a heading is never stranded from its rows, and "X" never lands in
    // a different column from "X — sub tab".
    // Measured: the in-shell tab clears the 90% height cap in four columns from 1440p up, five on 1080p.
    readonly property int columnCount: !window.shellTab ? 2 : (Screen.height >= 1200 ? 4 : 5)
    readonly property var columns: {
        var cols = [], heights = [];
        for (var c = 0; c < window.columnCount; c++) { cols.push([]); heights.push(0); }

        var fams = [], byRoot = ({});
        for (var i = 0; i < window.groupList.length; i++) {
            var g = window.groupList[i], root = g.name.split(" \u2014 ")[0];
            var f = byRoot[root];
            if (!f) { f = { members: [], weight: 0 }; byRoot[root] = f; fams.push(f); }
            f.members.push(g);
            f.weight += g.items.length + 2;   // heading costs about two rows
        }

        fams.sort(function (a, b) { return b.weight - a.weight; });
        for (var fi = 0; fi < fams.length; fi++) {
            var min = 0;
            for (var k = 1; k < window.columnCount; k++) if (heights[k] < heights[min]) min = k;
            for (var mi = 0; mi < fams[fi].members.length; mi++) cols[min].push(fams[fi].members[mi]);
            heights[min] += fams[fi].weight;
        }
        return cols;
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1; duration: 500; easing.type: Easing.OutExpo; running: true
    }

    Component.onCompleted: Qt.callLater(window.focusSearch)

    Rectangle {
        id: cardMask
        anchors.fill: parent
        radius: Radius.outer(s(20))
        color: "white"
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        scale: 0.96 + (0.04 * introMain)
        opacity: introMain

        Rectangle {
            anchors.fill: parent
            radius: Radius.outer(s(20))
            color: window.base
            border.color: window.surface0
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            Rectangle {
                width: parent.width * 0.55; height: width; radius: width / 2
                x: (parent.width * 0.5 - width / 2) + Math.cos(window.globalOrbitAngle) * window.s(140)
                y: (parent.height * 0.5 - height / 2) + Math.sin(window.globalOrbitAngle) * window.s(100)
                color: window.accent
                opacity: 0.05
            }

            ColumnLayout {
                id: sheetBody
                anchors.fill: parent
                anchors.margins: window.s(24)
                spacing: window.s(14)

                // --- Header + search ---------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(12)

                    Text {
                        text: "\u{f030c}"                 // md-keyboard
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.s(22)
                        color: window.accent
                    }
                    Text {
                        text: "SHORTCUTS"
                        font.family: Fonts.ui
                        font.weight: Font.Black
                        font.pixelSize: window.s(16)
                        color: window.text
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: window.filter === "" ? window.totalCount + " bound"
                                                   : window.shownCount + " of " + window.totalCount
                        font.family: Fonts.ui
                        font.pixelSize: window.s(10)
                        color: window.overlay0
                    }

                    Item { Layout.fillWidth: true }

                    V2.Switch {
                        id: tabSwitch
                        Layout.preferredWidth: window.s(150)
                        Layout.preferredHeight: window.s(30)
                        options: ["KDE", "Shell"]
                        currentIndex: window.tabIndex
                        cornerRadius: Radius.outer(window.s(9))
                        fontFamily: Fonts.ui
                        fontPixelSize: window.s(10)
                        accentColor: window.accent
                        baseColor: Qt.alpha(window.surface0, 0.6)
                        textColor: window.subtext0
                        activeTextColor: window.base
                        onToggled: i => window.tabIndex = i
                    }

                    Rectangle {
                        Layout.preferredWidth: window.s(260)
                        Layout.preferredHeight: window.s(30)
                        radius: Radius.outer(window.s(9))
                        color: Qt.alpha(window.surface0, 0.6)
                        border.width: 1
                        border.color: searchField.activeFocus ? Qt.alpha(window.accent, 0.6)
                                                              : Qt.alpha(window.surface1, 0.6)
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: window.s(10)
                            anchors.rightMargin: window.s(10)
                            spacing: window.s(7)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f0349}"          // md-magnify
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: window.s(12)
                                color: searchField.activeFocus ? window.accent : window.overlay0
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            TextField {
                                id: searchField
                                width: parent.width - window.s(28)
                                anchors.verticalCenter: parent.verticalCenter
                                background: Item {}
                                padding: 0
                                color: window.text
                                font.family: Fonts.ui
                                font.pixelSize: window.s(11)
                                placeholderText: "Type to search"
                                placeholderTextColor: window.overlay0
                                focus: true
                                onTextChanged: window.filter = text
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.alpha(window.surface1, 0.6)
                }

                // --- Group cards, packed into columns -----------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: window.groupList.length > 0
                    spacing: window.s(16)

                    Repeater {
                        model: window.columns

                        delegate: ColumnLayout {
                            id: column
                            required property var modelData
                            required property int index
                            readonly property var colGroups: column.modelData
                            readonly property int colIndex: column.index

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            spacing: window.s(12)

                            Repeater {
                                model: column.colGroups

                                delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    required property int index
                                    readonly property var group: card.modelData
                                    property color tint: window.groupTint(card.group.name)
                                    Behavior on tint { ColorAnimation { duration: 700 } }

                                    // Widest chord in THIS card, so one long chord elsewhere cannot squeeze every label.
                                    property real railWidth: window.s(90)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: cardCol.implicitHeight + window.s(22)
                                    radius: Radius.outer(window.s(14))
                                    color: Qt.alpha(window.surface0, 0.4)
                                    border.width: 1
                                    border.color: Qt.alpha(window.surface1, 0.5)

                                    // Shifted by transform, never y: the ColumnLayout owns y and would stack the cards.
                                    opacity: 0
                                    transform: Translate { id: introShift; y: window.s(10) }
                                    Component.onCompleted: cardIntro.start()
                                    SequentialAnimation {
                                        id: cardIntro
                                        PauseAnimation { duration: (column.colIndex * 70) + (card.index * 90) }
                                        ParallelAnimation {
                                            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: introShift; property: "y"; to: 0; duration: 380; easing.type: Easing.OutExpo }
                                        }
                                    }

                                    ColumnLayout {
                                        id: cardCol
                                        anchors.fill: parent
                                        anchors.margins: window.s(11)
                                        spacing: window.s(2)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.bottomMargin: window.s(4)
                                            spacing: window.s(8)

                                            Text {
                                                text: window.groupIcon(card.group.name)
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(14)
                                                color: card.tint
                                            }
                                            Text {
                                                text: card.group.name.toUpperCase()
                                                font.family: Fonts.ui
                                                font.weight: Font.Black
                                                font.pixelSize: window.s(10)
                                                color: card.tint
                                            }
                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                implicitWidth: countText.implicitWidth + window.s(10)
                                                implicitHeight: window.s(14)
                                                radius: height / 2
                                                color: Qt.alpha(card.tint, 0.15)
                                                Text {
                                                    id: countText
                                                    anchors.centerIn: parent
                                                    text: "" + card.group.items.length
                                                    font.family: Fonts.ui
                                                    font.weight: Font.Bold
                                                    font.pixelSize: window.s(8)
                                                    color: card.tint
                                                }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: 1
                                                color: Qt.alpha(card.tint, 0.18)
                                            }
                                        }

                                        Repeater {
                                            model: card.group.items

                                            delegate: Rectangle {
                                                id: bindRow
                                                required property var modelData
                                                readonly property var bind: bindRow.modelData

                                                Layout.fillWidth: true
                                                Layout.preferredHeight: window.s(22)
                                                radius: Radius.outer(window.s(6))
                                                color: rowHover.hovered ? Qt.alpha(card.tint, 0.1) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                HoverHandler { id: rowHover }

                                                Item {
                                                    id: rail
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: window.s(6)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: card.railWidth
                                                    height: parent.height

                                                    Row {
                                                        id: chipRow
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: window.s(6)

                                                        onImplicitWidthChanged: card.railWidth =
                                                            Math.min(window.s(280), Math.max(card.railWidth, implicitWidth))
                                                        Component.onCompleted: card.railWidth =
                                                            Math.min(window.s(280), Math.max(card.railWidth, implicitWidth))

                                                        // One chip group per live alternate: showing only the first hides the one pressed.
                                                        Repeater {
                                                            model: bindRow.bind.chords

                                                            delegate: Row {
                                                                id: chord
                                                                required property var modelData
                                                                required property int index
                                                                readonly property var parts: ("" + chord.modelData).split(" + ")
                                                                spacing: window.s(3)

                                                                Text {
                                                                    visible: chord.index > 0
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: "/"
                                                                    font.family: Fonts.ui
                                                                    font.pixelSize: window.s(10)
                                                                    color: Qt.alpha(window.overlay0, 0.7)
                                                                    rightPadding: window.s(3)
                                                                }

                                                                Repeater {
                                                                    model: chord.parts

                                                                    delegate: Rectangle {
                                                                        id: chip
                                                                        required property var modelData
                                                                        required property int index
                                                                        // The last chip is the distinguishing key; the modifiers in front repeat forever.
                                                                        readonly property bool isKey: chip.index === chord.parts.length - 1
                                                                        readonly property bool symbolic: window.keyIsSymbol(chip.modelData)

                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        height: window.s(17)
                                                                        width: chipLabel.implicitWidth + window.s(11)
                                                                        radius: Radius.outer(window.s(5))
                                                                        color: chip.isKey ? Qt.alpha(card.tint, 0.16)
                                                                                          : Qt.alpha(window.surface1, 0.7)
                                                                        border.width: 1
                                                                        border.color: chip.isKey ? Qt.alpha(card.tint, 0.45)
                                                                                                 : Qt.alpha(window.overlay0, 0.3)

                                                                        Text {
                                                                            id: chipLabel
                                                                            anchors.centerIn: parent
                                                                            text: window.keyText(chip.modelData)
                                                                            font.family: chip.symbolic ? "Iosevka Nerd Font" : Fonts.ui
                                                                            font.weight: chip.isKey ? Font.Bold : Font.Medium
                                                                            font.pixelSize: chip.symbolic ? window.s(11) : window.s(9)
                                                                            color: chip.isKey ? card.tint : window.subtext0
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    anchors.left: rail.right
                                                    anchors.leftMargin: window.s(12)
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: window.s(6)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: bindRow.bind.label
                                                    font.family: Fonts.ui
                                                    font.pixelSize: window.s(10)
                                                    color: rowHover.hovered ? window.text : window.subtext0
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }   // cards stay top-aligned
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: window.groupList.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: window.s(8)

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\u{f0349}"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: window.s(30)
                            color: Qt.alpha(window.overlay0, 0.5)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.totalCount === 0 ? "No shortcuts found"
                                                          : "Nothing matches \"" + window.filter + "\""
                            font.family: Fonts.ui
                            font.pixelSize: window.s(11)
                            color: window.overlay0
                        }
                    }
                }

                // --- Footer hint -------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: window.s(2)
                    spacing: window.s(7)

                    Rectangle {
                        implicitWidth: escLabel.implicitWidth + window.s(11)
                        implicitHeight: window.s(17)
                        radius: Radius.outer(window.s(5))
                        color: Qt.alpha(window.surface1, 0.7)
                        border.width: 1
                        border.color: Qt.alpha(window.overlay0, 0.3)
                        Text {
                            id: escLabel
                            anchors.centerIn: parent
                            text: "Esc"
                            font.family: Fonts.ui
                            font.weight: Font.Medium
                            font.pixelSize: window.s(9)
                            color: window.subtext0
                        }
                    }
                    Text {
                        text: window.filter === "" ? "close" : "clear search"
                        font.family: Fonts.ui
                        font.pixelSize: window.s(9)
                        color: window.overlay0
                    }

                    Rectangle {
                        Layout.leftMargin: window.s(8)
                        visible: window.superGlyph !== ""
                        implicitWidth: superLegend.implicitWidth + window.s(11)
                        implicitHeight: window.s(17)
                        radius: Radius.outer(window.s(5))
                        color: Qt.alpha(window.surface1, 0.7)
                        border.width: 1
                        border.color: Qt.alpha(window.overlay0, 0.3)
                        Text {
                            id: superLegend
                            anchors.centerIn: parent
                            text: window.superGlyph
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: window.s(11)
                            color: window.subtext0
                        }
                    }
                    Text {
                        visible: window.superGlyph !== ""
                        text: "Super"
                        font.family: Fonts.ui
                        font.pixelSize: window.s(9)
                        color: window.overlay0
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: window.shellTab ? "modules/cheatsheet/ShellShortcuts.js"
                                              : "~/.config/kglobalshortcutsrc"
                        font.family: Fonts.ui
                        font.pixelSize: window.s(9)
                        color: Qt.alpha(window.overlay0, 0.6)
                    }
                }
            }
        }
    }
}
