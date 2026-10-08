import "../../services/audio"
import "../../services/cava"
import "../../services/layout"
import "../../services/lyrics"
import "../../services/theme"
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// KDE port of serpantinum's music/EQ popup; sized and placed by Music.qml.
Item {
    id: root

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously
        currentWidth: Screen.width
    }

    // Helper function scoped to the root Item for easy access
    function s(val) {
        return scaler.s(val);
    }

    // Backend scripts (was $HOME/.config/hypr/scripts/quickshell/music/*).
    readonly property string scriptsDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    // The host (Music.qml) binds this Item's width/height to these and positions
    // it. Matches serpantinum's "music" layout (700×650, screen-scaled).
    readonly property real targetMasterWidth: root.s(700)
    readonly property real targetMasterHeight: root.s(650)

    // Theme Colors
    MatugenColors { id: _theme }

    // Theme Colors
    readonly property color base: _theme.base
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color overlay2: _theme.overlay2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color lavender: _theme.blue // Mapped to blue as Matugen template lacks lavender
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color yellow: _theme.yellow

    // Data State Properties
    property var musicData: {
        "title": "Loading...", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "textColor": "#cdd6f4", "deviceIcon": "󰓃", "deviceName": "Speaker",
        "artUrl": ""
    }

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false
    }

    // --- Audio visualizer styles (click the cover art to cycle) ---
    readonly property var vizStyleNames: ["Radial Bars", "Pulse Rings", "Orbit Arcs", "Waveform Ring", "Simple Bars", "Level Bars"]
    readonly property int vizStyleCount: vizStyleNames.length
    property int vizStyle: 0
    readonly property string vizStateFile: Quickshell.env("HOME") + "/.local/state/quickshell/music/viz_style"

    // Clicking a line jumps there. player_control.sh seek takes a percentage.
    function seekToLyric(i) {
        var len = Number(root.musicData.length) || 0;
        if (len <= 0) return;
        var t = Lyrics.timeForIndex(i);
        var pct = Math.max(0, Math.min(100, (t / len) * 100));
        var safePlayer = root.musicData.playerName ? root.musicData.playerName : "";
        root.execCmd(`${root.scriptsDir}/player_control.sh seek ${pct.toFixed(2)} ${len} "${safePlayer}"`);
    }

    function mixColor(a, b, k) {
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
    }

    function cycleViz() {
        vizStyle = (vizStyle + 1) % vizStyleCount;
        vizNameLabel.opacity = 1.0;
        vizNameFlash.restart();
        vizCanvas.requestPaint();   // redraw immediately, even if the anim tick is mid-cycle
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname '" + vizStateFile + "')\"; echo " + vizStyle + " > '" + vizStateFile + "'"]);
    }

    // Restore the saved style on startup.
    Process {
        running: true
        command: ["sh", "-c", "cat '" + root.vizStateFile + "' 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt(this.text.trim(), 10);
                if (!isNaN(n) && n >= 0 && n < root.vizStyleCount) root.vizStyle = n;
            }
        }
    }

    // Fades the style-name label back out ~1s after a cycle.
    Timer { id: vizNameFlash; interval: 1100; onTriggered: vizNameLabel.opacity = 0.0 }

    // Levels come from the Cava singleton; it owns decay-on-pause and restarts.
    property var vizLevels: Cava.barLevels
    property real vizLevel: 0.0

    // Kick is gated at 0.10 then gamma'd hard, so only a beat moves the disc.
    readonly property var beat: {
        var src = root.vizLevels;
        if (!src || src.length === 0) return { bass: 0.0, kick: 0.0 };
        var subBass   = (src[0] || 0) * 0.50 + (src[1] || 0) * 0.35 + (src[2] || 0) * 0.15;
        var kickPunch = (src[1] || 0) * 0.30 + (src[2] || 0) * 0.45 + (src[3] || 0) * 0.25;
        var rawKick = Math.max(subBass, kickPunch);
        return {
            bass: Math.max(0, Math.min(1, subBass * 0.6 + kickPunch * 0.4)),
            kick: rawKick > 0.10 ? Math.min(1, Math.pow((rawKick - 0.10) / 0.90, 1.8) * 1.4) : 0.0
        };
    }
    readonly property real bassLevel: beat.bass
    readonly property real kickLevel: beat.kick
    // Every style drives the disc: all six read the same shaped bands now, so
    // gating the beat reaction to one of them was leaving the rest half-lit.
    readonly property bool discReacts: root.musicData.status === "Playing"

    // Browser integration publishes ONE MPRIS name for every browser, so the bus
    // cannot say which; PipeWire's application.name can. chromium before chrome.
    readonly property var browserMarks: [
        { key: "firefox",  glyph: "\u{f0239}", label: "Firefox"  },
        { key: "chromium", glyph: "\u{f02af}", label: "Chromium" },
        { key: "chrome",   glyph: "\u{f02af}", label: "Chrome"   },
        { key: "brave",    glyph: "\u{f02af}", label: "Brave"    },
        { key: "vivaldi",  glyph: "\u{f02af}", label: "Vivaldi"  },
        { key: "edge",     glyph: "\u{f01e9}", label: "Edge"     }
    ]

    function browserMark() {
        var apps = Audio.apps;
        if (!apps) return null;
        for (var i = 0; i < apps.length; i++) {
            var name = ("" + Audio.getNodeAppName(apps[i])).toLowerCase();
            for (var m = 0; m < root.browserMarks.length; m++) {
                if (name.indexOf(root.browserMarks[m].key) >= 0)
                    return root.browserMarks[m];
            }
        }
        return null;
    }

    // Which app is playing. Matched on the MPRIS bus name, which is what
    // playerctl reports; every codepoint checked by glyph name against Iosevka.
    function playerGlyph() {
        var p = ("" + (root.musicData.playerName || "")).toLowerCase();
        if (p.indexOf("spotify") >= 0) return "\u{f04c7}";          // md-spotify
        if (p.indexOf("firefox") >= 0) return "\u{f0239}";          // md-firefox
        if (p.indexOf("chrome") >= 0
            || p.indexOf("chromium") >= 0
            || p.indexOf("brave") >= 0
            || p.indexOf("vivaldi") >= 0) return "\u{f02af}";       // md-google_chrome
        if (p.indexOf("edge") >= 0) return "\u{f01e9}";             // md-microsoft_edge
        if (p.indexOf("vlc") >= 0) return "\u{f057c}";              // md-vlc
        if (p.indexOf("mpv") >= 0) return "\u{f0fce}";              // md-movie_open
        if (p.indexOf("kdeconnect") >= 0) return "\u{f101e}";       // md-cast_audio
        if (p.indexOf("plasma-browser") >= 0 || p.indexOf("browser") >= 0) {
            var b = root.browserMark();
            return b ? b.glyph : "\u{f059f}";                       // md-web
        }
        return "\u{f075a}";                                         // md-music
    }

    function playerLabel() {
        var p = ("" + (root.musicData.playerName || "")).toLowerCase();
        if (p.indexOf("plasma-browser") >= 0) {
            var b = root.browserMark();
            return b ? b.label : "Browser";
        }
        return "" + (root.musicData.source || "Offline");
    }

    // Ten sliders, ten frequency bands: cava can show what each one is acting on.
    readonly property var eqBands: root.shapedBands(10)
    function eqLevel(i) {
        var b = root.eqBands;
        return (b && b.length > i) ? b[i] : 0.0;
    }

    // Sample the 64 cava bands logarithmically (pow 1.15), interpolate, mild gamma.
    function shapedBands(count) {
        var src = root.vizLevels, out = [];
        if (!src || src.length === 0) {
            for (var z = 0; z < count; z++) out.push(0.0);
            return out;
        }
        var n = src.length;
        for (var i = 0; i < count; i++) {
            var norm = count > 1 ? (i / (count - 1)) : 0;
            var pos = Math.pow(norm, 1.15) * (n - 1);
            var i0 = Math.floor(pos), i1 = Math.min(n - 1, i0 + 1), f = pos - i0;
            var v0 = src[i0] || 0.0, v1 = src[i1] || 0.0;
            var v = Math.max(0, Math.min(1, v0 + (v1 - v0) * f));
            out.push(Math.pow(v, 1.08));
        }
        return out;
    }

    Binding {
        target: Cava
        property: "isPlaying"
        value: root.musicData.status === "Playing"
    }

    Component.onCompleted: { Cava.registerConsumer(); Lyrics.registerConsumer(); }
    Component.onDestruction: { Cava.unregisterConsumer(); Lyrics.unregisterConsumer(); }

    Connections {
        target: Cava
        function onBarLevelsChanged() {
            var b = Cava.barLevels, mx = 0;
            for (var i = 0; i < b.length; i++) if (b[i] > mx) mx = b[i];
            root.vizLevel = root.vizLevel * 0.55 + mx * 0.45;   // smoothed peak
            vizCanvas.requestPaint();
        }
    }

    // Accumulators for Process standard output
    property string accumulatedMusicOut: ""
    property string accumulatedEqOut: ""

    // UI State for debouncing the slider and play button
    property bool userIsSeeking: false
    property bool userToggledPlay: false
    
    // ANTI-JITTER LOCK: Prevents background polling from reverting UI during processing
    property real lastEqUpdate: 0

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2
        duration: 90000
        loops: Animation.Infinite
        running: true
    }

    // --- CANVAS LIGHTNING ANIMATION STATE ---
    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0 // 1.0 = fully faded out

    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation { 
            target: root; property: "eqLightningProgress"; 
            from: 0.0; to: 10.0; // 10 points = 9 segments
            duration: 650; // Fast, snappy, energetic strike
            easing.type: Easing.OutSine 
        }
        PauseAnimation { duration: 150 } // Hold the core flash at the end
        NumberAnimation { 
            target: root; property: "eqLightningFade"; 
            from: 0.0; to: 1.0; 
            duration: 800; // Smooth dissipation
            easing.type: Easing.OutQuad 
        }
        ScriptAction { script: { root.eqLightningProgress = 0.0; } }
    }

    function triggerEqLightning() {
        Sounds.playSfx("musicpopup/swoosh.wav", 0.75);
        eqLightningAnim.restart();
    }

    // 0 = equalizer, 1 = lyrics. They share the region below the separator. The popup is
    // rebuilt on every open, so the last choice is read back from a state file.
    property int section: 0
    onSectionChanged: sectionFile.setText("" + section)

    FileView {
        id: sectionFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/music/section"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        Component.onCompleted: { if (parseInt(("" + text()).trim(), 10) === 1) root.section = 1; }
    }

    // Every shortcut below is a bare key. Without this they would eat each
    // character typed into the lyric search fields.
    readonly property bool typing:
        (typeof artistField !== "undefined" && artistField.hasFocus)
        || (typeof titleField !== "undefined" && titleField.hasFocus)

    function runManualSearch() {
        Lyrics.searchWith(artistField.text, titleField.text);
    }

    property string lastMusicStatus: "Stopped"
    onMusicDataChanged: {
        if (musicData && musicData.status && musicData.status !== lastMusicStatus) {
            if (musicData.status === "Playing") {
                playPulse.trigger();
            }
            lastMusicStatus = musicData.status;
        }

        // length > 0 filters the "Loading..." placeholder and the offline state,
        // neither of which is a track worth looking up.
        if (musicData && (Number(musicData.length) || 0) > 0) {
            Lyrics.playerName = "" + (musicData.playerName || "");
            Lyrics.setTrack(musicData.artist, musicData.title, musicData.album,
                            Number(musicData.length) || 0);
            Lyrics.syncPosition(Number(musicData.position) || 0,
                                musicData.status === "Playing");
        }
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introCover: 0
    property real introText: 0
    property real introControls: 0
    property real introSeparator: 0
    property real introEqHeader: 0
    property real introEqSliders: 0
    property real introPresets: 0

    ParallelAnimation {
        running: true

        // 1. Base window fades, scales, and lifts smoothly (sped up by ~40ms)
        NumberAnimation { target: root; property: "introMain"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }

        // 2. Cover art snaps in with a premium elastic feel
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: root; property: "introCover"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // 3. Text block glides in smoothly
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introText"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }
        }

        // 4. Progress bar and Media Controls bounce in
        SequentialAnimation {
            PauseAnimation { duration: 230 }
            NumberAnimation { target: root; property: "introControls"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        // 5. Separator line drops and fades
        SequentialAnimation {
            PauseAnimation { duration: 310 }
            NumberAnimation { target: root; property: "introSeparator"; from: 0; to: 1.0; duration: 660; easing.type: Easing.OutQuart }
        }

        // 6. EQ header follows down seamlessly
        SequentialAnimation {
            PauseAnimation { duration: 370 }
            NumberAnimation { target: root; property: "introEqHeader"; from: 0; to: 1.0; duration: 710; easing.type: Easing.OutQuart }
        }

        // 7. EQ Sliders sweep up in a sequential waterfall wave
        SequentialAnimation {
            PauseAnimation { duration: 430 }
            NumberAnimation { target: root; property: "introEqSliders"; from: 0; to: 1.0; duration: 860; easing.type: Easing.OutExpo }
        }

        // 8. Presets finish the orchestration with a final pop
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: root; property: "introPresets"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    // --- FIXED COLOR PARSING LOGIC ---
    property var borderColors: {
        // Distinct roles on purpose: mauve and blue are both md3.primary after the
        // accent remap, so the old mauve/blue/red default was really two colours.
        var defaultColors = [root.mauve, root.pink, root.red, root.mauve];
        if (!root.musicData || !root.musicData.grad) return defaultColors;
        
        var hexRegex = /#[0-9a-fA-F]{6}/g;
        var matches = root.musicData.grad.match(hexRegex);
        
        if (matches && matches.length >= 3) {
            return [matches[0], matches[1], matches[2], matches[0]]; // Wrap around for looping
        }
        return defaultColors;
    }

    // PROPER EXCEPTION-FREE FIX: Explicit bindings so GradientStop actually repaints
    property color bc1: borderColors[0] || root.mauve
    property color bc2: borderColors[1] || root.blue
    property color bc3: borderColors[2] || root.red
    property color bc4: borderColors[3] || root.mauve

    property color dynamicTextColor: {
        if (root.musicData && root.musicData.textColor) {
            var c = String(root.musicData.textColor).trim();
            // Securely extract exactly #RRGGBB, ignoring any alpha leak from the shell
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return root.text;
    }

    // --- UTILITIES & OPTIMISTIC UPDATES ---
    function execCmd(cmdStr) {
        var safeCmd = cmdStr.replace(/`/g, "\\`");
        var p = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bash", "-c", \`${safeCmd}\`]
                running: true
                onExited: (exitCode) => destroy()
            }
        `, root);
    }

    // Order matches the two on-screen rows, so 1-8 maps to what you see.
    readonly property var presetOrder: ["Flat", "Bass", "Treble", "Vocal",
                                        "Pop", "Rock", "Jazz", "Classic"]

    function cyclePreset(step) {
        var cur = root.presetOrder.indexOf(root.eqData.preset || "Flat");
        if (cur < 0) cur = 0;                       // "Custom" -> start from Flat
        var next = (cur + step + root.presetOrder.length) % root.presetOrder.length;
        root.applyPresetOptimistically(root.presetOrder[next]);
    }

    // Shortcut, not Keys: this Item never gets active focus, so Keys handlers
    // would silently never fire.
    Instantiator {
        model: root.presetOrder
        delegate: Shortcut {
            required property var modelData
            required property int index
            sequence: (index + 1).toString()        // 1-8
            enabled: !root.typing
            onActivated: root.applyPresetOptimistically(modelData)
        }
    }
    Shortcut { sequence: "]"; enabled: !root.typing; onActivated: root.cyclePreset(1) }
    Shortcut { sequence: "["; enabled: !root.typing; onActivated: root.cyclePreset(-1) }
    Shortcut { sequence: "0"; enabled: !root.typing; onActivated: root.applyPresetOptimistically("Flat") }

    // Section switching. Digits stay with the presets, so letters here.
    Shortcut { sequence: "Tab"; enabled: !root.typing; onActivated: root.section = (root.section + 1) % 2 }
    Shortcut { sequence: "Shift+1"; enabled: !root.typing; onActivated: root.section = 0 }
    Shortcut { sequence: "Shift+2"; enabled: !root.typing; onActivated: root.section = 1 }
    Shortcut { sequence: "E"; enabled: !root.typing; onActivated: root.section = 0 }
    Shortcut { sequence: "L"; enabled: !root.typing; onActivated: root.section = 1 }
    Shortcut { sequence: ","; enabled: root.section === 1 && !root.typing; onActivated: Lyrics.nudge(-0.1) }
    Shortcut { sequence: "."; enabled: root.section === 1 && !root.typing; onActivated: Lyrics.nudge(0.1) }
    Shortcut { sequence: "R"; enabled: root.section === 1 && !root.typing; onActivated: Lyrics.refresh() }

    function applyPresetOptimistically(presetName) {
        var presets = {
            "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "Bass": [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
            "Treble": [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
            "Vocal": [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
            "Pop": [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
            "Rock": [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
            "Jazz": [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
            "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
        };
        if (presets[presetName]) {
            var temp = Object.assign({}, root.eqData);
            for (var i = 0; i < 10; i++) {
                temp["b" + (i + 1)] = presets[presetName][i];
            }
            temp.preset = presetName;
            temp.pending = false; 
            root.eqData = temp; 
            
            // Blind the polling process to stop it from fetching old data
            root.lastEqUpdate = Date.now(); 
            
            root.triggerEqLightning();
            execCmd(`${root.scriptsDir}/equalizer.sh preset ${presetName}`);
        }
    }

    // --- DATA POLLING ---
    Timer {
        id: seekDebounceTimer
        interval: 2500 
        onTriggered: root.userIsSeeking = false
    }

    Timer {
        id: playDebounceTimer
        interval: 1500
        onTriggered: root.userToggledPlay = false
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!musicProc.running) musicProc.running = true;
            if (!eqProc.running) eqProc.running = true;
        }
    }

    Process {
        id: musicProc
        running: true
        command: ["bash", "-c", root.scriptsDir + "/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    var outStr = this.text.trim();
                    if (outStr.length > 0) {
                        try { 
                            var newData = JSON.parse(outStr); 
                            if (root.userToggledPlay) {
                                newData.status = root.musicData.status; 
                            }
                            root.musicData = newData; 
                        } catch(e) {}
                    }
                }
            }
        }
    }

    Process {
        id: eqProc
        running: true
        command: ["bash", "-c", root.scriptsDir + "/equalizer.sh get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    // Ignore background data entirely if we recently pushed an optimistic update
                    if (Date.now() - root.lastEqUpdate < 2000) return;

                    var outStr = this.text.trim();
                    if (outStr.length > 0) {
                        try { root.eqData = JSON.parse(outStr); } catch(e) {}
                    }
                }
            }
        }
    }

    // --- UI LAYOUT ---
    Item {
        id: mainWrapper
        anchors.fill: parent
        
        // Deepened scale effect and introduced a gentle Y-axis translation for the main container
        scale: 0.92 + (0.08 * root.introMain)
        opacity: root.introMain
        transform: Translate { y: root.s(15) * (1 - root.introMain) }

        // OUTER ANIMATED BORDER WITH PROPER CLIPPING
        Item {
            anchors.fill: parent

            Shape {
                id: maskRectOuter
                anchors.fill: parent
                visible: false // Hidden because MultiEffect will render it as a mask
                layer.enabled: true
                preferredRendererType: Shape.GeometryRenderer // Fixes lag by hardware accelerating the stroke

                property real sw: root.s(6)
                property real inset: (sw / 2) + root.s(0.5) 
                property real w: width
                property real h: height
                property real r: Math.max(0, Radius.outer(root.s(14)) - inset)
                
                // Mathematical perimeter
                property real straightLines: 2 * (w - 2 * inset - 2 * r) + 2 * (h - 2 * inset - 2 * r)
                property real arcLines: 2 * Math.PI * r
                property real perimeter: straightLines + arcLines

                property real drawProgress: 0

                NumberAnimation on drawProgress {
                    id: chargeAnim
                    from: 0
                    to: maskRectOuter.perimeter
                    duration: 1200 // The time it takes to "charge" the whole wick
                    easing.type: Easing.OutCubic
                    running: true // Ensure it starts reliably
                }

                ShapePath {
                    strokeWidth: maskRectOuter.sw
                    strokeColor: "black" 
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap 

                    // QML Shape dash patterns are measured in units of strokeWidth! 
                    dashPattern: [maskRectOuter.perimeter / maskRectOuter.sw, maskRectOuter.perimeter / maskRectOuter.sw]
                    dashOffset: (maskRectOuter.perimeter - maskRectOuter.drawProgress) / maskRectOuter.sw

                    // Start exactly at Bottom-Left corner, going UP clockwise
                    startX: maskRectOuter.inset
                    startY: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r

                    // 1. Up to top-left corner
                    PathLine { x: maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r }
                    // 2. Arc top-left
                    PathArc { 
                        x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 3. Right to top-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.inset }
                    // 4. Arc top-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 5. Down to bottom-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r }
                    // 6. Arc bottom-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 7. Left to bottom-left corner
                    PathLine { x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset }
                    // 8. Arc bottom-left to finish
                    PathArc { 
                        x: maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                }
            }

            Item {
                id: gradContainer
                anchors.fill: parent
                visible: false // Hidden for MultiEffect mapping
                clip: true // Prevents the rotated gradient bounding box from bulging out the sides!

                Rectangle {
                    width: Math.max(parent.width, parent.height) * 2
                    height: width
                    anchors.centerIn: parent
                    
                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 5000
                        loops: Animation.Infinite
                        running: true
                    }

                    gradient: Gradient {
                        // FIXED: Using securely unpacked color bindings
                        GradientStop { position: 0.0; color: root.bc1; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.33; color: root.bc2; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.66; color: root.bc3; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 1.0; color: root.bc4; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                    }
                }
            }

            MultiEffect {
                source: gradContainer
                anchors.fill: parent
                maskEnabled: true
                maskSource: maskRectOuter
            }
        }

        // INNER WINDOW BOX
        Rectangle {
            id: innerBg
            anchors.fill: parent
            anchors.margins: root.s(3)
            color: root.base
            radius: Radius.inset(root.s(10), root.s(3))

            // FIX: This forces the entire background to render as a single hardware texture,
            // preventing the UI from dragging and causing "shadow boxes" during the StackView transition!
            layer.enabled: true

            // Provide a perfectly rounded mask for the inner content
            Rectangle {
                id: innerBgMask
                anchors.fill: parent
                radius: Radius.inset(root.s(10), root.s(3))
                visible: false
                
                // FIX: Masks in MultiEffect strictly require layer.enabled to correctly capture the radius during scaling!
                layer.enabled: true 
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent
                
                // This correctly clamps the blur and orbit circles to the 10px radius corners
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                // LAYER 1: Background Blur (Smooth fade-in)
                Image {
                    anchors.fill: parent
                    source: root.musicData.blur ? "file://" + root.musicData.blur : ""
                    fillMode: Image.PreserveAspectCrop
                    
                    // Fixed: Ensures blur is completely hidden when stopped so the pure base color matches the calendar
                    opacity: (status === Image.Ready && root.musicData.status !== "Stopped" && root.musicData.status !== "Offline") ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.InOutQuad } }
                }

                // LAYER 1.5: Flowing Orbits
                Rectangle {
                    width: parent.width * 0.8; height: width; radius: width / 2
                    x: (parent.width / 2 - width / 2) + Math.cos(root.globalOrbitAngle * 2) * root.s(150)
                    y: (parent.height / 2 - height / 2) + Math.sin(root.globalOrbitAngle * 2) * root.s(100)
                    
                    // Fixed: Hides orbits when stopped
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.04 : 0.0)
                    color: root.musicData.status === "Playing" ? root.mauve : root.surface2
                    Behavior on color { ColorAnimation { duration: 1000 } }
                    Behavior on opacity { NumberAnimation { duration: 1000 } }
                }
                
                Rectangle {
                    width: parent.width * 0.9; height: width; radius: width / 2
                    x: (parent.width / 2 - width / 2) + Math.sin(root.globalOrbitAngle * 1.5) * root.s(-150)
                    y: (parent.height / 2 - height / 2) + Math.cos(root.globalOrbitAngle * 1.5) * root.s(-100)
                    
                    // Fixed: Hides orbits when stopped
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.02 : 0.0)
                    color: root.musicData.status === "Playing" ? root.blue : root.surface1
                    Behavior on color { ColorAnimation { duration: 1000 } }
                    Behavior on opacity { NumberAnimation { duration: 1000 } }
                }
            }

            // LAYER 2: UI Content
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(20)
                spacing: 0

                // --- Top info ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(220)
                    spacing: root.s(25)

                    // Cover Art Wrapper
                    Item {
                        Layout.preferredWidth: root.s(220)
                        Layout.preferredHeight: root.s(220)
                        Layout.alignment: Qt.AlignVCenter

                        opacity: root.introCover
                        // Enhanced 2D drift animation
                        transform: Translate { x: root.s(-40) * (1 - root.introCover); y: root.s(10) * (1 - root.introCover) }

                        // Beat reaction: scale with the bass, bounce on the kick, tilt with the low end.
                        scale: root.musicData.status !== "Playing" ? 0.90
                             : (root.discReacts ? 1.0 + (root.bassLevel * 0.0135) + (root.kickLevel * 0.027)
                                                : 1.0)
                        Behavior on scale {
                            enabled: !root.discReacts
                            NumberAnimation { duration: 800; easing.type: Easing.OutElastic; easing.overshoot: 1.2 }
                        }
                        anchors.verticalCenterOffset: root.discReacts
                                                    ? -(root.kickLevel * root.s(220) * 0.5 * 0.02025) : 0
                        rotation: root.discReacts ? (root.bassLevel - 0.3) * 0.9 : 0
                        Behavior on rotation { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        // Kick glow — barely there until a beat lands.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + root.s(26)
                            height: width
                            radius: width / 2
                            color: root.mauve
                            visible: root.discReacts
                            opacity: root.discReacts ? 0.01 + (root.kickLevel * 0.055) : 0.0
                            scale: 0.992 + (root.kickLevel * 0.02625)
                            z: -1
                            Behavior on opacity { NumberAnimation { duration: 40; easing.type: Easing.OutCubic } }
                            Behavior on scale { SpringAnimation { spring: 5.2; damping: 0.34; mass: 0.6 } }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.s(110)
                            color: root.surface1
                            border.width: root.s(4)
                            border.color: root.musicData.status === "Playing" ? root.mauve : root.overlay0
                            Behavior on border.color { ColorAnimation { duration: 500 } }

                            // Glow Effect surrounding the thumbnail
                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                width: parent.width + root.s(20)
                                height: parent.height + root.s(20)
                                radius: width / 2
                                color: root.mauve
                                opacity: root.musicData.status === "Playing" ? 0.5 : 0.0
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 1.0
                                }
                            }

                            // Subtle Audio Visualizer Bars
                            Canvas {
                                id: vizCanvas
                                // Sized larger than the album art: a Canvas clips to its own bounds, so bars
                                // radiating past the art edge need the room or they are never drawn.
                                anchors.centerIn: parent
                                width: parent.width + root.s(90)
                                height: parent.height + root.s(90)
                                opacity: root.musicData.status === "Playing" ? 0.8 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 400 } }

                                property real animPhase: 0
                                NumberAnimation on animPhase {
                                    from: 0; to: Math.PI * 2
                                    duration: 2000
                                    loops: Animation.Infinite
                                    running: root.musicData.status === "Playing"
                                }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);

                                    var cx = width / 2, cy = height / 2;
                                    var artR = parent.width / 2;   // album-art edge, measured from centre
                                    var m = root.mauve;
                                    ctx.lineCap = "round";

                                    var levels = root.vizLevels;
                                    var have = levels && levels.length > 0;
                                    var lvl = root.vizLevel;   // 0..1 smoothed peak

                                    // Radius budget rather than fixed heights; s(90) over the art = 45px per side.
                                    var budget = Math.min(root.s(22), artR * 0.20);
                                    var tintFor = function (frac, lv) {
                                        return Qt.tint(m, Qt.rgba(1, 1, 1, (frac * 0.4 + lv * 0.6) * 0.45));
                                    };

                                    if (root.vizStyle === 0) {
                                        // Radial Bars - mirrored spectrum, symmetric about the vertical axis.
                                        var rbHalf = 36, rbCount = rbHalf * 2;
                                        var rbShaped = root.shapedBands(rbHalf);
                                        var rbBase = artR + root.s(4);
                                        ctx.lineWidth = Math.max(root.s(2),
                                                        (2 * Math.PI * artR) / rbCount * 0.55);
                                        for (var i = 0; i < rbCount; i++) {
                                            var ri = i < rbHalf ? i : (rbCount - 1 - i);
                                            var rv = rbShaped[ri];
                                            var a = (i / rbCount) * Math.PI * 2 - Math.PI / 2;
                                            var h = Math.max(root.s(2), rv * budget * 1.70);
                                            var rc = tintFor(ri / rbHalf, rv);
                                            ctx.strokeStyle = Qt.rgba(rc.r, rc.g, rc.b, 0.35 + rv * 0.65);
                                            ctx.beginPath();
                                            ctx.moveTo(cx + Math.cos(a) * rbBase, cy + Math.sin(a) * rbBase);
                                            ctx.lineTo(cx + Math.cos(a) * (rbBase + h), cy + Math.sin(a) * (rbBase + h));
                                            ctx.stroke();
                                        }
                                    } else if (root.vizStyle === 1) {
                                        // Pulse Rings - the spectrum rides as a ripple in each ring's radius.
                                        var prRings = 5, prSteps = 96, prHalf = 48;
                                        var prShaped = root.shapedBands(prHalf);
                                        for (var r = 0; r < prRings; r++) {
                                            var t = ((animPhase / (Math.PI * 2)) + r / prRings) % 1.0;
                                            var rr = artR + root.s(4) + t * budget * (0.55 + 1.1 * lvl);
                                            var pc = tintFor(t, lvl);
                                            ctx.lineWidth = root.s(1.4) + root.s(1.6) * (1 - t);
                                            ctx.strokeStyle = Qt.rgba(pc.r, pc.g, pc.b,
                                                                      (1.0 - t) * (0.18 + 0.55 * lvl));
                                            ctx.beginPath();
                                            for (var ps = 0; ps <= prSteps; ps++) {
                                                var pa = (ps / prSteps) * Math.PI * 2;
                                                var pm = ps < prHalf ? ps : Math.max(0, prSteps - ps);
                                                var rip = prShaped[Math.min(prHalf - 1, pm)] * root.s(8) * (1 - t);
                                                var prad = rr + rip;
                                                var ppx = cx + Math.cos(pa) * prad, ppy = cy + Math.sin(pa) * prad;
                                                if (ps === 0) ctx.moveTo(ppx, ppy); else ctx.lineTo(ppx, ppy);
                                            }
                                            ctx.closePath();
                                            ctx.stroke();
                                        }
                                    } else if (root.vizStyle === 2) {
                                        // Orbit Arcs - one arc pair per frequency group, so bass and treble differ.
                                        var oaCount = 6;
                                        var oaShaped = root.shapedBands(oaCount);
                                        for (var k = 0; k < oaCount; k++) {
                                            var ov = oaShaped[k];
                                            var arcR = artR + root.s(6) + k * (budget / oaCount) * 1.15;
                                            var span = Math.PI * (0.10 + 0.55 * ov);
                                            var dir = (k % 2 === 0) ? 1 : -1;
                                            var start = animPhase * dir * (0.55 + k * 0.12)
                                                      + (k / oaCount) * Math.PI * 2;
                                            var oc = tintFor(k / oaCount, ov);
                                            ctx.lineWidth = root.s(1.5) + root.s(3.5) * ov;
                                            ctx.strokeStyle = Qt.rgba(oc.r, oc.g, oc.b, 0.22 + 0.62 * ov);
                                            ctx.beginPath();
                                            ctx.arc(cx, cy, arcR, start, start + span);
                                            ctx.stroke();
                                            ctx.beginPath();
                                            ctx.arc(cx, cy, arcR, start + Math.PI, start + Math.PI + span);
                                            ctx.stroke();
                                        }
                                    } else if (root.vizStyle === 3) {
                                        // Waveform Ring - three concentric traces.
                                        var wSteps = 132, wHalf = 66;
                                        var wShaped = root.shapedBands(wHalf);
                                        for (var layer = 0; layer < 3; layer++) {
                                            var lr = artR + root.s(7) + layer * root.s(6);
                                            var amp = budget * 0.55 * (0.30 + 0.95 * lvl) * (1 - layer * 0.22);
                                            var wc = tintFor(layer / 3, lvl);
                                            ctx.lineWidth = Math.max(root.s(1), root.s(2) - layer * root.s(0.4));
                                            ctx.strokeStyle = Qt.rgba(wc.r, wc.g, wc.b,
                                                                      (0.55 - layer * 0.14) * (0.40 + 0.60 * lvl));
                                            ctx.beginPath();
                                            for (var ws = 0; ws <= wSteps; ws++) {
                                                var wa = (ws / wSteps) * Math.PI * 2;
                                                var wm = ws < wHalf ? ws : Math.max(0, wSteps - ws);
                                                var wb = wShaped[Math.min(wHalf - 1, wm)];
                                                var wrad = lr + wb * amp
                                                         + Math.sin(wa * 6 + animPhase * (1 + layer * 0.3)) * root.s(2);
                                                var wpx = cx + Math.cos(wa) * wrad, wpy = cy + Math.sin(wa) * wrad;
                                                if (ws === 0) ctx.moveTo(wpx, wpy); else ctx.lineTo(wpx, wpy);
                                            }
                                            ctx.closePath();
                                            ctx.stroke();
                                        }
                                    } else if (root.vizStyle === 4) {
                                        // Simple Bars - deliberately the plain one: dense, uniform, one flat accent.
                                        var sbHalf = 44, sbCount = sbHalf * 2;
                                        var sbShaped = root.shapedBands(sbHalf);
                                        var sbBase = artR + root.s(3);
                                        ctx.lineWidth = Math.max(root.s(1.2),
                                                        (2 * Math.PI * artR) / sbCount * 0.5);
                                        for (var b = 0; b < sbCount; b++) {
                                            var si = b < sbHalf ? b : (sbCount - 1 - b);
                                            var sv = sbShaped[si];
                                            var a2 = (b / sbCount) * Math.PI * 2 - Math.PI / 2;
                                            var h2 = Math.max(root.s(1.5), sv * budget * 1.20);
                                            ctx.strokeStyle = Qt.rgba(m.r, m.g, m.b, 0.30 + sv * 0.55);
                                            ctx.beginPath();
                                            ctx.moveTo(cx + Math.cos(a2) * sbBase, cy + Math.sin(a2) * sbBase);
                                            ctx.lineTo(cx + Math.cos(a2) * (sbBase + h2), cy + Math.sin(a2) * (sbBase + h2));
                                            ctx.stroke();
                                        }
                                    } else if (root.vizStyle === 5) {
                                        // Level Bars - art at 86% of the radius, bars tile the remaining 14%.
                                        var lbCount = 60;
                                        var lbMax = artR * (1 / 0.86 - 1);          // his availableRadius - artRadius
                                        var lbBase = artR + root.s(1);
                                        var lbW = Math.max(root.s(1.5), (2 * Math.PI * artR) / lbCount * 0.65);
                                        var shaped = root.shapedBands(lbCount);
                                        ctx.lineWidth = lbW;
                                        for (var lb = 0; lb < lbCount; lb++) {
                                            var lv = shaped[lb];
                                            var la = (lb / lbCount) * Math.PI * 2 - Math.PI / 2;
                                            var lh = Math.max(root.s(2), lv * lbMax * 1.4);
                                            // Theme accent, not the album colours: the cover quantise can return near-black.
                                            var mix = ((lb / lbCount) * 0.4 + lv * 0.6) * 0.45;
                                            var bcol = Qt.tint(m, Qt.rgba(1, 1, 1, mix));
                                            ctx.strokeStyle = Qt.rgba(bcol.r, bcol.g, bcol.b, 0.40 + lv * 0.60);
                                            ctx.beginPath();
                                            ctx.moveTo(cx + Math.cos(la) * lbBase, cy + Math.sin(la) * lbBase);
                                            ctx.lineTo(cx + Math.cos(la) * (lbBase + lh), cy + Math.sin(la) * (lbBase + lh));
                                            ctx.stroke();
                                        }
                                    }
                                }

                                Timer {
                                    interval: 30
                                    running: root.musicData.status === "Playing"
                                    repeat: true
                                    onTriggered: vizCanvas.requestPaint()
                                }
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: root.s(4)
                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: root.musicData.artUrl ? "file://" + root.musicData.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false 
                                }
                                Rectangle {
                                    id: maskRect
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: true 
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: artImg
                                    maskEnabled: true
                                    maskSource: maskRect
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }
                                
                                // NEW: Dimmed slightly by tinting with the primary mauve accent, as requested
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.2)
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }

                                Rectangle {
                                    width: root.s(40); height: root.s(40)
                                    radius: root.s(20); color: "#000000"
                                    opacity: 0.8; anchors.centerIn: parent
                                }
                            }

                            // Click the cover art to cycle the visualizer style.
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cycleViz()
                            }

                            // Brief flash of the style name whenever it changes.
                            Text {
                                id: vizNameLabel
                                anchors.centerIn: parent
                                text: root.vizStyleNames[root.vizStyle]
                                color: root.text
                                font.family: Fonts.ui; font.pixelSize: root.s(13); font.bold: true
                                style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.75)
                                opacity: 0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.s(15)

                        // TEXT INFO CHUNK
                        ColumnLayout {
                            spacing: root.s(6)
                            opacity: root.introText
                            transform: Translate { x: root.s(30) * (1 - root.introText) }
                            
                            // HARD-LOCKED SEAMLESS INFINITE MARQUEE
                            Item {
                                id: titleClipRect
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(28) 
                                clip: true

                                // This is the distance between the end of the text and the clone
                                property int marqueeSpacing: root.s(60)

                                Item {
                                    id: marqueeContainer
                                    height: parent.height

                                    Row {
                                        spacing: titleClipRect.marqueeSpacing
                                        Text {
                                            id: titleTextMain
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(20)
                                            font.bold: true
                                            Behavior on color { ColorAnimation { duration: 600 } }

                                            // Only animate if the text is physically wider than our container
                                            onTextChanged: {
                                                marqueeContainer.x = 0;
                                                if (implicitWidth > titleClipRect.width) {
                                                    titleAnim.restart();
                                                } else {
                                                    titleAnim.stop();
                                                }
                                            }
                                        }
                                        // The clone that creates the seamless endless loop
                                        Text {
                                            id: titleTextClone
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(20)
                                            font.bold: true
                                            visible: titleTextMain.implicitWidth > titleClipRect.width
                                        }
                                    }

                                    SequentialAnimation on x {
                                        id: titleAnim
                                        loops: Animation.Infinite
                                        running: titleTextMain.implicitWidth > titleClipRect.width

                                        // 1. Stop for a few seconds in the initial position
                                        PauseAnimation { duration: 3000 }
                                        
                                        // 2. Smoothly run left until the clone is exactly where the original started
                                        NumberAnimation {
                                            from: 0
                                            to: -(titleTextMain.implicitWidth + titleClipRect.marqueeSpacing)
                                            // The duration calculates dynamically to maintain a constant scroll speed
                                            duration: (titleTextMain.implicitWidth + titleClipRect.marqueeSpacing) * 25
                                        }
                                        
                                        // 3. Instantly snap back to 0 without stopping (creating the seamless loop)
                                        PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                    }
                                }
                            }

                            Text {
                                text: root.musicData.artist ? "BY " + root.musicData.artist : ""
                                color: root.subtext0 // Better matugen match
                                font.family: Fonts.ui
                                font.pixelSize: root.s(14)
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1 // Strict 1 line
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(20)
                            }
                            // Chips on surface0: this row sits on the blurred art and must stay readable.
                            RowLayout {
                                spacing: root.s(8)

                                Rectangle {
                                    color: Qt.alpha(root.surface0, 0.75)
                                    radius: Radius.outer(root.s(8))
                                    Layout.preferredHeight: root.s(24)
                                    Layout.preferredWidth: pillContent.width + root.s(18)
                                    RowLayout {
                                        id: pillContent
                                        anchors.centerIn: parent
                                        spacing: root.s(6)
                                        Text {
                                            text: root.musicData.deviceIcon || "\u{f04c3}"
                                            color: root.mauve
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: root.s(14)
                                        }
                                        Text {
                                            text: root.musicData.deviceName || "Speaker"
                                            color: root.subtext1
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(12)
                                            font.bold: true
                                        }
                                    }
                                }

                                Rectangle {
                                    color: Qt.alpha(root.surface0, 0.75)
                                    radius: Radius.outer(root.s(8))
                                    Layout.preferredHeight: root.s(24)
                                    Layout.preferredWidth: playerContent.width + root.s(18)
                                    RowLayout {
                                        id: playerContent
                                        anchors.centerIn: parent
                                        spacing: root.s(6)
                                        Text {
                                            text: root.playerGlyph()
                                            color: root.blue
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: root.s(14)
                                        }
                                        Text {
                                            text: root.playerLabel()
                                            color: root.subtext1
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(12)
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        // PROGRESS AREA CHUNK
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(5)
                            opacity: root.introControls
                            transform: Translate { x: root.s(20) * (1 - root.introControls); y: root.s(10) * (1 - root.introControls) }

                            Slider {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(20) 
                                from: 0; to: 100

                                Connections {
                                    target: root
                                    function onMusicDataChanged() {
                                        if (!progBar.pressed && !root.userIsSeeking) {
                                            if (root.musicData && root.musicData.percent !== undefined) {
                                                var p = Number(root.musicData.percent);
                                                if (!isNaN(p)) progBar.value = p;
                                            }
                                        }
                                    }
                                }

                                Behavior on value {
                                    enabled: !progBar.pressed && !root.userIsSeeking
                                    NumberAnimation { duration: 400; easing.type: Easing.OutSine }
                                }

                                onPressedChanged: {
                                    if (pressed) {
                                        root.userIsSeeking = true;
                                        seekDebounceTimer.stop();
                                    } else {
                                        var temp = Object.assign({}, root.musicData);
                                        temp.percent = value;
                                        root.musicData = temp;

                                        var safePlayer = root.musicData.playerName ? root.musicData.playerName : "";
                                        root.execCmd(`${root.scriptsDir}/player_control.sh seek ${value.toFixed(2)} ${root.musicData.length} "${safePlayer}"`);
                                        
                                        seekDebounceTimer.restart();
                                    }
                                }

                                background: Item {
                                    x: progBar.leftPadding
                                    y: progBar.topPadding + (progBar.availableHeight - root.s(12)) / 2
                                    width: progBar.availableWidth
                                    height: root.s(12)

                                    // One clipped track with a single fill rectangle that IS the gradient.
                                    Rectangle {
                                        id: bgTrack
                                        anchors.fill: parent
                                        radius: root.s(6)
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)
                                        clip: true

                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Rectangle {
                                            id: fillTrack
                                            x: 0
                                            y: 0
                                            width: Math.max(0, Math.min(bgTrack.width, progBar.handle.x + progBar.handle.width))
                                            height: bgTrack.height
                                            radius: root.s(6)
                                            opacity: progBar.visualPosition > 0.001 ? 1.0 : 0.0

                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                // Must be a colour THIS file declares - an undefined property renders black.
                                                // Two stops, not three: a straight ramp stays a gradient at every width.
                                                GradientStop { position: 0.0; color: root.blue; Behavior on color { ColorAnimation { duration: 150 } } }
                                                GradientStop { position: 1.0; color: root.pink; Behavior on color { ColorAnimation { duration: 150 } } }
                                            }

                                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    // His hairline over the top of the track.
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: root.s(6)
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 1
                                    }
                                }

                                handle: Rectangle {
                                    x: progBar.leftPadding + progBar.visualPosition * (progBar.availableWidth - width)
                                    y: progBar.topPadding + (progBar.availableHeight - height) / 2
                                    implicitWidth: root.s(18) 
                                    implicitHeight: root.s(18)
                                    width: root.s(18); height: root.s(18)
                                    radius: root.s(9); color: root.text
                                    scale: progBar.pressed ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: root.musicData.positionStr || "00:00"; color: root.overlay2; font.family: Fonts.ui; font.bold: true; font.pixelSize: root.s(13) }
                                Item { Layout.fillWidth: true }
                                Text { text: root.musicData.lengthStr || "00:00"; color: root.overlay2; font.family: Fonts.ui; font.bold: true; font.pixelSize: root.s(13) }
                            }
                        }

                        // MEDIA CONTROLS CHUNK
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: root.s(22)
                            opacity: root.introControls
                            transform: Translate { y: root.s(20) * (1 - root.introControls) }

                            // Real surface, not a bare glyph: rest / hover / press are three
                            // distinct states so the control reads as a button.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: root.s(40); implicitHeight: root.s(40)
                                radius: width / 2
                                color: prevMa.containsMouse ? root.surface1
                                     : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.65)
                                border.width: 1
                                border.color: prevMa.containsMouse
                                            ? Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.45)
                                            : Qt.rgba(root.overlay0.r, root.overlay0.g, root.overlay0.b, 0.25)
                                scale: prevMa.pressed ? 0.90 : (prevMa.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf048"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(15)
                                    color: prevMa.containsMouse ? root.text : root.subtext0
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    transform: Translate { id: prevMaShift }
                                    SequentialAnimation {
                                        id: prevMaDart
                                        NumberAnimation { target: prevMaShift; property: "x"; to: root.s(-7); duration: 110; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: prevMaShift; property: "x"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                    }
                                }
                                MouseArea {
                                    id: prevMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        prevMaDart.restart();
                                        root.execCmd(`${root.scriptsDir}/player_control.sh prev "" "" "${root.musicData.playerName}"`);
                                    }
                                }
                            }

                            // Primary action: filled with the accent, and it breathes on the kick while
                            // playing — same kickLevel the visualiser uses, so the button is on the beat.
                            Rectangle {
                                id: playBtn
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: root.s(58); implicitHeight: root.s(58)
                                radius: width / 2
                                color: playMa.pressed ? Qt.darker(root.blue, 1.12)
                                     : (playMa.containsMouse ? Qt.lighter(root.blue, 1.10) : root.blue)
                                scale: playMa.pressed ? 0.92 : (playMa.containsMouse ? 1.05 : 1.0)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                // Kick rides a transform so it composes with the hover/press scale above
                                // instead of fighting its Behavior every frame.
                                transform: Scale {
                                    origin.x: playBtn.width / 2; origin.y: playBtn.height / 2
                                    xScale: root.musicData.status === "Playing" ? 1 + root.kickLevel * 0.035 : 1
                                    yScale: root.musicData.status === "Playing" ? 1 + root.kickLevel * 0.035 : 1
                                }

                                Rectangle {
                                    id: playPulse
                                    anchors.centerIn: parent
                                    width: parent.width; height: parent.height
                                    radius: width / 2
                                    color: root.blue
                                    opacity: 0
                                    scale: 1
                                    z: -1
                                    NumberAnimation { id: playPulseScaleAnim; target: playPulse; property: "scale"; from: 1.0; to: 1.8; duration: 500; easing.type: Easing.OutQuart }
                                    NumberAnimation { id: playPulseFadeAnim; target: playPulse; property: "opacity"; from: 0.5; to: 0.0; duration: 500; easing.type: Easing.OutQuart }
                                    function trigger() { playPulseScaleAnim.restart(); playPulseFadeAnim.restart(); }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.musicData.status === "Playing" ? "\uf04c" : "\uf04b"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(24)
                                    color: root.base
                                }

                                MouseArea {
                                    id: playMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.userToggledPlay = true;
                                        playDebounceTimer.restart();
                                        var temp = Object.assign({}, root.musicData);
                                        temp.status = (temp.status === "Playing" ? "Paused" : "Playing");
                                        root.musicData = temp;
                                        root.execCmd(`${root.scriptsDir}/player_control.sh play-pause "" "" "${root.musicData.playerName}"`);
                                    }
                                }
                            }

                            // Real surface, not a bare glyph: rest / hover / press are three
                            // distinct states so the control reads as a button.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: root.s(40); implicitHeight: root.s(40)
                                radius: width / 2
                                color: nextMa.containsMouse ? root.surface1
                                     : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.65)
                                border.width: 1
                                border.color: nextMa.containsMouse
                                            ? Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.45)
                                            : Qt.rgba(root.overlay0.r, root.overlay0.g, root.overlay0.b, 0.25)
                                scale: nextMa.pressed ? 0.90 : (nextMa.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf051"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(15)
                                    color: nextMa.containsMouse ? root.text : root.subtext0
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    transform: Translate { id: nextMaShift }
                                    SequentialAnimation {
                                        id: nextMaDart
                                        NumberAnimation { target: nextMaShift; property: "x"; to: root.s(7); duration: 110; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: nextMaShift; property: "x"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                    }
                                }
                                MouseArea {
                                    id: nextMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        nextMaDart.restart();
                                        root.execCmd(`${root.scriptsDir}/player_control.sh next "" "" "${root.musicData.playerName}"`);
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Separator ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(2)
                    Layout.topMargin: root.s(20)
                    Layout.bottomMargin: root.s(20)
                    color: "#1AFFFFFF"
                    radius: root.s(1)

                    opacity: root.introSeparator
                    transform: Translate { y: root.s(15) * (1 - root.introSeparator) }
                }

                // --- Equalizer ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.s(15)

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: root.introEqHeader
                        transform: Translate { y: root.s(15) * (1 - root.introEqHeader) }

                        Rectangle {
                            Layout.preferredHeight: root.s(34)
                            Layout.preferredWidth: sectionRow.implicitWidth + root.s(8)
                            radius: Radius.outer(root.s(11))
                            color: Qt.alpha(root.surface0, 0.6)

                            Row {
                                id: sectionRow
                                anchors.centerIn: parent
                                spacing: root.s(4)

                                SectionTab { idx: 0; glyph: "\u{f062e}"; label: "Equalizer"; tint: root.mauve }
                                SectionTab { idx: 1; glyph: "\u{f0bc2}"; label: "Lyrics";    tint: root.blue }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // --- Lyrics-only header controls ---
                        Rectangle {
                            visible: root.section === 1
                            Layout.preferredHeight: root.s(34)
                            Layout.preferredWidth: offsetRow.implicitWidth + root.s(16)
                            radius: Radius.outer(root.s(11))
                            color: Qt.alpha(root.surface0, 0.6)

                            Row {
                                id: offsetRow
                                anchors.centerIn: parent
                                spacing: root.s(6)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    rightPadding: root.s(2)
                                    text: Lyrics.loading ? "searching" : (Lyrics.backend || "")
                                    color: root.subtext0
                                    font.family: Fonts.ui
                                    font.pixelSize: root.s(10)
                                    opacity: 0.7
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    rightPadding: root.s(2)
                                    // Which highlight is live for this track, so a fall back to lines reads as intended.
                                    text: !Lyrics.hasLyrics ? ""
                                        : !Lyrics.wantWords ? "\u00b7 lines"
                                        : Lyrics.hasWords ? "\u00b7 sing-along"
                                        : Lyrics.hunting ? "\u00b7 sing-along\u2026" : "\u00b7 lines"
                                    visible: text !== ""
                                    color: Lyrics.wantWords && Lyrics.hasWords ? root.blue : root.subtext0
                                    font.family: Fonts.ui
                                    font.pixelSize: root.s(10)
                                    opacity: 0.85
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }

                                NudgeButton { label: "\u2212"; delta: -0.1 }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(40)
                                    text: (Lyrics.offset >= 0 ? "+" : "\u2212")
                                          + Math.abs(Lyrics.offset).toFixed(1) + "s"
                                    color: Math.abs(Lyrics.offset) > 0.001 ? root.blue : root.subtext0
                                    font.family: Fonts.ui
                                    font.pixelSize: root.s(11)
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }

                                NudgeButton { label: "+"; delta: 0.1 }
                            }
                        }
                        
                        // Current preset and the button that commits it, on the
                        // same chassis as the tabs and the lyric offset cluster.
                        Rectangle {
                            visible: root.section === 0
                            Layout.preferredHeight: root.s(34)
                            Layout.preferredWidth: eqHeaderRow.implicitWidth + root.s(16)
                            radius: Radius.outer(root.s(11))
                            color: Qt.alpha(root.surface0, 0.6)

                          Row {
                            id: eqHeaderRow
                            anchors.centerIn: parent
                            spacing: root.s(8)

                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: root.s(22)
                            implicitWidth: applyTxt.implicitWidth
                                           + (root.eqData.pending ? root.s(20) : root.s(6))
                            radius: Radius.outer(root.s(8))
                            color: root.eqData.pending ? root.mauve : "transparent"

                            Behavior on implicitWidth {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            
                            Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            layer.enabled: root.eqData.pending
                            layer.effect: MultiEffect {
                                shadowEnabled: true; shadowColor: root.mauve; shadowOpacity: 0.4; shadowBlur: 0.6
                            }

                            Text {
                                id: applyTxt
                                anchors.centerIn: parent
                                // md-check when there is nothing to do.
                                text: root.eqData.pending ? "Apply" : "\u{f012c}"
                                color: root.eqData.pending ? root.base : root.subtext0
                                opacity: root.eqData.pending ? 1.0 : 0.55
                                font.family: root.eqData.pending ? Fonts.ui
                                                                 : "Iosevka Nerd Font"
                                font.pixelSize: root.eqData.pending ? root.s(11) : root.s(13)
                                font.bold: true
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: root.eqData.pending
                                cursorShape: root.eqData.pending ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.eqData.pending) {
                                        var temp = Object.assign({}, root.eqData);
                                        temp.pending = false;
                                        root.eqData = temp;
                                        
                                        // Blind the polling process to stop it from fetching old data
                                        root.lastEqUpdate = Date.now(); 
                                        
                                        root.triggerEqLightning();
                                        root.execCmd(`${root.scriptsDir}/equalizer.sh apply`);
                                    }
                                }
                            }
                        }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.eqData.preset || "Flat"
                                color: root.subtext0
                                opacity: 0.85
                                font.family: Fonts.ui
                                font.pixelSize: root.s(11)
                                font.bold: true
                            }
                          }
                        }
                    }

                    // Eq Sliders Container with Canvas Lightning Overlay
                    Item {
                        visible: root.section === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(180)

                        Row {
                            id: eqSliderRow
                            anchors.fill: parent
                            z: 1 // Ensures sliders (and their handles) render over the lightning

                            Repeater {
                                model: [
                                    {"idx": 1, "lbl": "31"}, {"idx": 2, "lbl": "63"}, {"idx": 3, "lbl": "125"},
                                    {"idx": 4, "lbl": "250"}, {"idx": 5, "lbl": "500"}, {"idx": 6, "lbl": "1k"},
                                    {"idx": 7, "lbl": "2k"}, {"idx": 8, "lbl": "4k"}, {"idx": 9, "lbl": "8k"},
                                    {"idx": 10, "lbl": "16k"}
                                ]
                                delegate: Item {
                                    id: sliderDelegate
                                    width: eqSliderRow.width / 10 
                                    height: eqSliderRow.height

                                    // --- ENHANCED SLIDER CASCADING ANIMATION ---
                                    opacity: root.introEqSliders
                                    transform: Translate {
                                        y: root.s(30) * (1 - root.introEqSliders) + (index * root.s(8) * (1 - root.introEqSliders))
                                    }

                                    // Mathematical evaluation mapping to the exact timeline of the strike
                                    property real dist: root.eqLightningProgress - (modelData.idx - 1)
                                    property real hitPulse: dist >= 0 && dist < 1.0 ? Math.sin((dist) * Math.PI) : 0.0
                                    
                                    // Massive Energy Pulses
                                    property real trackPulse: 0.0
                                    property real ringPulse: 0.0
                                    property real flashFade: 0.0
                                    property bool hasFired: false

                                    onDistChanged: {
                                        // Reset the fire lock when the animation sweeps past or starts over
                                        if (dist <= 0.05) {
                                            hasFired = false;
                                        } else if (dist > 0.4 && !hasFired) {
                                            // Trigger strictly once per bolt passing over
                                            hasFired = true;
                                            trackPulseAnim.restart();
                                            ringPulseAnim.restart();
                                            flashFadeAnim.restart();
                                        }
                                    }

                                    SequentialAnimation {
                                        id: trackPulseAnim
                                        // Animates the bolt perfectly down the track
                                        NumberAnimation { target: sliderDelegate; property: "trackPulse"; from: 0.0; to: 1.0; duration: 1000; easing.type: Easing.OutQuart }
                                    }
                                    SequentialAnimation {
                                        id: ringPulseAnim
                                        // Explodes outward creating a physical shockwave
                                        NumberAnimation { target: sliderDelegate; property: "ringPulse"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutExpo }
                                    }
                                    SequentialAnimation {
                                        id: flashFadeAnim
                                        // Slowly cools the inner track gradient back to normal
                                        NumberAnimation { target: sliderDelegate; property: "flashFade"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutSine }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: root.s(5)
                                        Slider {
                                            id: eqSlider
                                            Layout.fillHeight: true
                                            Layout.alignment: Qt.AlignHCenter
                                            orientation: Qt.Vertical
                                            from: -12; to: 12
                                            stepSize: 1

                                            Connections {
                                                target: root
                                                function onEqDataChanged() {
                                                    if (!eqSlider.pressed) {
                                                        if (root.eqData && root.eqData["b" + modelData.idx] !== undefined) {
                                                            var p = Number(root.eqData["b" + modelData.idx]);
                                                            if (!isNaN(p)) eqSlider.value = p;
                                                        }
                                                    }
                                                }
                                            }

                                            Behavior on value {
                                                enabled: !eqSlider.pressed
                                                NumberAnimation {
                                                    duration: 350
                                                    easing.type: Easing.OutQuart
                                                }
                                            }

                                            onPressedChanged: {
                                                if (!pressed) {
                                                    var temp = Object.assign({}, root.eqData);
                                                    temp["b" + modelData.idx] = Math.round(value);
                                                    temp.preset = "Custom";
                                                    temp.pending = true;
                                                    root.eqData = temp;
                                                    
                                                    // Set lock here too to protect individual slider tweaks
                                                    root.lastEqUpdate = Date.now();
                                                    
                                                    root.execCmd(`${root.scriptsDir}/equalizer.sh set_band ${modelData.idx} ${Math.round(value)}`);
                                                }
                                            }

                                            background: Rectangle {
                                                id: trackBg
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding
                                                implicitWidth: root.s(10) 
                                                implicitHeight: root.s(150)
                                                width: root.s(10); height: eqSlider.availableHeight
                                                radius: root.s(4); 
                                                
                                                // Dynamic tint: surface0 with 70% opacity for a softer dark look
                                                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)

                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    id: trackEffect
                                                    shadowEnabled: true
                                                    shadowColor: "#000000"
                                                    shadowOpacity: 0.9
                                                    shadowBlur: 0.5
                                                    shadowVerticalOffset: 1
                                                }

                                                // MASSIVE Outer Energy Shockwave Ring 
                                                Rectangle {
                                                    z: -1
                                                    anchors.centerIn: parent
                                                    width: parent.width + root.s(20) + sliderDelegate.ringPulse * root.s(40)
                                                    height: parent.height + root.s(20) + sliderDelegate.ringPulse * root.s(60)
                                                    radius: parent.radius + root.s(10) + sliderDelegate.ringPulse * root.s(20)
                                                    color: "transparent"
                                                    border.color: root.mauve
                                                    border.width: root.s(2) + sliderDelegate.ringPulse * root.s(4)
                                                    opacity: sliderDelegate.ringPulse * 0.8 * (1.0 - root.eqLightningFade)
                                                    
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                // The Track Fill Base (FIXED THE SQUARE CORNERS ISSUE)
                                                Item {
                                                    width: parent.width
                                                    height: (1 - eqSlider.visualPosition) * parent.height
                                                    y: eqSlider.visualPosition * parent.height
                                                    
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: eqFillMask
                                                    }

                                                    Rectangle {
                                                        id: eqFillMask
                                                        anchors.fill: parent
                                                        radius: root.s(4)
                                                        visible: false
                                                        layer.enabled: true 
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent

                                                        // Primary at the base, easing up to the
                                                        // seek bar's other stop. Nothing else.
                                                        gradient: Gradient {
                                                            orientation: Gradient.Vertical
                                                            GradientStop {
                                                                position: 0.0; color: root.pink
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                            GradientStop {
                                                                position: 1.0; color: root.blue
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }

                                                        // Track Override: Changes entire gradient of track
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            opacity: sliderDelegate.flashFade
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: root.mauve }
                                                                GradientStop { position: 0.5; color: root.blue }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                        }

                                                        // The Internal Charging Surge Bolt 
                                                        Rectangle {
                                                            width: parent.width
                                                            height: root.s(80) // Massive physical bolt
                                                            y: (sliderDelegate.trackPulse * (parent.height + height)) - height
                                                            opacity: Math.sin(sliderDelegate.trackPulse * Math.PI) * 2.0 * (1.0 - root.eqLightningFade)
                                                            
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: "transparent" }
                                                                GradientStop { position: 0.2; color: root.blue }
                                                                GradientStop { position: 0.5; color: root.text } // Theme integrated bright center
                                                                GradientStop { position: 0.8; color: root.mauve }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                            
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true; shadowColor: root.blue; shadowBlur: 1.0; shadowOpacity: 1.0
                                                            }
                                                        }
                                                    }
                                                }

                                                // Painted after the fill so it sits on top of it rather than behind.
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width
                                                    height: parent.height
                                                            * root.eqLevel(modelData.idx - 1)
                                                    radius: parent.radius
                                                    color: root.text
                                                    opacity: root.musicData.status === "Playing" ? 0.30 : 0.0

                                                    Behavior on height {
                                                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                                                    }
                                                    Behavior on opacity { NumberAnimation { duration: 400 } }
                                                }
                                            }

                                            handle: Rectangle {
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                                implicitWidth: root.s(18)
                                                implicitHeight: root.s(18)
                                                width: root.s(18); height: root.s(18)
                                                radius: root.s(9); color: root.text

                                                property var catColors: [root.mauve, root.pink, root.lavender, root.mauve, root.blue]

                                                // Core glow flare that cleanly fades out matching the canvas
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width + root.s(36) * sliderDelegate.hitPulse // Bigger bloom
                                                    height: width
                                                    radius: width / 2
                                                    color: parent.catColors[index % parent.catColors.length]
                                                    opacity: sliderDelegate.hitPulse * (1.0 - root.eqLightningFade)
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                // Pop the handle itself slightly as the beam passes
                                                scale: 1.0 + (sliderDelegate.hitPulse * 0.4 * (1.0 - root.eqLightningFade))
                                            }
                                        }
                                        Text {
                                            text: modelData.lbl
                                            color: root.overlay1
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(10)
                                            font.bold: true
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }

                        // --- THE FLUID CANVAS LIGHTNING (Optimized for Realism and multiple waves) ---
                        Canvas {
                            id: lightningCanvas
                            anchors.fill: parent
                            opacity: 1.0 - root.eqLightningFade
                            z: 0 // Draw securely behind the sliders

                            // Force hardware FBO backend instead of slow software rendering
                            renderTarget: Canvas.FramebufferObject 

                            // GPU Layer effect to provide bloom WITHOUT locking up the CPU via ctx.shadowBlur
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: root.mauve
                                shadowBlur: 1.0 // 1.0 is max blur in MultiEffect
                                shadowOpacity: 0.6
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                            }

                            Timer {
                                interval: 16 // ~60fps for silky smooth arcs
                                running: root.eqLightningFade < 1.0 && root.eqLightningProgress > 0.0
                                repeat: true
                                onTriggered: lightningCanvas.requestPaint()
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                if (root.eqLightningProgress <= 0.0 || root.eqLightningFade >= 1.0) return;

                                var time = Date.now() / 1000;
                                var maxIdx = root.eqLightningProgress; // 0 to 9

                                ctx.lineJoin = "round";
                                ctx.lineCap = "round";

                                // Step 1: Map the spatial coordinates of the 10 handles
                                var pts = [];
                                for (var i = 1; i <= 10; i++) {
                                    var val = root.eqData["b" + i] !== undefined ? Number(root.eqData["b" + i]) : 0;
                                    var norm = 1.0 - ((val + 12) / 24);
                                    
                                    // Py uses margins rough mapping to the handles visible track
                                    var py = root.s(10) + norm * (height - root.s(35)); 
                                    var px = (i - 0.5) * (width / 10);
                                    pts.push({ x: px, y: py });
                                }

                                // Strands: 0 mauve glow, 1 pink glow, 2 crackling core, 3 hot white core.
                                for (var s = 0; s < 4; s++) { 
                                    ctx.beginPath();
                                    ctx.moveTo(pts[0].x, pts[0].y);

                                    for (var i = 0; i < pts.length - 1; i++) {
                                        if (i > maxIdx) break; // Stop drawing ahead of current progress

                                        var p1 = pts[i];
                                        var p2 = pts[i+1];

                                        var fraction = 1.0;
                                        if (maxIdx < i + 1) {
                                            fraction = maxIdx - i;
                                        }

                                        // Subdivision steps create the crackle noise
                                        var steps = s === 3 ? 6 : 8; // Ultra smooth subdivision, s=3 core has less subdiv for straighter look
                                        for (var j = 1; j <= steps; j++) {
                                            var t = j / steps;
                                            if (t > fraction) t = fraction;

                                            var cx = p1.x + (p2.x - p1.x) * t;
                                            var cy = p1.y + (p2.y - p1.y) * t;

                                            // Wave calculations: create distinct arcs and noise branching
                                            var envelope = Math.sin(t * Math.PI);

                                            // s=3 core noise (straightest) to s=0 outer glow noise (most waves)
                                            var noiseAmpX = s === 3 ? 1.0 : (4 - s) * 4; 
                                            var noiseAmpY = s === 3 ? 1.0 : (4 - s) * 5; 
                                            
                                            // Combine multiple frequencies for complex branching/crackle appearance
                                            // Glow strands (0, 1) also get a sweeping sine wave applied to create distinct separating waves
                                            var sepWaveX = (s < 2) ? Math.sin(time * 3 + i + j + s) * root.s(10) * envelope : 0;
                                            var sepWaveY = (s < 2) ? Math.cos(time * 2.5 + i - j - s) * root.s(15) * envelope : 0;

                                            // Primary erratic crackle noise using high frequency combined sine/cos
                                            var noiseX = Math.sin(time * (10+s) + i + j) * Math.cos(time * 8 - i + j) * noiseAmpX * envelope * (1 - root.eqLightningFade);
                                            var noiseY = Math.cos(time * (9-s) + i - j) * Math.sin(time * 7 + i - j) * noiseAmpY * envelope * (1 - root.eqLightningFade);

                                            ctx.lineTo(cx + sepWaveX + noiseX, cy + sepWaveY + noiseY);

                                            if (t === fraction) break;
                                        }
                                    }

                                    // Step 3: Theme and render each distinct strand
                                    if (s === 0) { // Massive Sweeping Outer Glow (Mauve)
                                        ctx.lineWidth = root.s(20);
                                        ctx.strokeStyle = root.mauve;
                                        ctx.globalAlpha = 0.2;
                                    } else if (s === 1) { // Medium Sweeping Wave (Pink)
                                        ctx.lineWidth = root.s(8);
                                        ctx.strokeStyle = root.pink;
                                        ctx.globalAlpha = 0.45;
                                    } else if (s === 2) { // Tight erratic core (Lavender)
                                        ctx.lineWidth = root.s(3.5);
                                        ctx.strokeStyle = root.lavender;
                                        ctx.globalAlpha = 0.85;
                                    } else if (s === 3) { // Pure white straight hot core - heavily transparent
                                        ctx.lineWidth = root.s(1.0);
                                        ctx.strokeStyle = "#ffffff";
                                        ctx.globalAlpha = 0.1;
                                    }

                                    ctx.stroke();
                                }
                            }
                        }
                    }

                    // The buttons ARE the chips: a chassis stretched around eight reads as a slab.
                    ColumnLayout {
                        visible: root.section === 0
                        Layout.fillWidth: true
                        spacing: root.s(8)

                        opacity: root.introPresets
                        transform: Translate { y: root.s(20) * (1 - root.introPresets) }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)
                            Repeater {
                                model: ["Flat", "Bass", "Treble", "Vocal"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)
                            Repeater {
                                model: ["Pop", "Rock", "Jazz", "Classic"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                    }

                    // --- Lyrics --- exactly the height the sliders + presets occupy
                    // (180 + 15 + 72), so switching sections leaves the outline untouched.
                    Item {
                        visible: root.section === 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(267)

                        opacity: root.introEqSliders
                        transform: Translate { y: root.s(15) * (1 - root.introEqSliders) }

                        ListView {
                            id: lyricsView
                            anchors.fill: parent
                            visible: Lyrics.hasLyrics
                            clip: true

                            model: Lyrics.lines
                            // -1 means playback is before the first line; nothing highlights.
                            currentIndex: Math.max(0, Lyrics.currentIndex)

                            // Pins the active line to the middle band and animates the column to it.
                            highlightRangeMode: ListView.StrictlyEnforceRange
                            preferredHighlightBegin: height / 2 - root.s(26)
                            preferredHighlightEnd: height / 2 + root.s(26)
                            highlightMoveDuration: 420
                            highlightMoveVelocity: -1

                            delegate: Item {
                                id: lyricRow
                                width: lyricsView.width
                                height: Math.max(root.s(34), (wordsLive ? wordFlow.height : lyricText.implicitHeight) + root.s(14))

                                readonly property bool isCurrent: index === Lyrics.currentIndex
                                readonly property int distance: Math.abs(index - Lyrics.currentIndex)
                                // Sing-along: the current line is laid out word by word so each lights on its cue.
                                readonly property bool wordsLive: isCurrent && Lyrics.wantWords && !!modelData.words

                                Text {
                                    id: lyricText
                                    anchors.centerIn: parent
                                    width: parent.width - root.s(28)

                                    // Empty lines are the instrumental gaps; the
                                    // LRC keeps them and so do we, marked.
                                    text: (modelData.text && modelData.text.length) ? modelData.text : "\u266a"

                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    font.family: Fonts.ui
                                    font.pixelSize: lyricRow.isCurrent ? root.s(16) : root.s(14)
                                    font.bold: lyricRow.isCurrent
                                    color: lyricRow.isCurrent ? root.blue : root.subtext0
                                    opacity: lyricRow.wordsLive ? 0.0
                                           : lyricRow.isCurrent ? 1.0
                                           : Math.max(0.22, 0.62 - lyricRow.distance * 0.14)

                                    Behavior on opacity { NumberAnimation { duration: 260 } }
                                    Behavior on color { ColorAnimation { duration: 260 } }
                                    Behavior on font.pixelSize {
                                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                                    }
                                }

                                // Rows are broken and centred by hand: a Flow cannot centre its rows and a
                                // wrapped Text cannot colour one word at a time.
                                Item {
                                    id: wordFlow
                                    anchors.centerIn: parent
                                    width: parent.width - root.s(28)
                                    opacity: lyricRow.wordsLive ? 1.0 : 0.0
                                    visible: opacity > 0

                                    Behavior on opacity { NumberAnimation { duration: 260 } }

                                    readonly property real spaceW: spaced.advanceWidth - unspaced.advanceWidth
                                    TextMetrics { id: spaced; font.family: Fonts.ui; font.pixelSize: root.s(16); font.bold: true; text: "a a" }
                                    TextMetrics { id: unspaced; font.family: Fonts.ui; font.pixelSize: root.s(16); font.bold: true; text: "aa" }

                                    onWidthChanged: relayout()

                                    function relayout() {
                                        var n = wordRep.count, items = [];
                                        for (var i = 0; i < n; i++) {
                                            var it = wordRep.itemAt(i);
                                            if (!it) return;
                                            items.push(it);
                                        }
                                        if (n === 0) { height = 0; return; }
                                        var maxW = width, sp = spaceW, lineH = items[0].implicitHeight;
                                        var rows = [[]], x = 0;
                                        for (i = 0; i < n; i++) {
                                            var w = items[i].implicitWidth;
                                            var lead = (i > 0 && /^\s/.test(items[i].raw)) ? sp : 0;
                                            if (x > 0 && x + lead + w > maxW) { rows.push([]); x = 0; lead = 0; }
                                            x += lead;
                                            items[i].x = x;
                                            items[i].y = (rows.length - 1) * lineH;
                                            rows[rows.length - 1].push(items[i]);
                                            x += w + (/\s$/.test(items[i].raw) ? sp : 0);
                                        }
                                        var first = ("" + lyricText.text).match(/[A-Za-z\u00c0-\u024f\u0370-\u08ff]/);
                                        var rtl = !!first && /[\u0590-\u08ff]/.test(first[0]);
                                        for (var r = 0; r < rows.length; r++) {
                                            var row = rows[r], a = row[0], b = row[row.length - 1];
                                            var off = (maxW - (b.x + b.implicitWidth - a.x)) / 2 - a.x;
                                            for (var k = 0; k < row.length; k++) {
                                                row[k].x += off;
                                                if (rtl) row[k].x = maxW - row[k].x - row[k].implicitWidth;
                                            }
                                        }
                                        height = rows.length * lineH;
                                    }

                                    Repeater {
                                        id: wordRep
                                        model: lyricRow.wordsLive ? modelData.words : []
                                        onItemAdded: wordFlow.relayout()

                                        delegate: Text {
                                            readonly property string raw: "" + modelData.text
                                            // How far the clock is into this word, 0..1 over its own length.
                                            readonly property real prog: {
                                                var e = Lyrics.lyricTime - modelData.t;
                                                return e <= 0 ? 0 : Math.min(1, e / Math.max(0.12, modelData.d));
                                            }
                                            text: raw.trim()
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(16)
                                            font.bold: true
                                            color: root.mixColor(root.subtext0, root.blue, 1 - (1 - prog) * (1 - prog))

                                            Behavior on color { ColorAnimation { duration: 70 } }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.seekToLyric(index)
                                }
                            }
                        }

                        // The helper ranks and returns options alongside the failure.
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(6)
                            visible: !Lyrics.hasLyrics
                            spacing: root.s(6)

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Lyrics.loading
                                      ? "Searching for lyrics"
                                      : (Lyrics.candidates.length > 0
                                         ? "No exact match \u2014 pick one"
                                         : "No lyrics found")
                                color: root.subtext0
                                font.family: Fonts.ui
                                font.pixelSize: root.s(13)
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: !Lyrics.loading && Lyrics.candidates.length === 0
                                         && Lyrics.reason !== ""
                                text: Lyrics.reason
                                color: root.subtext0
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                font.family: Fonts.ui
                                font.pixelSize: root.s(11)
                            }

                            // Seeded with whatever the player reported, then
                            // edited down to the real artist and song.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: root.s(2)
                                spacing: root.s(6)
                                visible: !Lyrics.loading && Lyrics.title !== ""

                                QueryField {
                                    id: artistField
                                    placeholder: "Artist"
                                    Layout.preferredWidth: root.s(112)
                                }

                                QueryField {
                                    id: titleField
                                    placeholder: "Song"
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    implicitWidth: findText.implicitWidth + root.s(20)
                                    implicitHeight: root.s(26)
                                    radius: Radius.outer(root.s(8))
                                    color: findMa.containsMouse ? root.blue
                                                                : Qt.alpha(root.surface2, 0.5)

                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Text {
                                        id: findText
                                        anchors.centerIn: parent
                                        text: Lyrics.searching ? "\u2026" : "Find"
                                        color: findMa.containsMouse ? root.base : root.subtext0
                                        font.family: Fonts.ui
                                        font.pixelSize: root.s(11)
                                        font.bold: true
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    MouseArea {
                                        id: findMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runManualSearch()
                                    }
                                }
                            }

                            // Refill the boxes whenever the track changes; the
                            // user's edits survive until then.
                            Connections {
                                target: Lyrics
                                function onTitleChanged() {
                                    artistField.text = Lyrics.artist;
                                    titleField.text = Lyrics.title;
                                }
                            }

                            ListView {
                                id: candList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !Lyrics.loading && Lyrics.candidates.length > 0
                                clip: true
                                spacing: root.s(4)
                                boundsBehavior: Flickable.StopAtBounds
                                model: Lyrics.candidates

                                delegate: Rectangle {
                                    width: candList.width
                                    height: root.s(36)
                                    radius: Radius.outer(root.s(8))
                                    color: candMa.containsMouse ? root.surface1
                                                                : Qt.alpha(root.surface0, 0.5)

                                    Behavior on color { ColorAnimation { duration: 160 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(10)
                                        anchors.rightMargin: root.s(10)
                                        spacing: root.s(8)

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: candMa.containsMouse ? root.text : root.subtext0
                                                elide: Text.ElideRight
                                                font.family: Fonts.ui
                                                font.pixelSize: root.s(11)
                                                font.bold: true
                                                Behavior on color { ColorAnimation { duration: 160 } }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.artist
                                                color: root.subtext0
                                                opacity: 0.6
                                                elide: Text.ElideRight
                                                font.family: Fonts.ui
                                                font.pixelSize: root.s(9)
                                            }
                                        }

                                        Text {
                                            visible: modelData.hasWords === true
                                            text: "\u266a words"
                                            color: root.blue
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(9)
                                        }

                                        Text {
                                            text: modelData.backend
                                            color: root.blue
                                            opacity: 0.7
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(9)
                                        }
                                    }

                                    MouseArea {
                                        id: candMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Lyrics.pick(modelData)
                                    }
                                }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: retryText.implicitWidth + root.s(26)
                                implicitHeight: root.s(26)
                                radius: Radius.outer(root.s(8))
                                visible: !Lyrics.loading && Lyrics.title !== ""
                                         && Lyrics.candidates.length === 0
                                color: retryMa.containsMouse ? root.blue : Qt.alpha(root.surface2, 0.5)

                                Behavior on color { ColorAnimation { duration: 200 } }

                                Text {
                                    id: retryText
                                    anchors.centerIn: parent
                                    text: "Search again"
                                    color: retryMa.containsMouse ? root.base : root.subtext0
                                    font.family: Fonts.ui
                                    font.pixelSize: root.s(11)
                                    font.bold: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                MouseArea {
                                    id: retryMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Lyrics.refresh()
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Keys are invisible otherwise; one dim line beats a legend.
                // Matches the hint the volume popup carries.
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.section === 0
                          ? "1\u20138 presets   [ ] cycle   0 flat   \u21e5 section"
                          : (Lyrics.hasLyrics
                             ? ", . offset   R refetch   \u21e5 section   click a line to seek"
                             : "edit the query \u2192 Find   click a result to use it   \u21e5 section")
                    font.family: Fonts.ui
                    font.pixelSize: root.s(9)
                    color: Qt.alpha(root.overlay0, 0.75)
                    elide: Text.ElideRight
                    opacity: root.introPresets
                }
            }
        }
    }

    // --- Section switcher tab --- same chassis as the volume popup's tabs.
    component SectionTab : Rectangle {
        id: tab

        property int idx: 0
        property string glyph: ""
        property string label: ""
        property color tint: root.blue
        readonly property bool isActive: root.section === idx

        width: tabContent.implicitWidth + root.s(20)
        height: root.s(26)
        radius: Radius.outer(root.s(9))
        color: isActive ? tint : (tabMa.containsMouse ? root.surface1 : "transparent")

        Behavior on color { ColorAnimation { duration: 180 } }

        Row {
            id: tabContent
            anchors.centerIn: parent
            spacing: root.s(7)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tab.glyph
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(13)
                color: tab.isActive ? root.base : root.subtext0
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tab.label
                font.family: Fonts.ui
                font.weight: Font.Bold
                font.pixelSize: root.s(11)
                color: tab.isActive ? root.base : root.subtext0
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }

        MouseArea {
            id: tabMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.section = tab.idx
        }
    }

    // TextInput, not Controls.TextField: the styled control brings its own palette.
    component QueryField : Rectangle {
        id: qf

        property string placeholder: ""
        property alias text: qfInput.text
        property alias hasFocus: qfInput.activeFocus

        implicitHeight: root.s(26)
        radius: Radius.outer(root.s(8))
        color: qfInput.activeFocus ? Qt.alpha(root.surface2, 0.7)
                                   : Qt.alpha(root.surface0, 0.6)
        border.width: 1
        border.color: qfInput.activeFocus ? root.blue : "transparent"

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        TextInput {
            id: qfInput
            anchors.fill: parent
            anchors.leftMargin: root.s(9)
            anchors.rightMargin: root.s(9)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            color: root.text
            selectionColor: root.blue
            selectedTextColor: root.base
            font.family: Fonts.ui
            font.pixelSize: root.s(11)

            onAccepted: root.runManualSearch()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: qfInput.text === ""
                text: qf.placeholder
                color: root.subtext0
                opacity: 0.45
                font.family: Fonts.ui
                font.pixelSize: root.s(11)
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.IBeamCursor
        }
    }

    // --- LYRIC OFFSET NUDGE ---
    component NudgeButton : Rectangle {
        id: nudge

        property string label: ""
        property real delta: 0

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: root.s(22)
        implicitHeight: root.s(22)
        radius: width / 2
        color: nudgeMa.containsMouse ? root.blue : Qt.alpha(root.surface2, 0.5)
        scale: nudgeMa.pressed ? 0.86 : 1.0

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: nudge.label
            color: nudgeMa.containsMouse ? root.base : root.subtext0
            font.family: Fonts.ui
            font.pixelSize: root.s(13)
            font.bold: true
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        MouseArea {
            id: nudgeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Lyrics.nudge(nudge.delta)
        }
    }

    // --- HELPER COMPONENT FOR PRESETS ---
    component PresetButton : Rectangle {
        property string name: ""
        Layout.fillWidth: true
        Layout.preferredHeight: root.s(32)
        radius: Radius.outer(root.s(9))

        property bool isActivePreset: root.eqData && root.eqData.preset === name
        property bool isHovered: hoverMa.containsMouse

        color: isActivePreset ? root.mauve
             : (isHovered ? root.surface1 : Qt.alpha(root.surface0, 0.55))
        scale: isHovered && !isActivePreset ? 1.04 : 1.0

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: parent.name
            color: parent.isActivePreset ? root.base : (parent.isHovered ? root.text : root.subtext0)
            font.family: Fonts.ui
            font.pixelSize: root.s(12)
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            id: hoverMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applyPresetOptimistically(parent.name)
        }
    }
}
