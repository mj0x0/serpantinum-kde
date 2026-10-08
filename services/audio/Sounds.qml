pragma Singleton

// serpantinum v2's UI sound effects, off unless ui.sfx is on. Playback is a detached
// pw-play per sound, exactly as v2 does: decoding and stream setup happen in that child,
// never on the GUI thread, so a click never waits on audio.
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool enabled: ShellSettings.value("ui.sfx", false) === true
    readonly property real masterVolume: {
        var v = Number(ShellSettings.value("ui.sfxVolume", 100));
        return Math.max(0, Math.min(100, isFinite(v) ? v : 100)) / 100;
    }
    readonly property string soundsDir:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/services/audio/sounds/"

    // pw-play (pipewire) or paplay (pulseaudio); empty until the probe answers, and an
    // empty player just means silence.
    property string player: ""
    Process {
        running: true
        command: ["sh", "-c", "command -v pw-play || command -v paplay || true"]
        stdout: StdioCollector { onStreamFinished: root.player = (this.text || "").trim().split("\n")[0] }
    }

    // v2's API. `duration` and `overrideSfxBlock` are dead in v2 too; kept so ported callers parse.
    function playSfx(filename, volume, duration, overrideSfxBlock) {
        root.play(root.soundsDir + filename, volume);
    }

    function play(filePath, volume) {
        if (!root.enabled || !filePath || root.player === "") return;
        var path = ("" + filePath).replace(/^file:\/\//, "");
        var v = volume === undefined ? 1.0 : Math.max(0.0, Math.min(2.0, volume));
        v = Math.min(1.0, v * root.masterVolume);
        if (v <= 0.0) return;
        // paplay wants 0-65536, pw-play a float.
        var flag = root.player.endsWith("paplay")
                 ? "--volume=" + Math.round(v * 65536)
                 : "--volume=" + v;
        Quickshell.execDetached([root.player, flag, path]);
    }

    // Ported v2 code calls these for its charge loops; we have no looping sounds.
    function playUntilStopped(filenameOrPath, volume) { root.play(filenameOrPath, volume); return -1; }
    function stopSfx(handleId) {}
    function stopAllSfx() {}
}
