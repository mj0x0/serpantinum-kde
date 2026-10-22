pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caps/num lock from sysfs LEDs, OR-ed across keyboards. LED attributes never notify, so we poll.
Singleton {
    id: root

    readonly property bool caps: _caps
    readonly property bool num: _num
    readonly property bool available: capsPaths.length > 0 || numPaths.length > 0
    property int pollMs: 100

    property bool _caps: false
    property bool _num: false
    property var capsPaths: []
    property var numPaths: []

    function readPath(path: string): string {
        if (ledFile.path === path)
            ledFile.reload();
        else
            ledFile.path = path;
        ledFile.waitForJob();
        return ledFile.text().trim();
    }

    function anyOn(paths: var): bool {
        for (const p of paths) {
            if (root.readPath(p) === "1")
                return true;
        }
        return false;
    }

    function poll(): void {
        const c = root.anyOn(root.capsPaths);
        if (c !== root._caps)
            root._caps = c;
        const n = root.anyOn(root.numPaths);
        if (n !== root._num)
            root._num = n;
    }

    function discover(): void {
        discoverProc.running = false;
        discoverProc.running = true;
    }

    Process {
        id: discoverProc
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock/brightness /sys/class/leds/*::numlock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const caps = [];
                const num = [];
                for (const line of this.text.split("\n")) {
                    const p = line.trim();
                    if (p.endsWith("::capslock/brightness"))
                        caps.push(p);
                    else if (p.endsWith("::numlock/brightness"))
                        num.push(p);
                }
                root.capsPaths = caps;
                root.numPaths = num;
                if (root.available)
                    root.poll();
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.discover()
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root.available
        onTriggered: root.poll()
    }

    FileView { id: ledFile; blockLoading: true; printErrors: false }
}
