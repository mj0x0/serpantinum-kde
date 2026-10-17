pragma Singleton

import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

// Leak instrumentation. Off unless debug.memProbe is true in settings.json; every entry
// point returns immediately when disabled so call sites stay free in normal runs.
Singleton {
    id: root

    readonly property bool enabled: ShellSettings.value("debug.memProbe", false) === true
    readonly property int intervalSec: Math.max(5, ShellSettings.value("debug.memProbeInterval", 30))

    // kind -> { key: label }; a key that is never untracked is the leak.
    property var live: ({})
    property var createdCount: ({})
    property var destroyedCount: ({})
    // free-form event counters, reported as totals and per-interval deltas
    property var counters: ({})
    property var lastCounters: ({})
    property int lastRss: 0
    property int ticks: 0

    function track(kind, key, label) {
        if (!enabled) return;
        if (!live[kind]) live[kind] = {};
        live[kind][String(key)] = label || "";
        createdCount[kind] = (createdCount[kind] || 0) + 1;
        console.log("[memprobe] +" + kind + " " + key + " " + (label || ""));
    }

    function untrack(kind, key) {
        if (!enabled) return;
        if (live[kind]) delete live[kind][String(key)];
        destroyedCount[kind] = (destroyedCount[kind] || 0) + 1;
        console.log("[memprobe] -" + kind + " " + key);
    }

    function bump(name, n) {
        if (!enabled) return;
        counters[name] = (counters[name] || 0) + (n || 1);
    }

    function liveCount(kind) {
        if (!live[kind]) return 0;
        return Object.keys(live[kind]).length;
    }

    function liveBreakdown(kind) {
        if (!live[kind]) return "{}";
        const byLabel = {};
        const keys = Object.keys(live[kind]);
        for (let i = 0; i < keys.length; i++) {
            const label = live[kind][keys[i]] || "?";
            byLabel[label] = (byLabel[label] || 0) + 1;
        }
        return JSON.stringify(byLabel);
    }

    function deltas() {
        const out = {};
        const names = Object.keys(counters);
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const d = counters[n] - (lastCounters[n] || 0);
            if (d !== 0) out[n] = d;
            lastCounters[n] = counters[n];
        }
        return out;
    }

    function fmtKb(kb) {
        return (kb / 1024).toFixed(1) + "M";
    }

    function statusField(text, field) {
        const m = text.match(new RegExp("^" + field + ":\\s+(\\d+)", "m"));
        return m ? parseInt(m[1], 10) : 0;
    }

    function sample() {
        if (!enabled) return;
        statusFile.reload();
        statusFile.waitForJob();
        const text = statusFile.text();
        if (!text) return;

        const rss = statusField(text, "VmRSS");
        const delta = lastRss > 0 ? rss - lastRss : 0;
        lastRss = rss;
        ticks += 1;

        console.log("[memprobe] tick=" + ticks + " interval=" + intervalSec + "s"
            + " rss=" + fmtKb(rss) + " d=" + (delta >= 0 ? "+" : "") + fmtKb(delta)
            + " anon=" + fmtKb(statusField(text, "RssAnon"))
            + " file=" + fmtKb(statusField(text, "RssFile"))
            + " shm=" + fmtKb(statusField(text, "RssShmem"))
            + " vmsize=" + fmtKb(statusField(text, "VmSize"))
            + " threads=" + statusField(text, "Threads")
            + " | widgets=" + liveCount("widget") + " " + liveBreakdown("widget")
            + " net=" + ((createdCount["widget"] || 0) - (destroyedCount["widget"] || 0))
            + " (c" + (createdCount["widget"] || 0) + "/d" + (destroyedCount["widget"] || 0) + ")"
            + " | loaders=" + liveCount("loader")
            + " | events=" + JSON.stringify(deltas()));
    }

    FileView {
        id: statusFile
        path: "/proc/self/status"
        blockLoading: true
        printErrors: false
    }

    Timer {
        running: root.enabled
        interval: root.intervalSec * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    IpcHandler {
        target: "memprobe"
        function dump(): string {
            root.sample();
            return JSON.stringify({
                enabled: root.enabled,
                rssKb: root.lastRss,
                widgets: root.live["widget"] || {},
                loaders: root.live["loader"] || {},
                created: root.createdCount,
                destroyed: root.destroyedCount,
                counters: root.counters
            }, null, 2);
        }
    }
}
