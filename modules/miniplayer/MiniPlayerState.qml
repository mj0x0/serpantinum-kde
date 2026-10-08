pragma Singleton

// The mini player's popout: hovering or clicking the bar widget opens it; leaving both closes it after a beat.
import QtQuick

Item {
    property bool open: false
    property real anchorX: 0
    property real anchorY: 0
    property var screen: null
    property bool widgetHovered: false
    property bool cardHovered: false
    property bool holding: false

    Timer {
        id: hideTimer
        interval: 500
        onTriggered: closeIfIdle()
    }

    function closeIfIdle() { if (!widgetHovered && !cardHovered && !holding) open = false; }
    function place(x, y, scr) { anchorX = x; anchorY = y; screen = scr; }
    function enter(x, y, scr) { widgetHovered = true; hideTimer.stop(); place(x, y, scr); open = true; }
    function leave() { widgetHovered = false; requestHide(); }
    function requestHide() { if (!widgetHovered && !cardHovered && !holding) hideTimer.restart(); }
    function cancelHide() { hideTimer.stop(); }
    function toggle(x, y, scr) {
        if (open) { hide(); return; }
        place(x, y, scr);
        open = true;
    }
    function hide() { hideTimer.stop(); open = false; }
}
