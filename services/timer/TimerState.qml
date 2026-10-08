// The quick-action timer's running state, published by modules/floating/quickactions/Timer.qml
// so the bar's info widget can show it. Raw epochs in, a once-a-second readout out.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property int mode: 0                 // 0 timer, 1 stopwatch, 2 pomodoro (the card's active tab)
    property real timerTargetEpoch: 0
    property int timerRemainingMs: 0
    property real swStartEpoch: 0
    property int swAccumulatedMs: 0
    property real pomoTargetEpoch: 0
    property int pomoState: 0            // 0 work, 1 short break, 2 long break

    readonly property bool timerRunning: timerTargetEpoch > 0
    readonly property bool swRunning: swStartEpoch > 0
    readonly property bool pomoRunning: pomoTargetEpoch > 0
    readonly property bool active: timerRunning || swRunning || pomoRunning

    // The running one, preferring whatever tab the card shows.
    readonly property int shownMode: (mode === 0 && timerRunning) || (mode === 1 && swRunning) || (mode === 2 && pomoRunning)
        ? mode : (timerRunning ? 0 : (swRunning ? 1 : 2))

    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: root.active; triggeredOnStart: true; onTriggered: root.now = Date.now() }

    readonly property int ms: {
        if (!active) return 0;
        if (shownMode === 0) return Math.max(0, timerTargetEpoch - now);
        if (shownMode === 1) return Math.max(0, swAccumulatedMs + (now - swStartEpoch));
        return Math.max(0, pomoTargetEpoch - now);
    }
    readonly property string text: {
        var s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        var out = h > 0 ? String(h).padStart(2, "0") + ":" : "";
        return out + String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0");
    }
    readonly property string icon: shownMode === 0 ? "\u{f051b}" : (shownMode === 1 ? "\u{f051f}" : "\u{f0176}")
    // Palette role name; the widget resolves it.
    readonly property string tone: shownMode === 0 ? "blue" : (shownMode === 1 ? "green" : (pomoState === 0 ? "peach" : "green"))
}
