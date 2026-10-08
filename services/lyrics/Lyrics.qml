// Timed lyrics for the current track, backed by helpers/lyrics.py (network + LRC).
// This side owns the clock: MPRIS position sampled at 20 Hz, polls as the watchdog.
pragma Singleton

import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    // ---- result ------------------------------------------------------------
    property var lines: []                       // [{ t: seconds, text: "" }]
    readonly property int count: lines.length
    readonly property bool hasLyrics: count > 0
    property string backend: ""
    property string trackId: ""
    // The served lines carry word timings (lines[].words); only with wantWords.
    property bool hasWords: false
    // Line-level lyrics are up while the helper still hunts for a word-timed version.
    property bool hunting: false
    property bool loading: false
    property string reason: ""
    property var candidates: []
    property bool searching: false

    // Positive = lyrics shown later. Persisted per track by the helper, because
    // two backends' rips of the same song can differ by most of a second.
    property real offset: 0

    // ---- current track -----------------------------------------------------
    property string artist: ""
    property string title: ""
    property string album: ""
    property real duration: 0

    // "sing-along" hunts word timings and shows them when a track has any;
    // "lines" is exactly the line-level behaviour, no extra lookups.
    readonly property bool wantWords:
        ("" + ShellSettings.value("lyrics.highlight", "sing-along")) === "sing-along"
    onWantWordsChanged: if (title !== "") fetch()

    // ---- consumers ---------------------------------------------------------
    property int activeConsumers: 0
    function registerConsumer() { activeConsumers++; }
    function unregisterConsumer() { activeConsumers = Math.max(0, activeConsumers - 1); }

    // ---- clock -------------------------------------------------------------
    // playerctl's name for the player the popup shows, resolved to its MPRIS object.
    property string playerName: ""

    readonly property var player: {
        var list = Mpris.players ? Mpris.players.values : [];
        var want = "org.mpris.MediaPlayer2." + playerName;
        var playing = null, paused = null;
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (playerName !== "" && p.dbusName === want) return p;
            if (!p.lengthSupported || p.length <= 0) continue;
            if (p.isPlaying) { if (!playing) playing = p; }
            else if (!paused && p.playbackState === MprisPlaybackState.Paused) paused = p;
        }
        return playing || paused;
    }

    // Quickshell extrapolates its last D-Bus position by rate and re-reads it on seeks,
    // play-state and track changes, so player.position sampled at 20 Hz is the clock.
    readonly property bool mprisClock: player !== null && player.positionSupported
    property bool polledPlaying: false
    readonly property bool playing: player !== null ? player.isPlaying : polledPlaying
    property real position: 0

    // Polls that keep disagreeing with MPRIS mean a stall or an unsignalled seek; the
    // difference rides on top of MPRIS until the next real position event clears it.
    property real correction: 0
    property int strikes: 0
    property real anchorPos: 0
    property real anchorMs: 0

    function reanchor(pos) {
        anchorPos = pos;
        anchorMs = Date.now();
        position = pos;
    }

    function tick() {
        var p = mprisClock ? player.position + correction
                           : anchorPos + (Date.now() - anchorMs) / 1000 * (player ? player.rate : 1);
        // A small backward correction would un-sing a word: hold until playback passes it.
        if (playing && p < position && position - p < 0.25) return;
        position = p;
    }

    // Polled position in fractional seconds, ~500 ms apart; the clock itself only
    // for players that do not report a position.
    function syncPosition(pos, isPlaying) {
        var p = Number(pos);
        if (!isFinite(p) || p < 0) return;
        var flipped = isPlaying !== polledPlaying;
        polledPlaying = isPlaying;
        if (mprisClock) {
            var drift = isPlaying ? p - (player.position + correction) : 0;
            strikes = Math.abs(drift) > 0.6 ? strikes + 1 : 0;
            if (strikes >= 3) { correction += drift; strikes = 0; tick(); }
            return;
        }
        if (flipped || !isPlaying || Math.abs(position - p) > 0.5) reanchor(p);
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.correction = 0; root.strikes = 0; root.tick(); }
    }

    Timer {
        interval: 50
        repeat: true
        running: root.activeConsumers > 0 && root.playing && root.count > 0
        onTriggered: root.tick()
    }

    // ---- lookup ------------------------------------------------------------
    readonly property int currentIndex: root.indexForTime(root.position)
    // The clock as the lyrics see it: per-track offset applied, 100 ms ahead like the lines.
    readonly property real lyricTime: root.position - root.offset + 0.1

    function indexForTime(t) {
        if (count === 0) return -1;
        var target = t - offset + 0.1;
        var lo = 0, hi = count;
        while (lo < hi) {
            var mid = lo + ((hi - lo) >> 1);
            if (lines[mid].t <= target) lo = mid + 1;
            else hi = mid;
        }
        return lo - 1;
    }

    function timeForIndex(i) {
        return (i >= 0 && i < count) ? lines[i].t + offset : 0;
    }

    function textAt(i) {
        return (i >= 0 && i < count) ? lines[i].text : "";
    }

    // ---- helper ------------------------------------------------------------
    readonly property string helper:
        ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/lyrics.py"

    function trackArgs() {
        return ["--title", title, "--artist", artist,
                "--album", album, "--duration", "" + Math.round(duration)]
               .concat(wantWords ? ["--words"] : []);
    }

    function clear() {
        lines = [];
        backend = "";
        trackId = "";
        reason = "";
        candidates = [];
        hasWords = false;
        hunting = false;
        offset = 0;
        position = 0;
        anchorPos = 0;
        correction = 0;
        strikes = 0;
    }

    // Called by the popup on every metadata poll; only a genuine track change
    // costs a fetch.
    function setTrack(newArtist, newTitle, newAlbum, newDuration) {
        var t = ("" + (newTitle || "")).trim();
        var a = ("" + (newArtist || "")).trim();
        if (t === title && a === artist) {
            album = ("" + (newAlbum || "")).trim();
            duration = Number(newDuration) || 0;
            return;
        }

        title = t;
        artist = a;
        album = ("" + (newAlbum || "")).trim();
        duration = Number(newDuration) || 0;

        clear();
        if (t === "") { loading = false; debounce.stop(); return; }

        loading = true;
        debounce.restart();
    }

    // Skipping through a playlist would otherwise fire a fetch per track.
    Timer {
        id: debounce
        interval: 350
        repeat: false
        onTriggered: root.fetch()
    }

    function run(proc, args) {
        if (proc.running) proc.running = false;
        proc.command = ["python3", "-W", "ignore", root.helper].concat(args);
        proc.running = true;
    }

    function fetch() {
        if (title === "") return;
        loading = true;
        run(fetchProc, trackArgs());
    }

    function refresh() {
        if (title === "") return;
        loading = true;
        run(fetchProc, trackArgs().concat(["--no-cache"]));
    }

    function search() {
        searchWith(artist, title);
    }

    // A browser reports the channel as the artist and the video title as the track.
    property string searchTitle: ""
    property string searchArtist: ""
    function searchWith(a, t) {
        var qt = ("" + (t || "")).trim();
        if (qt === "") return;
        searching = true;
        searchTitle = qt;
        searchArtist = ("" + (a || "")).trim();
        run(searchProc, ["--search", "--title", searchTitle, "--artist", searchArtist]
                        .concat(wantWords ? ["--words"] : []));
    }

    // The helper records the pick, so the same choice comes back next play.
    function pick(cand) {
        if (!cand || !cand.backend || !cand.id) return;
        loading = true;
        run(fetchProc, ["--id", "" + cand.id, "--backend", "" + cand.backend,
                        "--title", title, "--artist", artist]
                       .concat(wantWords ? ["--words"] : []));
    }

    function setOffset(value) {
        offset = Math.round(value * 100) / 100;
        if (title === "") return;
        offsetProc.command = ["python3", "-W", "ignore", helper,
                              "--title", title, "--artist", artist,
                              "--set-offset", "" + offset];
        offsetProc.running = true;
    }

    function nudge(delta) { setOffset(offset + delta); }

    function applyResult(text) {
        var d;
        try { d = JSON.parse(text); } catch (e) {
            reason = "bad helper output";
            return;
        }

        // The helper echoes the track it answered for, so a late result is dropped.
        if (("" + (d.title || "")) !== title || ("" + (d.artist || "")) !== artist)
            return;

        if (!d.ok) {
            lines = [];
            backend = "";
            trackId = "";
            reason = d.reason || "no lyrics";
            // A failed PICK carries no candidates and must not wipe the list being chosen from.
            var next = d.candidates || [];
            if (next.length > 0 || candidates.length === 0)
                candidates = next;
            return;
        }

        lines = d.lines || [];
        hasWords = d.hasWords === true;
        hunting = d.pending === true;
        candidates = [];
        backend = d.backend || "";
        trackId = "" + (d.id || "");
        offset = Number(d.offset) || 0;
        reason = "";
        reanchor(position);
    }

    Process {
        id: fetchProc
        // A helper that dies without writing leaves the spinner up forever.
        onExited: { root.loading = false; root.hunting = false; }
        // One JSON object per line: cached lines first, a word-timed upgrade may follow.
        stdout: SplitParser {
            onRead: data => {
                root.loading = false;
                var t = ("" + data).trim();
                if (t !== "") root.applyResult(t);
            }
        }
    }

    Process {
        id: searchProc
        onExited: root.searching = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                try {
                    var d = JSON.parse(("" + this.text).trim());
                    // The helper echoes the query, so a late result for another search is dropped.
                    if (("" + (d.title || "")) !== root.searchTitle
                        || ("" + (d.artist || "")) !== root.searchArtist) return;
                    root.candidates = d.candidates || [];
                } catch (e) {
                    root.candidates = [];
                }
            }
        }
    }

    Process { id: offsetProc }
}
