pragma Singleton

import "../../modules/notifcenter"
import QtQuick
import Quickshell
import Quickshell.Io

// KDE Connect phone state from the local daemon via helpers/kdeconnect.sh (qdbus6).
// 8s poll as a floor plus a gdbus watcher; we re-read rather than parse the signal.
Singleton {
    readonly property string scriptsDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    property bool   online: false
    property string deviceId: ""
    property string deviceName: ""
    property int    charge: -1
    property bool   charging: false
    property string sigType: ""
    property int    sigStrength: -1

    // Only poll/watch while the notification center is actually open.
    readonly property bool activeGate: NotifCenterState.open

    function refresh() { fetchProc.running = false; fetchProc.running = true; }

    Process {
        id: fetchProc
        command: ["bash", scriptsDir + "/kdeconnect.sh", "--once"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try { d = JSON.parse((this.text || "").trim() || "{}"); } catch (e) { d = {}; }
                if (d.state === "online") {
                    online = true;
                    deviceId = d.id || "";
                    deviceName = d.name || "Phone";
                    charge = (typeof d.charge === "number") ? d.charge : -1;
                    charging = !!d.charging;
                    sigType = d.sigType || "";
                    sigStrength = (typeof d.sigStrength === "number") ? d.sigStrength : -1;
                } else {
                    online = false;
                }
            }
        }
    }

    // Polling floor while open (triggeredOnStart → immediate fetch on open).
    Timer {
        interval: 8000; repeat: true
        running: activeGate
        triggeredOnStart: true
        onTriggered: refresh()
    }

    // Event trigger: any KDE Connect DBus signal → debounced re-fetch.
    Process {
        id: watchProc
        running: activeGate
        command: ["bash", scriptsDir + "/kdeconnect.sh", "--watch"]
        stdout: SplitParser { onRead: (line) => debounce.restart() }
    }
    Timer { id: debounce; interval: 350; onTriggered: refresh() }

    // Present a clean state the instant the center closes.
    onActiveGateChanged: if (!activeGate) online = false;

    // --- Actions -------------------------------------------------------------
    function ring()          { if (deviceId) Quickshell.execDetached(["bash", scriptsDir + "/kdeconnect.sh", "ring", deviceId]); }
    function sendClipboard() { if (deviceId) Quickshell.execDetached(["bash", scriptsDir + "/kdeconnect.sh", "send-clipboard", deviceId]); }
    function browse()        { if (deviceId) Quickshell.execDetached(["bash", scriptsDir + "/kdeconnect.sh", "browse", deviceId]); }
    function ping()          { if (deviceId) Quickshell.execDetached(["bash", scriptsDir + "/kdeconnect.sh", "ping", deviceId]); }
}
