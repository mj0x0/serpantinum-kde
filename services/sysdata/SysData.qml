// Centralized system stats, refcounted so it only reads while subscribed.
// cpu/ram/net/temp are read straight from /proc and sysfs; disk is the one fork left (df, 60 s).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // --- Centralized Properties ---
    property int cpu: 0
    property int ramPercent: 0
    property real ramGb: 0.0
    property int temp: 0
    property real netRx: 0
    property real netTx: 0
    property int diskPercent: 0
    property real diskGb: 0.0
    property real diskTotalGb: 0.0

    // --- Lifecycle Management ---
    property int subscribers: 0

    // --- Delta baselines ---
    property real prevTotal: -1
    property real prevIdle: 0
    property real prevRx: -1
    property real prevTx: 0
    property real prevAt: 0
    property string iface: ""
    property string tempPath: ""
    property bool tempScanned: false

    function subscribe() {
        subscribers++;
        if (subscribers === 1) {
            sample();
            diskProc.running = true;
            firstSample.restart();
            sampleTimer.start();
            diskTimer.start();
        }
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        if (subscribers === 0) {
            sampleTimer.stop();
            diskTimer.stop();
        }
    }

    function fields(line: string): var {
        return line.split("\t").join(" ").split(" ").filter(s => s.length > 0);
    }

    function read(view: FileView): string {
        view.reload();
        view.waitForJob();
        return view.text();
    }

    // One view can serve many paths, but only if each read waits for its own job.
    function readPath(path: string): string {
        probeFile.path = path;
        probeFile.waitForJob();
        return probeFile.text().trim();
    }

    function findTempPath(): string {
        for (let i = 0; i < 32; i++) {
            const dir = "/sys/class/hwmon/hwmon" + i;
            const name = root.readPath(dir + "/name");
            if (name !== "k10temp" && name !== "zenpower" && name !== "coretemp")
                continue;
            for (let t = 1; t <= 9; t++) {
                const label = root.readPath(dir + "/temp" + t + "_label");
                if (label === "Tctl" || label === "Tdie" || label.startsWith("Package"))
                    return dir + "/temp" + t + "_input";
            }
            return dir + "/temp1_input";
        }
        return "";
    }

    function sample(): void {
        const now = Date.now();
        const dt = root.prevAt > 0 ? (now - root.prevAt) / 1000 : 0;
        root.prevAt = now;

        const c = root.fields(root.read(statFile).split("\n")[0]);
        if (c.length >= 9) {
            const idle = Number(c[4]) + Number(c[5]);
            const total = idle + Number(c[1]) + Number(c[2]) + Number(c[3]) + Number(c[6]) + Number(c[7]) + Number(c[8]);
            const dTotal = total - root.prevTotal;
            if (root.prevTotal >= 0 && dTotal > 0)
                root.cpu = Math.max(0, Math.min(100, Math.round(100 * (dTotal - (idle - root.prevIdle)) / dTotal)));
            root.prevTotal = total;
            root.prevIdle = idle;
        }

        let memTotal = 0;
        let memAvail = 0;
        for (const line of root.read(memFile).split("\n")) {
            if (line.startsWith("MemTotal:")) {
                memTotal = Number(root.fields(line)[1]);
            } else if (line.startsWith("MemAvailable:")) {
                memAvail = Number(root.fields(line)[1]);
                break;
            }
        }
        if (memTotal > 0) {
            root.ramPercent = Math.round(100 * (memTotal - memAvail) / memTotal);
            root.ramGb = (memTotal - memAvail) / 1048576;
        }

        if (!root.tempScanned) {
            root.tempPath = root.findTempPath();
            root.tempScanned = true;
        }
        if (root.tempPath !== "") {
            tempFile.path = root.tempPath;
            const v = Number(root.read(tempFile).trim());
            if (v > 0)
                root.temp = Math.round(v / 1000);
        }

        // Default route = the physical wire; a policy-routed VPN never takes it over.
        let primary = "";
        const routeLines = root.read(routeFile).split("\n");
        for (let i = 1; i < routeLines.length && primary === ""; i++) {
            const f = root.fields(routeLines[i]);
            if (f.length >= 2 && f[1] === "00000000")
                primary = f[0];
        }
        if (primary !== root.iface) {
            root.iface = primary;
            root.prevRx = -1;
        }

        let rx = -1;
        let tx = 0;
        if (root.iface !== "") {
            for (const line of root.read(devFile).split("\n")) {
                const colon = line.indexOf(":");
                if (colon < 0 || line.slice(0, colon).trim() !== root.iface)
                    continue;
                const f = root.fields(line.slice(colon + 1));
                if (f.length >= 9) {
                    rx = Number(f[0]);
                    tx = Number(f[8]);
                }
                break;
            }
        }
        if (rx < 0) {
            root.netRx = 0;
            root.netTx = 0;
            root.prevRx = -1;
        } else {
            if (root.prevRx >= 0 && dt > 0.05) {
                root.netRx = Math.max(0, (rx - root.prevRx) / dt);
                root.netTx = Math.max(0, (tx - root.prevTx) / dt);
            }
            root.prevRx = rx;
            root.prevTx = tx;
        }
    }

    Timer {
        id: sampleTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: root.sample()
    }

    // The subscribe sample only seeds the baselines; this one turns them into a reading.
    Timer {
        id: firstSample
        interval: 300
        onTriggered: root.sample()
    }

    Timer {
        id: diskTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: {
            diskProc.running = false;
            diskProc.running = true;
        }
    }

    FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
    FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
    FileView { id: routeFile; path: "/proc/net/route"; blockLoading: true; printErrors: false }
    FileView { id: devFile; path: "/proc/net/dev"; blockLoading: true; printErrors: false }
    FileView { id: tempFile; blockLoading: true; printErrors: false }
    FileView { id: probeFile; blockLoading: true; printErrors: false }

    // Nothing in QML can statvfs, so this one stays a process — once a minute, deduped by device.
    Process {
        id: diskProc
        running: false
        command: ["df", "-Plk", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "overlay", "-x", "efivarfs", "-x", "iso9660"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                let used = 0;
                let total = 0;
                const lines = this.text.split("\n");
                for (let i = 1; i < lines.length; i++) {
                    const f = root.fields(lines[i]);
                    if (f.length < 6)
                        continue;
                    const dev = f[0];
                    if (dev === "udev" || dev === "none" || dev.startsWith("/dev/loop") || seen[dev])
                        continue;
                    seen[dev] = true;
                    total += Number(f[1]);
                    used += Number(f[2]);
                }
                if (total > 0) {
                    root.diskPercent = Math.round(100 * used / total);
                    root.diskGb = used / 1048576;
                    root.diskTotalGb = total / 1048576;
                }
            }
        }
    }
}
