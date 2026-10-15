pragma Singleton

// Volume and microphone OSD state. Turn Plasma's own volume OSD off or both show:
// System Settings -> Sound, or plasmaparc [General] VolumeOsd/MuteOsd.
import "../audio"
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property bool enabled: ShellSettings.value("osd.enabled", true) !== false
    readonly property int timeout: Math.max(400, Number(ShellSettings.value("osd.timeout", 1800)) || 1800)

    property bool visible: false
    property string kind: "volume"          // "volume" | "mic"

    readonly property PwNode sink: Audio.defaultSink
    // A filter node as the default source (Easy Effects makes one) exposes no volume to
    // Quickshell, so fall back to the first real input that does.
    readonly property PwNode source: {
        var d = Audio.defaultSource;
        if (d && d.audio) return d;
        var ins = Audio.inputs || [];
        for (var i = 0; i < ins.length; i++)
            if (ins[i] && ins[i].audio) return ins[i];
        return d;
    }

    readonly property int volume: (sink && sink.audio) ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false
    readonly property int micVolume: (source && source.audio) ? Math.round(source.audio.volume * 100) : 0
    readonly property bool micMuted: (source && source.audio) ? source.audio.muted : false

    readonly property int shownValue: kind === "mic" ? micVolume : volume
    readonly property bool shownMuted: kind === "mic" ? micMuted : muted

    // Tracking the nodes keeps their audio bound, so volume changes actually arrive.
    PwObjectTracker { objects: [root.sink, root.source].filter(n => n) }

    function show(k) {
        if (!enabled) return;
        kind = k;
        visible = true;
        hideTimer.restart();
    }

    Timer { id: hideTimer; interval: root.timeout; onTriggered: root.visible = false }

    // Nothing shows until a real change arrives: the first reading, and every switch of
    // default device, only seeds the baseline.
    property int lastVolume: -1
    property int lastMicVolume: -1
    property bool lastMuted: false
    property bool lastMicMuted: false
    property bool seeded: false
    property bool micSeeded: false

    onSinkChanged: { seeded = false; seedTimer.restart() }
    onSourceChanged: { micSeeded = false; seedTimer.restart() }

    // A device that never moves never emits, so the baseline cannot wait for a signal:
    // without this the first real change is swallowed as the seed.
    Timer {
        id: seedTimer
        interval: 600
        running: true
        onTriggered: {
            if (!root.seeded) { root.lastVolume = root.volume; root.lastMuted = root.muted; root.seeded = true; }
            if (!root.micSeeded) { root.lastMicVolume = root.micVolume; root.lastMicMuted = root.micMuted; root.micSeeded = true; }
        }
    }

    onVolumeChanged: step("volume")
    onMutedChanged: step("volume")
    onMicVolumeChanged: step("mic")
    onMicMutedChanged: step("mic")

    function step(k): void {
        if (k === "mic") {
            if (!micSeeded) { micSeeded = true; lastMicVolume = micVolume; lastMicMuted = micMuted; return; }
            if (micVolume === lastMicVolume && micMuted === lastMicMuted) return;
            lastMicVolume = micVolume;
            lastMicMuted = micMuted;
            show("mic");
        } else {
            if (!seeded) { seeded = true; lastVolume = volume; lastMuted = muted; return; }
            if (volume === lastVolume && muted === lastMuted) return;
            lastVolume = volume;
            lastMuted = muted;
            show("volume");
        }
    }
}
