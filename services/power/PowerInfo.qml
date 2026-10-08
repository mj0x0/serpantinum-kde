// Power posture from helpers/power-watch.py: the profile, and which apps hold the machine awake.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property string profile: ""
    property var choices: []
    property var holds: []
    property string degraded: ""
    property var inhibitions: []      // [{ who, why, granted, asking }]
    property bool screenBlocked: false
    property bool sleepBlocked: false

    readonly property int activeCount: inhibitions.filter(i => i.granted).length
    readonly property int blockedCount: inhibitions.length - activeCount

    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/power-watch.py"

    function setProfile(p) {
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.Solid.PowerManagement",
            "/org/kde/Solid/PowerManagement/Actions/PowerProfile",
            "org.kde.Solid.PowerManagement.Actions.PowerProfile", "setProfile", "s", p]);
    }

    // PowerDevil persists this to powerdevilrc: a block survives relogs until allowed again.
    function setAllowed(who, why, allowed) {
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.Solid.PowerManagement",
            "/org/kde/Solid/PowerManagement/PolicyAgent",
            "org.kde.Solid.PowerManagement.PolicyAgent", "SetInhibitionAllowed", "ssb",
            who, why, allowed ? "true" : "false"]);
    }

    Process {
        id: watcher
        running: true
        command: ["python3", "-W", "ignore", root.helper]
        stdout: SplitParser {
            onRead: line => {
                var s;
                try { s = JSON.parse(line); } catch (e) { return; }
                root.available = s.available === true;
                root.profile = s.profile || "";
                root.choices = s.choices || [];
                root.holds = s.holds || [];
                root.degraded = s.degraded || "";
                root.inhibitions = s.inhibitions || [];
                root.screenBlocked = s.screen === true;
                root.sleepBlocked = s.sleep === true;
            }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 3000; onTriggered: watcher.running = true }
}
