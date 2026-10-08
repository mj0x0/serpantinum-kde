// Thin on purpose: WallpaperPicker owns listing, thumbnails and colour extraction.
pragma Singleton
import "../popups"

import "../../services/settings"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool open: Popups.current === "wallpaper"

    function toggle() { if (!open) prep(); Popups.toggle("wallpaper") }
    function show()   { prep(); Popups.show("wallpaper") }
    function hide()   { Popups.hideIf("wallpaper") }

    // The picker lists the THUMBNAIL directory, so without this it opens empty (upstream
    // did it in qs_manager.sh). Manifest-guarded, and fired on open rather than at startup.
    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    property bool preparing: false

    function prep() {
        if (thumbProc.running) return;
        preparing = true;
        thumbProc.running = true;
    }

    Process {
        id: thumbProc
        command: ["bash", root.helper + "/wallpaper-thumbs.sh",
                  ShellSettings.wallpaperDir]
        onExited: root.preparing = false
    }
}
