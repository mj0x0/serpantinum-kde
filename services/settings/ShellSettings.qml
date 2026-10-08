pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User knobs from ~/.config/quickshell/settings.json; the dir is watched for live edits.
// pragma Singleton must be the FIRST line and the Singleton takes no id:.
Singleton {
    // Not named `data`: that is the built-in default-property list every QML
    // object already has, and assigning to it silently fails as read-only.
    property var cfg: ({})

    // Dotted lookup: value("cheatsheet.superKey", "arch").
    function value(path, fallback) {
        var cur = cfg;
        var parts = ("" + path).split(".");
        for (var i = 0; i < parts.length; i++) {
            if (cur === null || typeof cur !== "object" || cur[parts[i]] === undefined)
                return fallback;
            cur = cur[parts[i]];
        }
        return cur;
    }

    readonly property string writer:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/settings-write.py"

    // cfg is never assigned here (the watcher reloads it). Writes run one at a time on the
    // newest snapshot, so a slider burst cannot land out of order or clobber another key.
    property var pendingCfg: null
    property string queuedJson: ""

    function setValue(path, val) {
        var next;
        try { next = JSON.parse(JSON.stringify(pendingCfg || cfg || {})); } catch (e) { next = ({}); }
        var parts = ("" + path).split(".");
        var cur = next;
        for (var i = 0; i < parts.length - 1; i++) {
            if (cur[parts[i]] === null || typeof cur[parts[i]] !== "object")
                cur[parts[i]] = ({});
            cur = cur[parts[i]];
        }
        cur[parts[parts.length - 1]] = val;
        pendingCfg = next;
        // JSON on argv, not through a shell string: no quoting to get wrong.
        var json = JSON.stringify(next);
        if (writeProc.running) { queuedJson = json; return; }
        writeProc.command = ["python3", writer, json];
        writeProc.running = true;
    }

    Process {
        id: writeProc
        onExited: {
            if (queuedJson === "") return;
            command = ["python3", writer, queuedJson];
            queuedJson = "";
            running = true;
        }
    }
    // Once the file has caught up with the last write, it is the source of truth again.
    onCfgChanged: if (!writeProc.running && queuedJson === "") pendingCfg = null

    // Distro logos beat the word Super; codepoints checked by glyph NAME in Iosevka.
    readonly property var superKeyPresets: ({
        "arch":    "\u{f303}",     // linux-archlinux
        "tux":     "\u{f31a}",     // linux-tux
        "windows": "\u{f05b3}",    // md-microsoft_windows
        "apple":   "\u{f0035}",    // md-apple
        "text":    "",             // spell it out
    })

    readonly property string superKeyName: {
        var v = value("cheatsheet.superKey", "arch");
        return (typeof v === "string" && v !== "") ? v : "arch";
    }

    // "" means render the word instead. An unknown name is taken as a literal
    // glyph, so someone can drop in their own distro without a code change.
    readonly property string superKeyGlyph: {
        var p = superKeyPresets[superKeyName];
        return p !== undefined ? p : superKeyName;
    }

    // OFF by default: polkit allows ONE agent per session, so enabling EVICTS KDE's.
    // Enable in settings.json, then mask plasma-polkit-agent. DISABLE_POLKIT=1 forces off.
    readonly property bool polkitEnabled:
        Quickshell.env("DISABLE_POLKIT") === "1"
        ? false
        : value("polkit.enabled", false) === true

    // One directory holds images and videos; two knobs so videos can live on another disk.
    readonly property string wallpaperDir:
        expandHome(value("wallpaper.imageDir", "~/Pictures/Wallpapers"))
    readonly property string wallpaperVideoDir:
        expandHome(value("wallpaper.videoDir", "~/Pictures/Wallpapers"))
    // Empty follows imageDir at read time, so moving Images moves the downloads with it.
    readonly property string wallhavenDir:
        expandHome(("" + (value("wallpaper.wallhaven.dir", "") || "")).trim()
                   || value("wallpaper.imageDir", "~/Pictures/Wallpapers"))
    readonly property bool wallhavenApplyOnDownload:
        value("wallpaper.wallhaven.applyOnDownload", false) === true
    readonly property string pickerStyle: "" + value("wallpaper.pickerStyle", "slices")
    readonly property string handMove: "" + value("wallpaper.handMove", "random")
    readonly property int handCardSize: Math.max(50, Math.min(200, Number(value("wallpaper.hand.cardSize", 100)) || 100))
    readonly property int wallColumns: Math.max(3, Math.min(8, Number(value("wallpaper.wall.columns", 5)) || 5))
    readonly property bool previewShader: value("wallpaper.preview.shader", true) !== false
    readonly property bool previewName: value("wallpaper.preview.name", true) !== false
    readonly property bool previewColors: value("wallpaper.preview.colors", true) !== false

    function expandHome(p) {
        var str = "" + (p || "");
        if (str.indexOf("~/") === 0)
            return Quickshell.env("HOME") + str.substring(1);
        return str;
    }

    Process {
        id: loader
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/settings.json\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var m = JSON.parse((this.text && this.text.trim()) ? this.text : "{}");
                    cfg = (m && typeof m === "object") ? m : ({});
                } catch (e) {
                    cfg = ({});
                }
            }
        }
    }
    Process {
        id: watcher
        running: true
        command: ["sh", "-c", "D=\"$HOME/.config/quickshell\"; mkdir -p \"$D\"; setpriv --pdeathsig KILL inotifywait -qq -e close_write,create,moved_to \"$D\" 2>/dev/null || sleep 3"]
        onExited: {
            loader.running = false;  loader.running = true;
            watcher.running = false; watcher.running = true;
        }
    }
}
