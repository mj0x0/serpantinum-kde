// In-process preview through Colors.preview*; a commit holds it until colors.json catches up.
pragma Singleton

import "ThemeDerive.js" as Derive
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string shown: ""
    property string committed: ""
    property var matugen: null

    FileView {
        id: matugenFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors-matugen.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.matugen = JSON.parse(matugenFile.text()); } catch (e) { root.matugen = null; }
        }
        onLoadFailed: root.matugen = null
    }

    Timer {
        id: fallback
        interval: 20000
        onTriggered: root.settle()
    }

    Connections {
        target: Colors
        function onFileLoaded() {
            if (root.committed !== "" && Colors.fileTheme.name === root.committed) root.settle();
        }
    }

    function show(t) {
        if (!t || !t.colors) return;
        var data;
        try { data = Derive.fromTheme(t.id, t.colors); } catch (e) { return; }
        apply(data);
        Colors.previewing = true;
        shown = "" + t.id;
    }

    function showMatugen() {
        if (!root.matugen || typeof root.matugen !== "object") { clear(); return; }
        apply(Derive.fromGenerated(root.matugen));
        Colors.previewing = true;
        shown = "matugen";
    }

    function clear() {
        Colors.previewing = false;
        shown = "";
    }

    function commit(id) {
        committed = "" + id;
        fallback.restart();
    }

    function settle() {
        var id = committed;
        committed = "";
        fallback.stop();
        // A preview of some other theme stays up for the picker to drive.
        if (shown === "" || shown === id) clear();
    }

    function apply(data) {
        assign(Colors.previewTheme, data.theme);
        assign(Colors.previewMd3, data.md3);
        assign(Colors.previewPalette, data.palette);
        assign(Colors.previewBase16, data.base16);
        var named = data.named || {};
        if (Object.keys(named).length === 0) {
            for (var i = 0; i < Derive.ROLES.length; i++) Colors.previewNamed[Derive.ROLES[i]] = "transparent";
        } else {
            assign(Colors.previewNamed, named);
        }
    }

    function assign(obj, src) {
        if (!src) return;
        for (var k in src) if (obj[k] !== undefined) obj[k] = src[k];
    }
}
