// Current wallpaper, owned by us rather than read back out of plasmashell.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateFile: home + "/.local/state/quickshell/wallpaper/current"
    readonly property string thumbDir: home + "/.cache/quickshell/wallpaper_picker/thumbs"

    readonly property var videoExts: ["mp4", "mkv", "mov", "webm"]

    // Absolute path of the wallpaper. One line of plain text on disk, which is
    // also the shape matugen/KMY's `file=` option reads, so the same file can
    // drive theming without a second source of truth.
    property string current: ""
    readonly property bool isVideo: root.extOf(root.current) !== ""
                                    && root.videoExts.indexOf(root.extOf(root.current)) >= 0

    function extOf(p) {
        var s = String(p);
        var i = s.lastIndexOf(".");
        return i < 0 ? "" : s.substring(i + 1).toLowerCase();
    }

    function baseOf(p) {
        var s = String(p);
        var i = s.lastIndexOf("/");
        return i < 0 ? s : s.substring(i + 1);
    }

    // A still that represents this wallpaper: the image itself, or the video's
    // thumbnail. wallpaper-thumbs.sh prefixes video thumbs with 000_.
    readonly property string still: root.current === "" ? ""
        : (root.isVideo ? root.thumbDir + "/000_" + root.baseOf(root.current)
                        : root.current)

    // set-wallpaper.py hands the file to our Plasma wallpaper plugin, which does the
    // transition itself, then fires the theming hook.
    readonly property string setter:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/set-wallpaper.py"

    function apply(path) {
        if (path) Quickshell.execDetached(["python3", root.setter, path]);
    }

    FileView {
        id: stateView
        path: root.stateFile
        watchChanges: true
        onLoaded: root.current = (stateView.text() || "").trim().replace(/^file:\/\//, "")
        onFileChanged: stateView.reload()
    }
}
