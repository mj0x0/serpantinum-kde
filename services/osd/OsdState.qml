pragma Singleton

import "../audio"
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
    property var screen: null
    property bool isHovered: false

    readonly property PwNode activeSink: Audio.defaultSink || (Audio.outputs && Audio.outputs.length > 0 ? Audio.outputs[0] : null)
    readonly property real sysVolume: activeSink && activeSink.audio ? Math.round(activeSink.audio.volume * 100) : 0
    readonly property bool sysMuted: activeSink && activeSink.audio ? activeSink.audio.muted : false

    readonly property PwNode activeSource: Audio.defaultSource || (Audio.inputs && Audio.inputs.length > 0 ? Audio.inputs[0] : null)
    readonly property real sysMicVolume: activeSource && activeSource.audio ? Math.round(activeSource.audio.volume * 100) : 0
    readonly property bool sysMicMuted: activeSource && activeSource.audio ? activeSource.audio.muted : false

    property real lastVolume: -1
    property bool lastMuted: false
    property real lastMicVolume: -1
    property bool lastMicMuted: false
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

    function show(k, scr) {
        if (!enabled) return;
        controller.kind = k || "volume";
        if (scr !== undefined && scr !== null) {
            controller.screen = scr;
        }
        controller.isVisible = true;
        hideTimer.restart();
    }

    function display(k, scr) {
        show(k, scr);
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

    function toggle(k, scr) {
        if (controller.isVisible && controller.kind === k) {
            hide();
        } else {
            show(k, scr);
        }
    }
}
