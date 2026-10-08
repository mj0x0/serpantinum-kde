// Shared FFT levels from cava, ported from serpantinum v2 (AGPL-3.0, see NOTICE).
// A singleton so one process can feed several widgets, refcounted by consumer.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int barCount: 64
    property var barLevels: {
        let arr = [];
        for (let i = 0; i < barCount; i++) arr.push(0.0);
        return arr;
    }

    // Bound by whoever knows the player state (MusicPopup does it).
    property bool isPlaying: false

    property int activeConsumers: 0
    property bool isRestarting: false
    readonly property bool processEnabled: activeConsumers > 0
                                        && (isPlaying || decayTimer.running)
                                        && !isRestarting

    function registerConsumer() { activeConsumers++; }
    function unregisterConsumer() { activeConsumers = Math.max(0, activeConsumers - 1); }

    function resetBars() {
        let empty = [];
        for (let i = 0; i < root.barCount; i++) empty.push(0.0);
        root.barLevels = empty;
    }

    function restartCava() {
        if (!processEnabled) return;
        isRestarting = true;
        restartTimer.restart();
    }

    onIsPlayingChanged: {
        if (isPlaying) decayTimer.stop();
        else if (activeConsumers > 0) decayTimer.restart();
        else resetBars();
    }

    onProcessEnabledChanged: if (!processEnabled) resetBars();

    // Keeps cava alive a moment past pause so the bars fall instead of snapping.
    Timer { id: decayTimer; interval: 1000; repeat: false }

    Timer { id: restartTimer; interval: 500; repeat: false; onTriggered: root.isRestarting = false }

    // cava can wedge and stop emitting while still running; nothing else notices.
    Timer {
        id: dataWatchdog
        interval: 2000
        running: cavaProcess.running && root.isPlaying
        repeat: false
        onTriggered: root.restartCava()
    }

    Process {
        id: cavaProcess
        running: root.processEnabled
        onExited: root.restartCava()
        // Config is generated inline rather than read from a file, so bar count
        // and range stay in step with the parsing below.
        command: [
            "bash", "-c",
            "cava -p <(printf '[general]\\nbars = %d\\nframerate = 60\\nsensitivity = 150\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 1000\\nbar_delimiter = 59\\n' " + root.barCount + ")"
        ]
        stdout: SplitParser {
            onRead: data => {
                dataWatchdog.restart();
                let str = data.trim();
                if (str.length === 0) return;
                let parts = str.split(";");
                let count = Math.min(parts.length, root.barCount);
                let newLevels = [];
                for (let i = 0; i < root.barCount; i++) {
                    let val = i < count ? (parseInt(parts[i]) || 0) : 0;
                    newLevels.push(Math.max(0.0, Math.min(1.0, val / 1000.0)));
                }
                root.barLevels = newLevels;
            }
        }
    }
}
