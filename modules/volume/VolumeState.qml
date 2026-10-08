// VolumeState — open/closed state for the audio panel.
pragma Singleton
import "../popups"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "volume"

    // Screen centre of the TopBar volume pill, published by the bar so the
    // panel can open beside it on vertical bars. -1 until reported.
    property real iconCenterX: -1
    property real iconCenterY: -1

    // "outputs" | "inputs" | "apps" — remembered across opens.
    property string tab: "outputs"

    function toggle() { Popups.toggle("volume") }
    function show()   { Popups.show("volume") }
    function hide()   { Popups.hideIf("volume") }
    function openTab(t) {
        if (t === "outputs" || t === "inputs" || t === "apps") tab = t;
        Popups.show("volume");
    }
}
