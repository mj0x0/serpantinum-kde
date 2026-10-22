pragma Singleton

import "../airplane"
import "../audio"
import "../bridge"
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: controller

    readonly property bool enabled: ShellSettings.value("osd.enabled", true) !== false
    readonly property int timeout: Math.max(400, Number(ShellSettings.value("osd.timeout", 1800)) || 1800)

    property bool isVisible: false
    property string kind: "volume"
    property int briVal: 0
    property string stateVal: "off"
    property var screen: null
    property bool isHovered: false

    readonly property PwNode activeSink: Audio.defaultSink || (Audio.outputs && Audio.outputs.length > 0 ? Audio.outputs[0] : null)
    readonly property real sysVolume: activeSink && activeSink.audio ? Math.round(activeSink.audio.volume * 100) : 0
    readonly property bool sysMuted: activeSink && activeSink.audio ? activeSink.audio.muted : false

    readonly property PwNode activeSource: Audio.defaultSource || (Audio.inputs && Audio.inputs.length > 0 ? Audio.inputs[0] : null)
    readonly property real sysMicVolume: activeSource && activeSource.audio ? Math.round(activeSource.audio.volume * 100) : 0
    readonly property bool sysMicMuted: activeSource && activeSource.audio ? activeSource.audio.muted : false

    readonly property bool sysAirplane: AirplaneState.engaged

    // Brightness is PowerDevil's primary display, relayed by the bridge daemon.
    readonly property var brightness: Bridge.brightness || ({})
    readonly property bool hasBrightness: !!brightness.display
    readonly property int sysBrightness: Number(brightness.percent) || 0

    property real lastVolume: -1
    property bool lastMuted: false
    property real lastMicVolume: -1
    property bool lastMicMuted: false
    property bool lastAirplane: false
    property int lastCapsLock: -1
    property int lastNumLock: -1
    property int lastBrightness: -1
    property bool isInitialized: false

    Timer {
        id: hideTimer
        interval: controller.timeout
        repeat: false
        onTriggered: {
            if (!controller.isHovered) {
                controller.isVisible = false;
            }
        }
    }

    // Seed from a timer, not the first change signal: an unchanged device never emits.
    Timer {
        id: initTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            controller.lastVolume = controller.sysVolume;
            controller.lastMuted = controller.sysMuted;
            controller.lastMicVolume = controller.sysMicVolume;
            controller.lastMicMuted = controller.sysMicMuted;
            controller.lastAirplane = controller.sysAirplane;
            controller.lastBrightness = controller.sysBrightness;
            controller.briVal = controller.sysBrightness;
            controller.lastCapsLock = KbLocks.caps ? 1 : 0;
            controller.lastNumLock = KbLocks.num ? 1 : 0;
            controller.isInitialized = true;
        }
    }

    onActiveSinkChanged: { isInitialized = false; initTimer.restart() }
    onActiveSourceChanged: { isInitialized = false; initTimer.restart() }

    onSysVolumeChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastVolume !== controller.sysVolume) {
            controller.lastVolume = controller.sysVolume;
            controller.show("volume");
        }
    }

    onSysMutedChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMuted !== controller.sysMuted) {
            controller.lastMuted = controller.sysMuted;
            controller.show("volume");
        }
    }

    onSysMicVolumeChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMicVolume !== controller.sysMicVolume) {
            controller.lastMicVolume = controller.sysMicVolume;
            controller.show("mic");
        }
    }

    onSysMicMutedChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMicMuted !== controller.sysMicMuted) {
            controller.lastMicMuted = controller.sysMicMuted;
            controller.show("mic");
        }
    }

    onSysAirplaneChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastAirplane !== controller.sysAirplane) {
            controller.lastAirplane = controller.sysAirplane;
            controller.show("airplane", controller.sysAirplane ? "on" : "off");
        }
    }

    onSysBrightnessChanged: {
        if (!controller.isInitialized) { controller.briVal = controller.sysBrightness; return; }
        if (controller.lastBrightness !== controller.sysBrightness) {
            controller.lastBrightness = controller.sysBrightness;
            controller.show("brightness", controller.sysBrightness);
        }
    }

    Connections {
        target: KbLocks
        function onCapsChanged() {
            if (!controller.isInitialized) return;
            controller.lastCapsLock = KbLocks.caps ? 1 : 0;
            controller.show("capslock", KbLocks.caps ? "on" : "off");
        }
        function onNumChanged() {
            if (!controller.isInitialized) return;
            controller.lastNumLock = KbLocks.num ? 1 : 0;
            controller.show("numlock", KbLocks.num ? "on" : "off");
        }
    }

    // What Plasma would have drawn: PowerDevil and KWin call org.kde.osdService, the bridge relays it.
    Connections {
        target: Bridge
        function onOsdCall(member, args) {
            if (!controller.isInitialized) return;
            if (member === "screenBrightnessChanged" || member === "brightnessChanged") {
                controller.lastBrightness = Number(args[0]) || 0;
                controller.show("brightness", controller.lastBrightness);
            } else if (member === "kbdLayoutChanged") {
                controller.show("keyboard", "" + args[0]);
            }
        }
    }

    function setBrightness(pct) {
        if (!hasBrightness) return;
        var max = Number(brightness.max) || 0;
        if (max <= 0) return;
        var value = Math.round(Math.max(0, Math.min(100, pct)) / 100 * max);
        // Flag 1 keeps PowerDevil from calling the OSD service for our own change.
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.ScreenBrightness",
            "/org/kde/ScreenBrightness/" + brightness.display, "org.kde.ScreenBrightness.Display",
            "SetBrightness", "iu", "" + value, "1"]);
    }

    function show(k, v, scr) {
        if (!enabled) return;
        controller.kind = k || "volume";
        if (controller.kind === "brightness" && v !== undefined) {
            controller.briVal = parseInt(v) || 0;
        } else if (v !== undefined) {
            controller.stateVal = v.toString();
        }
        if (scr !== undefined && scr !== null) {
            controller.screen = scr;
        }
        controller.isVisible = true;
        hideTimer.restart();
    }

    function display(k, v, scr) {
        show(k, v, scr);
    }

    function hide() {
        hideTimer.stop();
        controller.isVisible = false;
    }

    function requestHide() {
        if (!controller.isHovered) {
            hideTimer.restart();
        }
    }

    function cancelHide() {
        hideTimer.stop();
    }

    function restartTimer() {
        if (controller.isVisible) {
            hideTimer.restart();
        }
    }

    function toggle(k, v, scr) {
        if (controller.isVisible && controller.kind === k) {
            hide();
        } else {
            show(k, v, scr);
        }
    }
}
