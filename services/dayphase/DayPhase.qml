pragma Singleton

import QtQuick
import Quickshell

// Which quarter of the day it is, for widgets that tint by the clock. A singleton so
// short-lived panels need no Timer of their own, and the shell shifts mood as one.
Singleton {
    // 0 morning · 1 afternoon · 2 evening · 3 night
    property int phase: 3
    readonly property var names: ["Morning", "Afternoon", "Evening", "Night"]
    readonly property string name: names[phase]

    function recompute() {
        var h = new Date().getHours();
        phase = (h >= 5 && h < 12) ? 0
              : (h >= 12 && h < 17) ? 1
              : (h >= 17 && h < 21) ? 2
              : 3;
    }

    Component.onCompleted: recompute()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: recompute() }
}
