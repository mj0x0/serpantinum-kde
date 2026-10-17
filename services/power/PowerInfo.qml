// Power posture from power-watch (Bridge.power): the profile, and which apps hold the machine awake.
pragma Singleton

import "../bridge"
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var _s: Bridge.power || ({})

    readonly property bool available: _s.available === true
    readonly property string profile: _s.profile || ""
    readonly property var choices: _s.choices || []
    readonly property var holds: _s.holds || []
    readonly property string degraded: _s.degraded || ""
    readonly property var inhibitions: _s.inhibitions || []      // [{ who, why, granted, asking }]
    readonly property bool screenBlocked: _s.screen === true
    readonly property bool sleepBlocked: _s.sleep === true

    readonly property int activeCount: inhibitions.filter(i => i.granted).length
    readonly property int blockedCount: inhibitions.length - activeCount

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
}
