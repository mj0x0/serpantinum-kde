pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Per-app tray icon overrides, keyed by SNI id or title, from a live-watched
// ~/.config/quickshell/tray-icons.json. Value = glyph, or { glyph, font?, color? }.
Singleton {
    property var map: ({})

    function reparse(txt) {
        try {
            var m = JSON.parse((txt && txt.trim()) ? txt : "{}");
            map = (m && typeof m === "object") ? m : ({});
        } catch (e) {
            map = ({});
        }
    }

    function lookup(id, title) {
        var m = map;
        if (!m) return null;
        var v = (id !== undefined && m[id] !== undefined) ? m[id]
              : (title !== undefined && m[title] !== undefined) ? m[title]
              : undefined;
        if (v === undefined) {
            var lid = (id || "").toLowerCase(), lt = (title || "").toLowerCase();
            for (var k in m) {
                var lk = k.toLowerCase();
                if (lk === lid || (lt && lk === lt)) { v = m[k]; break; }
            }
        }
        if (v === undefined || v === null) return null;
        if (typeof v === "string") return { glyph: v, font: "", color: "" };
        return { glyph: v.glyph || v.icon || "", font: v.font || "", color: v.color || "" };
    }

    readonly property string writer:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/settings-write.py"

    // map is never assigned here (the watcher reloads it); writes queue like ShellSettings'.
    // Empty glyph removes the entry; `font` is kept; a bare glyph stays a plain string.
    property var pendingMap: null
    property string queuedJson: ""
    onMapChanged: if (!writeProc.running && queuedJson === "") pendingMap = null

    function setEntry(key, glyph, color) {
        if (!key) return;
        var base = pendingMap || map;
        var next = {};
        for (var k in base) next[k] = base[k];

        var g = ("" + (glyph || "")).trim();
        if (g === "") {
            delete next[key];
        } else {
            var old = base[key];
            var font = (old && typeof old === "object" && old.font) ? old.font : "";
            var c = ("" + (color || "")).trim();
            next[key] = (c === "" && font === "")
                      ? g
                      : { glyph: g, color: c, font: font };
        }
        pendingMap = next;
        var json = JSON.stringify(next);
        if (writeProc.running) { queuedJson = json; return; }
        writeProc.command = ["python3", writer, json, "--file", "tray-icons.json"];
        writeProc.running = true;
    }

    Process {
        id: writeProc
        onExited: {
            if (queuedJson === "") return;
            command = ["python3", writer, queuedJson, "--file", "tray-icons.json"];
            queuedJson = "";
            running = true;
        }
    }

    Process {
        id: loader
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/tray-icons.json\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: reparse(this.text) }
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
