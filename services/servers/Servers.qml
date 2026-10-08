// The self-hosted services behind the Network panel's Servers tab, from helpers/servers.py:
// docker containers, the systemd units named in settings, and listening ports the helper can
// attribute. Every mutating call goes through that helper, so there is one place to audit.
pragma Singleton

import "../../modules/network"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // shellDir is a file:// URL; a command needs a plain path.
    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/servers.py"

    // --- model ------------------------------------------------------------------

    // [{ id, kind: "docker"|"user"|"system", name, state: "running"|"stopped"|"failed"|"unknown",
    //    ports: [int], detail, canStop, portSource }]
    property var servers: []
    property bool loading: false
    property bool started: false        // false until a list has come back at least once
    property string lastError: ""

    readonly property int count: root.servers.length
    readonly property int runningCount: {
        var n = 0;
        for (var i = 0; i < root.servers.length; i++)
            if (root.servers[i].state === "running")
                n++;
        return n;
    }

    // --- polling ----------------------------------------------------------------

    property int activeConsumers: 0
    function registerConsumer() { root.activeConsumers++; }
    function unregisterConsumer() { root.activeConsumers = Math.max(0, root.activeConsumers - 1); }

    // The panel sitting on its own tab is the usual reader; the counter is for anything
    // else that wants the list without the panel being open.
    readonly property bool watching:
        root.activeConsumers > 0 || (NetworkState.wanted && NetworkState.tab === "servers")

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.watching
        onTriggered: root.refresh()
    }

    // A stop or start lands a moment after the helper returns.
    Timer { id: settle; interval: 1200; onTriggered: root.refresh() }

    // Nothing left running behind a closed panel: a helper that wedged on an unresponsive
    // dockerd would otherwise outlive the tab that asked for it.
    onWatchingChanged: {
        if (!root.watching && listProc.running) {
            listProc.stale = true;
            listProc.running = false;
            root.loading = false;
        }
    }

    // The last line, not the whole stream: a traceback's useful line is its last, and the
    // panel shows this on one line.
    function lastLine(text) {
        var lines = ("" + text).split("\n");
        for (var i = lines.length - 1; i >= 0; i--)
            if (lines[i].trim() !== "")
                return lines[i].trim();
        return "";
    }

    // One list run at a time; a tick that lands on a run in flight is dropped. A settling
    // action keeps its own run, but nothing else starts behind a closed panel.
    function refresh() {
        if (listProc.running || (!root.watching && !root.acting))
            return;
        root.loading = true;
        root.listStderr = "";
        listProc.stale = false;
        listProc.running = true;
    }

    property string listStderr: ""

    Process {
        id: listProc
        property bool stale: false      // an abandoned run: its output and its exit are dropped
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: if (!listProc.stale) root.applyList(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: root.listStderr = root.lastLine(this.text)
        }
        onExited: (code, status) => {
            if (listProc.stale)
                return;
            root.loading = false;
            root.started = true;
            if (code !== 0)
                root.lastError = root.listStderr || ("The servers helper exited with code " + code + ".");
        }
    }

    // Every field is coerced here so no binding downstream can read an undefined.
    function normalise(s) {
        if (!s || typeof s !== "object")
            return null;
        var id = (s.id === undefined || s.id === null) ? "" : "" + s.id;
        var name = (s.name === undefined || s.name === null) ? "" : "" + s.name;
        if (id === "" && name === "")
            return null;

        var ports = [];
        var raw = Array.isArray(s.ports) ? s.ports : [];
        for (var i = 0; i < raw.length; i++) {
            var p = parseInt(raw[i], 10);
            if (isFinite(p) && p > 0 && p <= 65535 && ports.indexOf(p) === -1)
                ports.push(p);
        }
        ports.sort(function (a, b) { return a - b; });

        var state = "" + (s.state || "unknown");
        if (state !== "running" && state !== "stopped" && state !== "failed")
            state = "unknown";
        var kind = "" + (s.kind || "");
        if (kind !== "docker" && kind !== "user" && kind !== "system")
            kind = "";

        return {
            id: id === "" ? name : id,
            kind: kind,
            name: name === "" ? id : name,
            state: state,
            ports: ports,
            detail: (s.detail === undefined || s.detail === null) ? "" : "" + s.detail,
            // An unattributed listener has no kind, so there is nothing to act on.
            canStop: s.canStop === true && kind !== "",
            portSource: (s.portSource === undefined || s.portSource === null) ? "" : "" + s.portSource
        };
    }

    property string signature: ""

    function applyList(text) {
        var d;
        try {
            d = JSON.parse(("" + text).trim() || "null");
        } catch (e) {
            root.lastError = "The servers helper returned unreadable output.";
            return;
        }
        if (!d || !Array.isArray(d.servers)) {
            root.lastError = "The servers helper returned no list.";
            return;
        }

        var out = [];
        for (var i = 0; i < d.servers.length; i++) {
            var row = root.normalise(d.servers[i]);
            if (row)
                out.push(row);
        }
        // By name, not by state: a row must not jump up the list the moment it is stopped.
        out.sort(function (a, b) {
            var an = a.name.toLowerCase(), bn = b.name.toLowerCase();
            if (an !== bn)
                return an < bn ? -1 : 1;
            return a.kind < b.kind ? -1 : (a.kind > b.kind ? 1 : 0);
        });

        root.lastError = "";
        // Reassigning rebuilds every delegate, so an unchanged poll keeps the old array.
        var sig = JSON.stringify(out);
        if (sig === root.signature)
            return;
        root.signature = sig;
        root.servers = out;
    }

    // --- actions ----------------------------------------------------------------

    // Nothing here runs docker or systemctl itself. A system unit's stop reaches systemd over
    // D-Bus inside the helper and raises a polkit prompt the session agent answers - never sudo.
    property var busyKeys: []
    function slotFor(kind, id) { return kind + "/" + id; }
    function isBusy(kind, id) { return root.busyKeys.indexOf(root.slotFor(kind, id)) !== -1; }
    readonly property bool acting: root.busyKeys.length > 0

    function stop(kind, id)  { root.act("stop", kind, id); }
    function start(kind, id) { root.act("start", kind, id); }

    function act(verb, kind, id) {
        var k = "" + (kind || "");
        var i = "" + (id || "");
        if (k === "" || i === "" || root.isBusy(k, i))
            return;
        root.busyKeys = root.busyKeys.concat([root.slotFor(k, i)]);
        root.lastError = "";
        var proc = actor.createObject(root, {
            tag: root.slotFor(k, i),
            command: ["python3", root.helper, verb, k, i]
        });
        proc.running = true;
    }

    // One Process per action, so stopping one service does not queue behind another.
    Component {
        id: actor
        Process {
            id: ap
            property string tag: ""
            property string err: ""
            stdout: StdioCollector {}   // drained, not read: failures come back on stderr
            stderr: StdioCollector {
                onStreamFinished: ap.err = root.lastLine(this.text)
            }
            onExited: (code, status) => {
                root.busyKeys = root.busyKeys.filter(function (s) { return s !== ap.tag; });
                if (code !== 0)
                    root.lastError = ap.err || ("The servers helper exited with code " + code + ".");
                root.refresh();
                settle.restart();
                ap.destroy();
            }
        }
    }
}
