// Screen eyedropper via the xdg-desktop-portal (helpers/color-pick.py). The pick is
// written to a state file, so it survives the Floating panel collapsing mid-pick.

import "../../../services/layout"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    // --- Host contract -------------------------------------------------------
    function s(val) { return typeof scaleFunc === "function" ? scaleFunc(val) : val; }
    property int requestedLayoutTemplate: 1
    property real baseW: s(370)
    property real baseL: s(450)
    property bool onBottom: typeof activeEdge !== "undefined" && activeEdge === "bottom"
    property real preferredWidth:      onBottom ? baseL : baseW
    property real preferredExtraLength: onBottom ? baseW : baseL

    // Floating rotates tab content per edge; counter-rotate so the picker stays upright.
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"
    property real counterRotation: {
        if (safeActiveEdge === "right") return 180;
        if (safeActiveEdge === "bottom") return 90;
        return 0;
    }

    MatugenColors { id: _theme }
    property color cBase: _theme.base
    property color cSurface0: _theme.surface0
    property color cSurface1: _theme.surface1
    property color cSurface2: _theme.surface2
    property color cText: _theme.text
    property color cSubtext0: _theme.subtext0
    property color cMauve: _theme.mauve
    property color cGreen: _theme.green
    property string uiFont: Fonts.ui

    // --- Paths ---------------------------------------------------------------
    readonly property string helpersDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"
    readonly property string stateDir:   Quickshell.env("HOME") + "/.local/state/quickshell/colorpicker"
    readonly property string lastPickPath: stateDir + "/last_pick"
    readonly property string recentPath:   stateDir + "/recent.json"

    // --- State ---------------------------------------------------------------
    property color pickedColor: cMauve
    property real  alphaVal: 1.0                 // 0..1
    property var   recentColors: []
    property bool  recentsLoaded: false
    property string pendingPick: ""
    property string flashKey: ""
    Timer { id: flashTimer; interval: 1000; onTriggered: root.flashKey = "" }

    // --- Format outputs ------------------------------------------------------
    function h2(x) { var h = Math.round(Math.max(0, Math.min(255, x * 255))).toString(16); return h.length < 2 ? "0" + h : h; }
    readonly property int rC: Math.round(pickedColor.r * 255)
    readonly property int gC: Math.round(pickedColor.g * 255)
    readonly property int bC: Math.round(pickedColor.b * 255)
    readonly property int aPct: Math.round(alphaVal * 100)
    readonly property bool hasAlpha: alphaVal < 0.999

    readonly property string hexOut: ("#" + h2(pickedColor.r) + h2(pickedColor.g) + h2(pickedColor.b) + (hasAlpha ? h2(alphaVal) : "")).toUpperCase()
    readonly property string rgbOut: hasAlpha
        ? ("rgba(" + rC + ", " + gC + ", " + bC + ", " + alphaVal.toFixed(2) + ")")
        : ("rgb(" + rC + ", " + gC + ", " + bC + ")")
    readonly property var hslV: toHsl(pickedColor)
    readonly property string hslOut: hasAlpha
        ? ("hsla(" + hslV.h + ", " + hslV.s + "%, " + hslV.l + "%, " + alphaVal.toFixed(2) + ")")
        : ("hsl(" + hslV.h + ", " + hslV.s + "%, " + hslV.l + "%)")

    function toHsl(c) {
        var r = c.r, g = c.g, b = c.b;
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
        var h = 0, sl = 0, l = (mx + mn) / 2;
        if (mx !== mn) {
            var d = mx - mn;
            sl = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (mx === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }
        return { h: Math.round(h * 360), s: Math.round(sl * 100), l: Math.round(l * 100) };
    }

    // --- Actions -------------------------------------------------------------
    function pick() { Quickshell.execDetached(["python3", root.helpersDir + "/color-pick.py"]); }

    function applyPick(hex) {
        hex = (hex || "").trim().toLowerCase();
        if (!/^#[0-9a-f]{6}$/.test(hex)) return;
        if (!recentsLoaded) { root.pendingPick = hex; return; }
        root.pickedColor = hex;
        addRecent(hex);
    }
    function addRecent(hex) {
        hex = hex.toLowerCase();
        var arr = root.recentColors.slice().filter(function (x) { return String(x).toLowerCase() !== hex; });
        arr.unshift(hex);
        if (arr.length > 10) arr = arr.slice(0, 10);
        root.recentColors = arr;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p '" + root.stateDir + "'; printf '%s' '" + JSON.stringify(arr) + "' > '" + root.recentPath + "'"]);
    }
    function onRecentsLoaded(arr) {
        root.recentColors = Array.isArray(arr) ? arr : [];
        root.recentsLoaded = true;
        if (root.pendingPick) { var p = root.pendingPick; root.pendingPick = ""; applyPick(p); }
    }
    function copyText(txt, key) {
        Quickshell.execDetached(["wl-copy", txt]);
        root.flashKey = key; flashTimer.restart();
    }

    // --- Persistence I/O -----------------------------------------------------
    Process {
        id: recentsLoader
        command: ["sh", "-c", "cat '" + root.recentPath + "' 2>/dev/null || echo '[]'"]
        stdout: StdioCollector { onStreamFinished: {
            var a = []; try { a = JSON.parse((this.text || "[]").trim() || "[]"); } catch (e) {}
            root.onRecentsLoaded(a);
        } }
    }
    Process {
        id: lastPickReader
        command: ["sh", "-c", "cat '" + root.lastPickPath + "' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.applyPick(this.text) }
    }
    Process {
        id: lastPickWatcher
        running: true
        command: ["sh", "-c", "touch '" + root.lastPickPath + "' 2>/dev/null; setpriv --pdeathsig KILL inotifywait -qq -e close_write,modify '" + root.lastPickPath + "' 2>/dev/null || sleep 2"]
        onExited: {
            lastPickReader.running = false; lastPickReader.running = true;
            lastPickWatcher.running = false; lastPickWatcher.running = true;
        }
    }
    Component.onCompleted: { recentsLoader.running = true; lastPickReader.running = true; }

    // --- UI — wrapped in orientedRoot so it stays upright on right/bottom edges. ---
    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width:  (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation

        ColumnLayout {
        anchors.fill: parent
        spacing: root.s(10)

        Text {
            text: "COLOUR PICKER"
            font.family: root.uiFont; font.weight: Font.Black; font.pixelSize: root.s(13)
            color: root.cSubtext0
            Layout.alignment: Qt.AlignHCenter
        }

        // Swatch (with checkerboard behind for alpha) + eyedropper button.
        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(10)

            Rectangle {
                Layout.preferredWidth: root.s(56); Layout.preferredHeight: root.s(56)
                radius: Radius.outer(root.s(12)); clip: true
                border.width: 1; border.color: root.cSurface2
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d"); var sz = root.s(8);
                        for (var y = 0; y < height; y += sz)
                            for (var x = 0; x < width; x += sz) {
                                ctx.fillStyle = ((Math.floor(x / sz) + Math.floor(y / sz)) % 2 === 0) ? "#e0e0e0" : "#a8a8a8";
                                ctx.fillRect(x, y, sz, sz);
                            }
                    }
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(root.pickedColor.r, root.pickedColor.g, root.pickedColor.b, root.alphaVal) }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: root.s(56)
                radius: Radius.outer(root.s(12))
                color: pickMa.containsMouse ? root.cSurface1 : root.cSurface0
                border.width: 1; border.color: pickMa.containsMouse ? root.cMauve : root.cSurface1
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                RowLayout {
                    anchors.centerIn: parent; spacing: root.s(10)
                    Text { text: "󰈊"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(22); color: pickMa.containsMouse ? root.cMauve : root.cText }
                    Text { text: "Pick from screen"; font.family: root.uiFont; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.cText }
                }
                MouseArea { id: pickMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick() }
            }
        }

        // Format rows: HEX / RGB / HSL, click to copy.
        Repeater {
            model: [
                { key: "hex", label: "HEX", value: root.hexOut },
                { key: "rgb", label: "RGB", value: root.rgbOut },
                { key: "hsl", label: "HSL", value: root.hslOut }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(40)
                radius: Radius.outer(root.s(10))
                color: fmtMa.containsMouse ? root.cSurface1 : root.cSurface0
                border.width: 1; border.color: root.cSurface1
                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(12); anchors.rightMargin: root.s(12)
                    spacing: root.s(10)
                    Text {
                        text: modelData.label
                        font.family: root.uiFont; font.weight: Font.Black; font.pixelSize: root.s(11)
                        color: root.cMauve
                        Layout.preferredWidth: root.s(34)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.flashKey === modelData.key ? "Copied!" : modelData.value
                        color: root.flashKey === modelData.key ? root.cGreen : root.cText
                        font.family: root.uiFont; font.weight: Font.Medium; font.pixelSize: root.s(13)
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        text: "󰆏"   // md-content-copy
                        font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15)
                        color: fmtMa.containsMouse ? root.cMauve : root.cSubtext0
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
                MouseArea {
                    id: fmtMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyText(modelData.value, modelData.key)
                }
            }
        }

        // Opacity slider.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.s(4)
            RowLayout {
                Layout.fillWidth: true
                Text { text: "OPACITY"; font.family: root.uiFont; font.weight: Font.Black; font.pixelSize: root.s(11); color: root.cSubtext0 }
                Item { Layout.fillWidth: true }
                Text { text: root.aPct + "%"; font.family: root.uiFont; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.cText }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(20)
                Rectangle {
                    id: opTrack
                    anchors.fill: parent
                    radius: height / 2
                    color: root.cSurface0
                    border.width: 1; border.color: root.cSurface1
                    clip: true
                    Rectangle {
                        height: parent.height
                        width: parent.width * root.alphaVal
                        radius: parent.radius
                        color: Qt.rgba(root.pickedColor.r, root.pickedColor.g, root.pickedColor.b, 1.0)
                        opacity: 0.9
                    }
                    Rectangle {
                        width: root.s(8); height: parent.height + root.s(4); radius: root.s(4)
                        y: -root.s(2)
                        x: Math.max(0, Math.min(opTrack.width - width, root.alphaVal * opTrack.width - width / 2))
                        color: "white"; border.width: root.s(2); border.color: root.cSurface2
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (m) => root.alphaVal = Math.max(0, Math.min(1, m.x / opTrack.width))
                        onPositionChanged: (m) => { if (pressed) root.alphaVal = Math.max(0, Math.min(1, m.x / opTrack.width)); }
                    }
                }
            }
        }

        // Recent colours.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.s(6)
            Text { text: "RECENT"; font.family: root.uiFont; font.weight: Font.Black; font.pixelSize: root.s(11); color: root.cSubtext0 }
            Text {
                visible: root.recentColors.length === 0
                text: "No recent colours yet — pick one."
                font.family: root.uiFont; font.italic: true; font.pixelSize: root.s(12); color: root.cSubtext0
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(6)
                visible: root.recentColors.length > 0
                Repeater {
                    model: root.recentColors
                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: root.s(26); Layout.preferredHeight: root.s(26)
                        radius: Radius.outer(root.s(7))
                        color: modelData
                        border.width: 1; border.color: swMa.containsMouse ? root.cMauve : root.cSurface2
                        scale: swMa.containsMouse ? 1.12 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        MouseArea {
                            id: swMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.pickedColor = modelData; root.alphaVal = 1.0; }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Item { Layout.fillHeight: true }
        }
    }
}
