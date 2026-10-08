// One window for every popup, serpantinum v2's Main.qml on our modules: a clipped box
// morphs between the registry's per-widget geometry while the content is swapped
// inside it. Popups are built on open and torn down after close, so nothing idles.

import "../../services/bar"
import "../../services/layout"
import "../bluetooth"
import "../network"
import "../notifcenter"
import "../power"
import "../volume"
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services/layout/PopupRegistry.js" as Registry

PanelWindow {
    id: host

    readonly property bool shown: Popups.current !== "hidden"
    // Stays mapped until the exit fade has run out.
    visible: shown || stage.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-popups"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // The bar's strip keeps its clicks, except where the card covers it.
    mask: Region {
        item: barHole
        intersection: Intersection.Xor
        Region { item: box; intersection: Intersection.Subtract }
    }

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return scaler.s(v); }

    Connections {
        target: Popups
        function onRequested(name, arg) { host.switchWidget(name, arg) }
    }

    // The only Escape in this window; a popup may consume it first via handleEscape().
    Shortcut {
        sequence: "Escape"
        enabled: host.shown
        onActivated: {
            var it = stage.item;
            if (it && typeof it.handleEscape === "function" && it.handleEscape()) return;
            Popups.hide();
        }
    }

    MouseArea { anchors.fill: parent; enabled: host.shown; onClicked: Popups.hide() }

    Item {
        id: barHole
        readonly property bool active: host.shown && !BarState.hidden
        readonly property real t: BarState.bandThickness
        x: (active && BarState.position === "right") ? host.width - t : 0
        y: (active && BarState.position === "bottom") ? host.height - t : 0
        width: !active ? 0 : (BarState.isVertical ? t : host.width)
        height: !active ? 0 : (BarState.isVertical ? host.height : t)
    }

    // --- geometry -----------------------------------------------------------
    function iconCenter(name) {
        switch (name) {
        case "network":     return [NetworkState.iconCenterX, NetworkState.iconCenterY];
        case "bluetooth":   return [BluetoothState.iconCenterX, BluetoothState.iconCenterY];
        case "power":       return [PowerState.iconCenterX, PowerState.iconCenterY];
        case "volume":      return [VolumeState.iconCenterX, VolumeState.iconCenterY];
        case "notifcenter": return [NotifCenterState.iconCenterX, NotifCenterState.iconCenterY];
        }
        return [-1, -1];
    }

    function layoutFor(name, item) {
        var t = Registry.get(name);
        if (!t) return null;
        var W = host.width, H = host.height;
        var w = t.w === "fill" ? W : s(t.w);
        var h = t.h === "fill" ? H : s(t.h);
        if (item) {
            if (typeof item.targetMasterWidth === "number" && item.targetMasterWidth >= 50) w = item.targetMasterWidth;
            if (typeof item.targetMasterHeight === "number" && item.targetMasterHeight >= 50) h = item.targetMasterHeight;
        }
        var gaps = { top: BarState.topGap, bottom: BarState.bottomGap, left: BarState.leftGap, right: BarState.rightGap };
        var p = Registry.place(t.pos[BarState.position] || t.pos.top, BarState.position,
                               w, h, W, H, gaps, iconCenter(name), s);
        return { x: p.x, y: p.y, w: w, h: h };
    }

    // Re-evaluated when the screen, the bar or the popup's own target size changes.
    // objectName gates the moment between swapping the item and updating current.
    readonly property var lay: (shown && stage.item && stage.item.objectName === Popups.current)
                               ? layoutFor(Popups.current, stage.item) : null
    onLayChanged: if (lay) applyLayout(lay)

    property real boxX: 0
    property real boxY: 0
    property real boxW: 1
    property real boxH: 1
    property real stageW: 1
    property real stageH: 1

    function applyLayout(l) {
        boxX = l.x; boxY = l.y; boxW = l.w; boxH = l.h;
        stageW = l.w; stageH = l.h;
    }

    // --- switching ----------------------------------------------------------
    property int generation: 0
    property bool morph: false
    property int morphMs: 300
    readonly property int switchMs: 300
    readonly property int exitMs: 180
    property int exitFadeMs: 140
    property bool exitScales: true
    property var components: ({})

    function componentFor(name, url) {
        var c = components[name];
        if (!c) { c = Qt.createComponent(url); components[name] = c; }
        return c;
    }

    function switchWidget(name, arg) {
        generation++;
        var gen = generation;
        clearTimer.stop();

        if (name === "hidden") {
            if (Popups.current !== "hidden") {
                // A popup with beginClose() plays its own outro and says how long it needs.
                var it = stage.item;
                var ms = 0;
                if (it && typeof it.beginClose === "function") {
                    var r = it.beginClose();
                    ms = (typeof r === "number" && r > 0) ? Math.round(r) : 0;
                }
                exitFadeMs = ms > 0 ? ms : 140;
                exitScales = ms === 0;
                clearTimer.interval = ms > 0 ? ms + 40 : 200;
                Popups.current = "hidden";
                Popups.arg = "";
                morphMs = exitMs;
                morph = false;
                clearTimer.gen = gen;
                clearTimer.restart();
            }
            return;
        }

        var t = Registry.get(name);
        if (!t) { console.warn("PopupHost: unknown popup", name); return; }
        var comp = componentFor(name, t.comp);
        // Never cache a failed build: the file is not hot-reload watched, so a fix must retry.
        if (comp.status === Component.Error) { console.warn("PopupHost:", name, comp.errorString()); delete components[name]; return; }
        var item = comp.createObject(stage, {});
        if (!item) { console.warn("PopupHost: could not build", name); return; }
        if (gen !== generation) { item.destroy(); return; }

        var fromHidden = Popups.current === "hidden" || stage.item === null;
        // From hidden the box must not slide over from the last popup's place. A popup that
        // animates itself (an edge sheet) never gets the box stretched into or out of it.
        var selfAnim = item.selfAnimates === true || (stage.item !== null && stage.item.selfAnimates === true);
        morph = !fromHidden && !selfAnim;
        morphMs = switchMs;

        item.objectName = name;
        item.width = Qt.binding(function () { return stage.width; });
        item.height = Qt.binding(function () { return stage.height; });
        if (item.closeRequested !== undefined) item.closeRequested.connect(function () { Popups.hideIf(name); });

        var old = stage.item;
        stage.item = item;
        Popups.current = name;
        Popups.arg = arg;
        if (old) old.destroy();
        item.forceActiveFocus();

        if (fromHidden && !selfAnim) Qt.callLater(function () {
            if (gen === generation && Popups.current === name) morph = true;
        });
    }

    // After the exit fade the popup is torn down; the next open starts clean.
    Timer {
        id: clearTimer
        interval: 200
        property int gen: -1
        onTriggered: {
            if (Popups.current !== "hidden" || gen !== host.generation) return;
            if (stage.item) { stage.item.destroy(); stage.item = null; }
            host.morph = false;
        }
    }

    // --- the box that morphs ------------------------------------------------
    Item {
        id: box
        x: host.boxX
        y: host.boxY
        width: host.boxW
        height: host.boxH
        clip: true

        Behavior on x      { enabled: host.morph; NumberAnimation { duration: host.morphMs; easing.type: Easing.OutCubic } }
        Behavior on y      { enabled: host.morph; NumberAnimation { duration: host.morphMs; easing.type: Easing.OutCubic } }
        Behavior on width  { enabled: host.morph; NumberAnimation { duration: host.morphMs; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: host.morph; NumberAnimation { duration: host.morphMs; easing.type: Easing.OutCubic } }

        // Laid out at the target size and centred, so the content never reflows mid-morph.
        Item {
            id: stage
            property Item item: null
            width: host.stageW
            height: host.stageH
            x: (box.width - width) / 2
            y: (box.height - height) / 2
            transformOrigin: Item.Center
            // Set by popups that play their own entrance and exit; the host then only shows and hides them.
            readonly property bool selfAnimates: item !== null && item.selfAnimates === true

            scale: host.shown || !host.exitScales || selfAnimates ? 1 : 0.96
            Behavior on scale {
                id: scaleBehavior
                enabled: !stage.selfAnimates
                NumberAnimation {
                    readonly property bool opening: scaleBehavior.targetValue > 0.98
                    duration: opening ? 280 : 160
                    easing.type: opening ? Easing.OutCubic : Easing.InCubic
                }
            }
            opacity: host.shown || selfAnimates ? 1 : 0
            Behavior on opacity {
                id: fadeBehavior
                enabled: !stage.selfAnimates
                NumberAnimation {
                    duration: fadeBehavior.targetValue > 0.5 ? 200 : host.exitFadeMs
                    easing.type: fadeBehavior.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
                }
            }

            // Swallow clicks on the card so they never reach the catcher above.
            MouseArea { anchors.fill: parent }
        }
    }
}
