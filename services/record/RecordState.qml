// The one owner of gpu-screen-recorder state: the overlay starts it, the bar pill reads and
// stops it, IPC does both. Every call goes through helpers/record.sh; GSR itself is detached
// so a recording survives the overlay and a shell restart (status re-attaches at startup).
pragma Singleton

import "../caching"
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    Caching { id: paths }

    property bool recording: false
    property bool paused: false
    property real startedAt: 0          // epoch ms
    property int elapsed: 0             // seconds since startedAt
    property string outputPath: ""
    property string lastError: ""
    property bool busy: false

    property var hdrOutputs: []
    property bool hdrProbed: false
    function isHdr(name) { return root.hdrOutputs.indexOf("" + name) !== -1 }
    function refreshHdr() { if (!hdrProc.running) hdrProc.running = true }

    // shellDir is a file:// URL; a command needs a plain path.
    readonly property string shellRoot: ("" + Quickshell.shellDir).replace(/^file:\/\//, "")
    readonly property string helper: root.shellRoot + "/helpers/record.sh"
    readonly property string runDir: paths.getRunDir("record")
    readonly property string socketPath: root.runDir + "/gsr.sock"

    function setting(key, fallback) { return ShellSettings.value("record." + key, fallback) }

    function startArgs(opts) {
        var output = "" + (opts.output || "");
        var hdr = opts.hdr !== undefined ? opts.hdr === true
                                         : (root.setting("hdr", true) !== false && root.isHdr(output));
        var args = ["bash", root.helper, "start", "--run-dir", root.runDir,
                    "--dir", ShellSettings.expandHome(("" + root.setting("dir", "")).trim() || "~/Videos/Screencasts")];
        if (output !== "") args.push("--output", output);
        if (opts.region) args.push("--region", "" + opts.region);
        args.push("--hdr", hdr ? "yes" : "no",
                  "--audio", "" + (opts.audio || root.setting("audio", "system")),
                  "--fps", "" + (Math.round(Number(root.setting("fps", 60))) || 60),
                  "--quality", "" + root.setting("quality", "very_high"),
                  "--codec", "" + root.setting("codec", "h264"),
                  "--hdr-codec", "" + root.setting("hdrCodec", "hevc_hdr"),
                  "--container", "" + root.setting("container", "mp4"),
                  "--hdr-container", "" + root.setting("hdrContainer", "mkv"),
                  "--cursor", root.setting("cursor", true) !== false ? "yes" : "no",
                  "--fm", "" + root.setting("frameMode", "vfr"),
                  "--cr", "" + root.setting("colorRange", "limited"));
        return args;
    }

    // A status poll that overlaps a start or stop is stale by the time it answers; the generation drops it.
    property int gen: 0
    property int pollGen: -1

    function start(opts) {
        if (root.busy || root.recording) return;
        root.gen++;
        root.lastError = "";
        root.busy = true;
        startProc.command = root.startArgs(opts || {});
        startProc.running = true;
    }

    function stop() {
        if (root.busy) return;
        root.gen++;
        root.busy = true;
        stopProc.running = true;
    }

    // Held shortcuts re-fire on some keyboards; a toggle settles briefly, as in ScreenshotState.
    property double lastPauseToggle: 0
    function togglePause() {
        var now = Date.now();
        if (root.busy || !root.recording || pauseProc.running || now - root.lastPauseToggle < 500) return;
        root.lastPauseToggle = now;
        pauseProc.running = true;
    }

    function debugState() {
        return JSON.stringify({
            recording: root.recording, paused: root.paused, busy: root.busy,
            startedAt: root.startedAt, elapsed: root.elapsed, outputPath: root.outputPath,
            lastError: root.lastError, hdrOutputs: root.hdrOutputs, hdrProbed: root.hdrProbed,
            socketPath: root.socketPath
        });
    }

    // --- replies ----------------------------------------------------------------

    function lastLine(text) {
        var lines = ("" + text).split("\n");
        for (var i = lines.length - 1; i >= 0; i--)
            if (lines[i].trim() !== "")
                return lines[i].trim();
        return "";
    }

    function parse(text) {
        var line = root.lastLine(text);
        try {
            var o = JSON.parse(line);
            if (o && typeof o === "object") return o;
        } catch (e) {}
        return null;
    }

    function replyError(o, text, fallback) {
        if (o) return "" + (o.error || fallback);
        var line = root.lastLine(text);
        return line === "" ? "record.sh returned nothing" : "Unexpected reply from record.sh: " + line;
    }

    function attach(o) {
        root.outputPath = "" + (o.file || "");
        root.startedAt = Number(o.startedAt) || Date.now();
        root.paused = o.paused === true;
        root.recording = true;
        root.tick();
    }

    function clear() {
        root.recording = false;
        root.paused = false;
        root.elapsed = 0;
    }

    function fail(msg) {
        root.lastError = msg;
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Screen Recorder",
                                 "Recording failed", msg]);
    }

    function tick() {
        root.elapsed = root.startedAt > 0 ? Math.max(0, Math.floor((Date.now() - root.startedAt) / 1000)) : 0;
    }

    function applyStatus(text) {
        var o = root.parse(text);
        // A broken or stale reply must not drop a live recording; the next poll decides.
        if (!o || root.pollGen !== root.gen || root.busy) return;
        if (o.running === true) {
            if (root.recording) root.paused = o.paused === true;
            else root.attach(o);
        } else if (root.recording) {
            if (o.error) root.fail("Recording stopped: " + o.error);
            root.clear();
        }
    }

    // --- processes --------------------------------------------------------------

    Process {
        id: startProc
        property bool failed: false
        stdout: StdioCollector {
            onStreamFinished: {
                var o = root.parse(this.text);
                startProc.failed = !(o && o.ok === true);
                if (startProc.failed) root.fail(root.replyError(o, this.text, "Recording failed"));
                else root.attach(o);
            }
        }
        onExited: {
            root.gen++;
            root.busy = false;
            // A recorder the script gave up on, or refused to double-start, is still live and must stay stoppable.
            if (startProc.failed) {
                startProc.failed = false;
                root.refreshStatus();
                lateAttach.restart();
            }
        }
    }
    Timer { id: lateAttach; interval: 4000; onTriggered: root.refreshStatus() }

    Process {
        id: stopProc
        command: ["bash", root.helper, "stop", "--run-dir", root.runDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = root.parse(this.text);
                if (o && o.ok === true) {
                    if (o.file) root.outputPath = "" + o.file;
                    root.clear();
                } else {
                    root.lastError = root.replyError(o, this.text, "Stop failed");
                }
            }
        }
        onExited: {
            root.gen++;
            root.busy = false;
        }
    }

    Process {
        id: pauseProc
        command: ["bash", root.helper, "pause", "--run-dir", root.runDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = root.parse(this.text);
                if (o && o.ok === true) root.paused = o.paused !== undefined ? o.paused === true : !root.paused;
                else root.lastError = root.replyError(o, this.text, "Pause failed");
            }
        }
    }

    Process {
        id: statusProc
        command: ["bash", root.helper, "status", "--run-dir", root.runDir]
        stdout: StdioCollector { onStreamFinished: root.applyStatus(this.text) }
    }
    function refreshStatus() {
        if (statusProc.running) return;
        root.pollGen = root.gen;
        statusProc.running = true;
    }

    Process {
        id: hdrProc
        command: ["kscreen-doctor", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                var names = [];
                try {
                    var d = JSON.parse(this.text);
                    var outs = (d && Array.isArray(d.outputs)) ? d.outputs : [];
                    for (var i = 0; i < outs.length; i++)
                        if (outs[i] && outs[i].enabled !== false && outs[i].hdr === true)
                            names.push("" + outs[i].name);
                } catch (e) {}
                root.hdrOutputs = names;
                root.hdrProbed = true;
            }
        }
    }

    // An external stop (gsr-cli, a crash) has to clear the pill.
    Timer { interval: 2000; repeat: true; running: root.recording; onTriggered: root.refreshStatus() }
    Timer { interval: 1000; repeat: true; running: root.recording; onTriggered: root.tick() }

    Component.onCompleted: {
        root.refreshStatus();
        root.refreshHdr();
    }
}
