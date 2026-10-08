import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io
import "WindowRegistry.js" as LayoutMath

Item {
    id: root
    visible: false

    property real currentWidth: 1920.0
    property real currentHeight: 1080.0 // <-- ADDED
    // uiScale comes from ShellSettings, watched once for the whole shell. It used to be a
    // per-Scaler bash watcher polling for a file a KDE port never creates - 14 of them.
    property real uiScale: ShellSettings.value("ui.scale", 1.0)


    // FIXED: Now passes both Width and Height to respect aspect ratio
    property real baseScale: LayoutMath.getScale(currentWidth, currentHeight, uiScale)
    
    function s(val) { 
        return LayoutMath.s(val, baseScale); 
    }

}
