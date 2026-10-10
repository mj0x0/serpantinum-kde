// Shim, not a port: upstream Lyrics' member names over the rice's lyrics engine (services/lyrics),
// which owns the clock and the lines; this only reshapes lines[].t/d into upstream's time/endTime.
pragma Singleton

import "../lyrics"
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    property int subscribers: 0
    readonly property var player: Lyrics.player

    readonly property bool isMediaActive: player !== null && player.playbackState !== MprisPlaybackState.Stopped && (player.trackTitle || "") !== ""
    readonly property string trackTitle: player ? (player.trackTitle || "") : ""
    readonly property string trackArtist: player ? (player.trackArtist || "") : ""
    readonly property string currentTrackKey: isMediaActive ? (trackArtist.trim() + " - " + trackTitle.trim()) : ""

    readonly property var lyrics: {
        var src = Lyrics.lines || [];
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var l = src[i];
            var ws = l.words || [];
            var words = [];
            for (var j = 0; j < ws.length; j++) {
                var w = ws[j];
                var t = Number(w.t) || 0;
                words.push({ time: t, endTime: t + (Number(w.d) || 0), text: "" + (w.text || "") });
            }
            out.push({ time: Number(l.t) || 0, text: "" + (l.text || ""), words: words });
        }
        return out;
    }
    readonly property bool hasLyrics: Lyrics.hasLyrics
    readonly property bool loading: Lyrics.loading
    readonly property real currentPosition: Lyrics.lyricTime
    readonly property int currentIndex: Lyrics.currentIndex

    function subscribe() {
        subscribers++;
        Lyrics.registerConsumer();
        feedTrack();
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        Lyrics.unregisterConsumer();
    }

    // The engine is otherwise fed only while the music popup polls; faces feed it from MPRIS.
    function feedTrack() {
        if (subscribers <= 0 || !isMediaActive) return;
        Lyrics.setTrack(trackArtist, trackTitle, player.trackAlbum || "",
                        player.lengthSupported ? player.length : 0);
    }

    onPlayerChanged: feedTrack()

    Connections {
        target: root.player
        function onTrackTitleChanged() { root.feedTrack(); }
        function onTrackArtistChanged() { root.feedTrack(); }
        function onPostTrackChanged() { root.feedTrack(); }
    }

    function getLineOpacity(idx, curIdx) {
        if (curIdx < 0) return 0.50;
        if (idx === curIdx) return 1.0;
        let d = Math.abs(idx - curIdx);
        if (d === 1) return 0.60;
        if (d === 2) return 0.38;
        return Math.max(0.20, 0.38 - ((d - 2) * 0.08));
    }

    function renderActiveLineText(modelData, pos, highlightColor, textColor) {
        if (!modelData.words || modelData.words.length === 0) {
            return modelData.text !== "" ? modelData.text : "♪";
        }
        let activeIdx = -1;
        for (let i = 0; i < modelData.words.length; i++) {
            let w = modelData.words[i];
            let end = (w.endTime !== undefined && w.endTime > w.time) ? w.endTime : (i < modelData.words.length - 1 ? modelData.words[i + 1].time : (w.time + 0.8));
            if (pos >= w.time && pos < end) {
                activeIdx = i;
                break;
            }
        }
        let highlight = highlightColor ? highlightColor.toString() : "#cba6f7";
        let baseText = textColor ? textColor.toString() : "#cdd6f4";
        let parsedTextCol = Qt.color(baseText);
        let upcoming = Qt.rgba(parsedTextCol.r, parsedTextCol.g, parsedTextCol.b, 0.40).toString();
        let html = "";
        for (let i = 0; i < modelData.words.length; i++) {
            let w = modelData.words[i];
            let end = (w.endTime !== undefined && w.endTime > w.time) ? w.endTime : (i < modelData.words.length - 1 ? modelData.words[i + 1].time : (w.time + 0.8));

            let space = "";
            if (i < modelData.words.length - 1) {
                let nextW = modelData.words[i + 1];
                if (!w.text.endsWith(" ") && !nextW.text.startsWith(" ")) {
                    if (/\S/.test(w.text) && !/^[,.\!?:;)\]]/.test(nextW.text)) {
                        space = " ";
                    }
                }
            }

            let escaped = w.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

            if (i === activeIdx) {
                html += "<font color='" + highlight + "'>" + escaped + "</font>" + space;
            } else if (pos >= end || (activeIdx !== -1 && i < activeIdx)) {
                html += "<font color='" + baseText + "'>" + escaped + "</font>" + space;
            } else {
                html += "<font color='" + upcoming + "'>" + escaped + "</font>" + space;
            }
        }
        return html.trim();
    }

    // Stub: the rice helper only matches local .lrc files by track name (helpers/lyrics.py try_local).
    function loadLocalLyricsFile(filePath) {}
}
