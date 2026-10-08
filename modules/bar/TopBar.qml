// The bar: one PanelWindow per screen. barWindow carries the data plumbing (pollers,
// settings, style chrome); barContent is serpantinum v2's placement engine on our
// widgets: bar.modules {left, center, right}, groups as nested arrays, every widget
// declared statically (its blur Region stays static) and placed from target sizes.
import "widgets"
import "../../services/audio"
import "../../services/bar"
import "../../services/caching"
import "../../services/cava"
import "../../services/layout"
import "../../services/network"
import "../../services/settings"
import "../../services/theme"
import "../notifcenter"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import "../../services/bar/BarModules.js" as BarModules

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: barWindow
            // Project root on disk, for invoking our KDE watcher/bridge scripts.
            readonly property string shellPath: ("" + Quickshell.shellDir).replace(/^file:\/\//, "")

            Caching { id: paths }

            IpcHandler {
                target: "topbar"
                function forceReload() { Quickshell.reload(true) }
            }

            required property var modelData
            screen: modelData

            property string barPosition: "" + ShellSettings.value("bar.position", "top")
            readonly property bool isVertical: barPosition === "left" || barPosition === "right"

            anchors {
                top: barWindow.isVertical || barWindow.barPosition === "top"
                bottom: barWindow.isVertical || barWindow.barPosition === "bottom"
                left: !barWindow.isVertical || barWindow.barPosition === "left"
                right: !barWindow.isVertical || barWindow.barPosition === "right"
            }

            Scaler {
                id: scaler
                // A vertical bar's own width is just the thickness; scale from the screen.
                currentWidth: barWindow.isVertical ? barWindow.screen.width : barWindow.width
                // bar.size shrinks or grows every widget, since they all size through s().
                uiScale: Number(ShellSettings.value("ui.scale", 1.0))
                         * Math.max(0.6, Math.min(1.4, Number(ShellSettings.value("bar.size", 1.0)) || 1.0))
            }

            property real baseScale: scaler.baseScale
            function s(val) { return scaler.s(val); }

            property int barHeight: s(48)

            // Popups clear the bar using this, wherever it sits.
            Binding { target: BarState; property: "edgeGap"; value: barWindow.barHeight + barWindow.s(20) }
            Binding { target: BarState; property: "solid"; value: barWindow.isSolid }
            Binding { target: BarState; property: "hidden"; value: barWindow.autohide || barWindow.fullscreenActive }
            Binding { target: BarState; property: "slabThickness"; value: barWindow.barHeight + (barWindow.isFill ? 0 : barWindow.s(8)) }
            Binding { target: BarState; property: "bandThickness"; value: barWindow.barHeight + (barWindow.isFill ? barWindow.s(14) : barWindow.s(8)) }

            // --- bar.* settings (v2 schema; old topbar.* keys read as fallback) ---
            property string barStyle: "" + ShellSettings.value("bar.style", "modular")
            readonly property bool isSolid: barStyle === "solid" || barStyle === "fill"
            readonly property bool isFill: barStyle === "fill"
            // Pill corners follow ui.radius; controls inside a pill sit 2px in, as upstream.
            readonly property real pillRadius: Radius.outer(s(14))
            readonly property real innerRadius: Radius.inset(s(10), s(2))
            property bool distinctPills: ShellSettings.value("bar.distinctPills", false) === true
            property real barOpacity: Number(ShellSettings.value("bar.opacity", 85)) / 100
            property bool autohide: ShellSettings.value("bar.autohide", false) === true
            property int autohideTimeout: Number(ShellSettings.value("bar.autohideTimeout", 1000))
            property real barWidthPercent: Number(ShellSettings.value("bar.width", 100))
            property bool fitWidth: ShellSettings.value("bar.fitWidth", false) === true
            readonly property string timeFormat: "" + ShellSettings.value("bar.time.format", "HH:mm:ss")

            // Pill chrome shared by every section. Solid styles swallow the pill
            // backgrounds unless distinctPills keeps the segmented look.
            readonly property color pillBg: isSolid
                ? (distinctPills ? Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.6) : "transparent")
                : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, barOpacity)
            readonly property real pillBorderAlpha: isSolid ? 0 : 1

            implicitHeight: isVertical ? 0 : barHeight + (isFill ? s(14) : 0)
            implicitWidth: isVertical ? barHeight + (isFill ? s(14) : 0) : 0
            // 8px off the bar's own edge, 4px along it; fill sits flush.
            margins {
                top: barWindow.isFill ? 0 : (barWindow.barPosition === "top" ? s(8) : (barWindow.isVertical ? s(4) : 0))
                bottom: barWindow.isFill ? 0 : (barWindow.barPosition === "bottom" ? s(8) : (barWindow.isVertical ? s(4) : 0))
                left: barWindow.isFill ? 0 : (barWindow.barPosition === "left" ? s(8) : (barWindow.isVertical ? 0 : s(4)))
                right: barWindow.isFill ? 0 : (barWindow.barPosition === "right" ? s(8) : (barWindow.isVertical ? 0 : s(4)))
            }
            exclusiveZone: autohide ? 0 : barHeight
            color: "transparent"

            // Hide the bar and release its space when the focused window is fullscreen.
            property bool fullscreenActive: false
            visible: !fullscreenActive

            // --- autohide ---
            property bool barRevealed: !autohide || barHover.hovered || hideTimer.running
            HoverHandler { id: barHover }
            Timer { id: hideTimer; interval: barWindow.autohideTimeout }
            Connections {
                target: barHover
                function onHoveredChanged() {
                    if (!barHover.hovered && barWindow.autohide) hideTimer.restart();
                    else hideTimer.stop();
                }
            }
            // While hidden only a thin strip at the edge takes input, so windows
            // underneath stay clickable. null mask = whole window (autohide off).
            mask: autohide ? autohideMask : null
            Region {
                id: autohideMask
                x: (barWindow.barPosition === "right" && !barWindow.barRevealed) ? barWindow.width - 4 : 0
                y: (barWindow.barPosition === "bottom" && !barWindow.barRevealed) ? barWindow.height - 4 : 0
                width: barWindow.barRevealed ? barWindow.width : (barWindow.isVertical ? 4 : barWindow.width)
                height: barWindow.barRevealed ? barWindow.height : (barWindow.isVertical ? barWindow.height : 4)
            }

            // Blur behind each pill only, so the gaps between pills keep the segmented
            // look; solid styles blur the one slab instead. Every widget and group
            // background is a static item, so this list is static too.
            Region {
                id: pillsRegion
                item: actionsW
                radius: barWindow.pillRadius
                Region { item: workspacesW; radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: mediaW;      radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: timedateW;   radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: weatherW;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: trayW;       radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: kbW;         radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: networkW;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: awakeW;      radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: powerW;      radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: btW;         radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: volW;        radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: notifW;      radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: focusW;      radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: infoW;       radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: visW;        radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: sysmonW;     radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg0;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg1;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg2;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg3;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg4;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
                Region { item: groupBg5;    radius: barWindow.pillRadius; intersection: Intersection.Combine }
            }
            Region {
                id: solidRegion
                item: solidBackground
                radius: barWindow.isFill ? 0 : barWindow.pillRadius
            }
            readonly property bool blurEnabled: ShellSettings.value("bar.blur", false) === true
            BackgroundEffect.blurRegion: (!blurEnabled || (autohide && !barRevealed)) ? null
                                         : (isSolid ? solidRegion : pillsRegion)

            MatugenColors { id: mocha }

            // --- recording (any PipeWire screencast), polled 2s; start time for the info widget ---
            property bool isRecording: false
            property real recStartEpoch: 0
            property real nowTick: Date.now()
            onIsRecordingChanged: if (isRecording) { recStartEpoch = Date.now(); nowTick = Date.now(); }
            Timer { interval: 1000; repeat: true; running: barWindow.isRecording; onTriggered: barWindow.nowTick = Date.now() }
            Process {
                id: recPoller
                command: ["bash", barWindow.shellPath + "/helpers/screencast-check.sh"]
                stdout: StdioCollector { onStreamFinished: barWindow.isRecording = (this.text.trim() === "1") }
            }
            Timer {
                interval: 2000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: { recPoller.running = false; recPoller.running = true; }
            }

            property bool isDesktop: false
            readonly property string ethStatus: Net.ethStatus
            readonly property bool vpnActive: Net.vpnActive

            Process {
                id: chassisDetector
                running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector { onStreamFinished: barWindow.isDesktop = (this.text.trim() === "desktop") }
            }

            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }

            property bool startupCascadeFinished: false
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }

            property bool fastPollerLoaded: false
            property bool isDataReady: fastPollerLoaded
            Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }

            // The status pills cascade in once the data is there.
            property bool statusRevealed: false
            Timer { running: barWindow.isStartupReady && barWindow.isDataReady; interval: 250; onTriggered: barWindow.statusRevealed = true }

            property string timeStr: ""
            property string hourStr: ""
            property string minuteStr: ""
            property string fullDateStr: ""
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)

            property string weatherIcon: ""
            property string weatherTemp: "--°"
            property string weatherHex: mocha.yellow

            readonly property string wifiIcon: Net.linkIcon
            readonly property string wifiSsid: Net.wifiSsid

            // From Quickshell's native Bluetooth module.
            readonly property var btAdapter: Bluetooth.defaultAdapter
            readonly property bool btPresent: btAdapter !== null && btAdapter !== undefined
            readonly property bool btEnabled: btPresent && btAdapter.enabled
            readonly property var btConnectedDev: {
                if (!btEnabled || !btAdapter.devices) return null;
                var v = btAdapter.devices.values;
                for (var i = 0; i < v.length; i++)
                    if (v[i] && v[i].connected) return v[i];
                return null;
            }
            property string btStatus: btEnabled ? "on" : "off"
            property string btIcon: btConnectedDev ? "\u{f00b1}" : (btEnabled ? "\u{f00af}" : "\u{f00b2}")
            property string btDevice: btConnectedDev ? (btConnectedDev.deviceName || "") : ""

            // Straight from PipeWire (Audio tracks every node).
            readonly property var audioSink: Audio.defaultSink
            readonly property int volPct: audioSink && audioSink.audio ? Math.round(audioSink.audio.volume * 100) : 0
            readonly property bool isMuted: audioSink && audioSink.audio ? audioSink.audio.muted : false
            readonly property string volPercent: volPct + "%"
            readonly property string volIcon: (isMuted || volPct === 0) ? "\u{f075f}"
                                               : volPct < 34 ? "\u{f057f}" : volPct < 67 ? "\u{f0580}" : "\u{f057e}"

            property string kbLayout: "us"

            ListModel {
                id: workspacesModel
                property int activeIndex: 0
            }

            property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }
            property string displayTitle: ""
            property string displayTime: ""
            property string displayArtUrl: ""
            onMusicDataChanged: {
                if (musicData && musicData.status !== "Stopped" && musicData.title !== "") {
                    displayTitle = musicData.title;
                    displayTime = musicData.timeStr;
                    displayArtUrl = musicData.artUrl;
                }
            }

            property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
            // Presence AND radio: Networking.wifiEnabled reads true on a box with no adapter.
            readonly property bool isWifiOn: Net.wifiPresent && Net.radioOn
            property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
            property bool showEthernet: barWindow.ethStatus === "Connected" || (barWindow.isDesktop && !barWindow.isWifiOn)
            property bool isSoundActive: !barWindow.isMuted && barWindow.volPct > 0

            // cava only needs to run while something plays and the visualiser is on the bar.
            Binding { target: Cava; property: "isPlaying"; value: barWindow.musicData.status === "Playing"; when: visW.placed }

            Process {
                id: wsDaemon
                command: ["python3", "-u", barWindow.shellPath + "/helpers/ws-bridge.py"]
                running: true
            }

            Process {
                id: wsReader
                running: true
                command: ["cat", paths.getRunDir("workspaces") + "/workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let newData = JSON.parse(txt);
                                while (workspacesModel.count < newData.length) workspacesModel.append({ "wsId": "", "wsState": "" });
                                while (workspacesModel.count > newData.length) workspacesModel.remove(workspacesModel.count - 1);
                                let newActive = -1;
                                for (let i = 0; i < newData.length; i++) {
                                    if (newData[i].state === "active") newActive = i;
                                    if (workspacesModel.get(i).wsState !== newData[i].state) workspacesModel.setProperty(i, "wsState", newData[i].state);
                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                }
                                if (newActive !== -1 && workspacesModel.activeIndex !== newActive) workspacesModel.activeIndex = newActive;
                            } catch(e) {}
                        }
                    }
                }
            }

            Process {
                id: wsWatcher
                running: true
                command: ["bash", "-c", "setpriv --pdeathsig KILL inotifywait -qq -e close_write,modify " + paths.getRunDir("workspaces") + "/workspaces.json"]
                onExited: {
                    wsReader.running = false; wsReader.running = true;
                    running = false; running = true;
                }
            }

            Process {
                id: musicForceRefresh
                running: true
                command: ["bash", "-c", "bash " + barWindow.shellPath + "/helpers/music_info.sh | tee " + paths.getRunDir("music") + "/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") { try { barWindow.musicData = JSON.parse(txt); } catch(e) {} }
                    }
                }
            }
            function refreshMusic() { musicForceRefresh.running = true }

            Timer {
                interval: 1000
                running: barWindow.musicData !== null && barWindow.musicData.status === "Playing"
                repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;
                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;
                    let posParts = parts[0].split(":").map(Number);
                    let lenParts = parts[1].split(":").map(Number);
                    let posSecs = (posParts.length === 3) ? (posParts[0] * 3600 + posParts[1] * 60 + posParts[2]) : (posParts[0] * 60 + posParts[1]);
                    let lenSecs = (lenParts.length === 3) ? (lenParts[0] * 3600 + lenParts[1] * 60 + lenParts[2]) : (lenParts[0] * 60 + lenParts[1]);
                    if (isNaN(posSecs) || isNaN(lenSecs)) return;
                    posSecs++;
                    if (posSecs > lenSecs) posSecs = lenSecs;
                    let newPosStr = "";
                    if (posParts.length === 3) {
                        let h = Math.floor(posSecs / 3600), m = Math.floor((posSecs % 3600) / 60), s = posSecs % 60;
                        newPosStr = h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    } else {
                        let m = Math.floor(posSecs / 60), s = posSecs % 60;
                        newPosStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }
                    let newData = Object.assign({}, barWindow.musicData);
                    newData.timeStr = newPosStr + " / " + parts[1];
                    newData.positionStr = newPosStr;
                    if (lenSecs > 0) newData.percent = (posSecs / lenSecs) * 100;
                    barWindow.musicData = newData;
                }
            }

            Process {
                id: mprisWatcher
                running: true
                command: ["bash", "-c", "bash " + barWindow.shellPath + "/helpers/mpris-wait.sh"]
                onExited: {
                    musicForceRefresh.running = false; musicForceRefresh.running = true;
                    running = false; running = true;
                }
            }

            Timer {
                id: artRetryTimer
                interval: 500
                repeat: true
                running: barWindow.displayArtUrl && barWindow.displayArtUrl.indexOf("placeholder_blank.png") !== -1
                onTriggered: { musicForceRefresh.running = false; musicForceRefresh.running = true; }
            }

            Process {
                id: kbPoller; running: true
                command: ["bash", "-c", barWindow.shellPath + "/helpers/kb-fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "" && barWindow.kbLayout !== txt) barWindow.kbLayout = txt;
                        kbWaiter.running = false; kbWaiter.running = true;
                        barWindow.fastPollerLoaded = true;
                    }
                }
            }
            Process { id: kbWaiter; command: ["bash", "-c", barWindow.shellPath + "/helpers/kb-wait.sh"]; onExited: { kbPoller.running = false; kbPoller.running = true; } }

            // Fullscreen state (hide-on-fullscreen). ws-bridge writes 0/1 to
            // runDir/fullscreen on every active-window/fullscreen change.
            Process {
                id: fsPoller; running: true
                command: ["bash", "-c", "cat " + paths.runDir + "/fullscreen 2>/dev/null || echo 0"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.fullscreenActive = (this.text.trim() === "1");
                        fsWaiter.running = false; fsWaiter.running = true;
                    }
                }
            }
            Process {
                id: fsWaiter
                command: ["bash", "-c", "F=" + paths.runDir + "/fullscreen; while [ ! -f \"$F\" ]; do sleep 1; done; setpriv --pdeathsig KILL inotifywait -qq -e close_write,modify \"$F\""]
                onExited: { fsPoller.running = false; fsPoller.running = true; }
            }

            Process {
                id: weatherPoller
                command: ["bash", "-c", `
                    W="${barWindow.shellPath}/helpers/weather.sh"
                    bash "$W" --current-icon
                    bash "$W" --current-temp
                    bash "$W" --current-hex
                `]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length >= 3) {
                            barWindow.weatherIcon = lines[0];
                            barWindow.weatherTemp = lines[1];
                            barWindow.weatherHex = lines[2] || mocha.yellow;
                        }
                    }
                }
            }
            Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { weatherPoller.running = false; weatherPoller.running = true; } }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    let d = new Date();
                    barWindow.timeStr = Qt.formatDateTime(d, barWindow.timeFormat);
                    barWindow.hourStr = Qt.formatDateTime(d, barWindow.timeFormat.indexOf("hh") !== -1 ? "hh" : "HH");
                    barWindow.minuteStr = Qt.formatDateTime(d, "mm");
                    barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length) barWindow.typeInIndex = barWindow.fullDateStr.length;
                }
            }
            onTimeFormatChanged: barWindow.timeStr = Qt.formatDateTime(new Date(), barWindow.timeFormat)

            Timer {
                id: typewriterTimer
                interval: 40
                running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
                repeat: true
                onTriggered: barWindow.typeInIndex += 1
            }

            // --- the slab and the placement engine ----------------------------------------
            Item {
                id: barContent
                readonly property bool vertical: barWindow.isVertical

                // --- bar.modules (ids, aliases, defaults: services/bar/BarModules.js) ---
                readonly property var modulesRaw: ShellSettings.value("bar.modules", null)
                readonly property var modules: BarModules.parse(modulesRaw, function (k) { return ShellSettings.value("bar.widgets." + k, true) !== false; })
                readonly property var leftArr: modules.left
                readonly property var centerArr: modules.center
                readonly property var rightArr: modules.right
                readonly property var flatLeft: BarModules.flat(leftArr)
                readonly property var flatCenter: BarModules.flat(centerArr)
                readonly property var flatRight: BarModules.flat(rightArr)
                readonly property var groupDefs: {
                    var d = [];
                    var all = [leftArr, centerArr, rightArr];
                    for (var a = 0; a < all.length; a++) for (var i = 0; i < all[a].length; i++) if (Array.isArray(all[a][i])) d.push(all[a][i]);
                    return d;
                }

                function isPlaced(id) { return flatLeft.indexOf(id) !== -1 || flatCenter.indexOf(id) !== -1 || flatRight.indexOf(id) !== -1; }
                function isGrouped(id) {
                    for (var g = 0; g < groupDefs.length; g++) if (groupDefs[g].indexOf(id) !== -1) return true;
                    return false;
                }
                function widgetFor(id) {
                    switch (id) {
                    case "actions": return actionsW;     case "workspaces": return workspacesW;
                    case "media": return mediaW;         case "timedate": return timedateW;
                    case "weather": return weatherW;     case "tray": return trayW;
                    case "kb": return kbW;               case "network": return networkW;
                    case "awake": return awakeW;         case "power": return powerW;
                    case "bt": return btW;               case "vol": return volW;
                    case "notif": return notifW;         case "focus": return focusW;
                    case "info": return infoW;           case "vis": return visW;
                    case "sysmon": return sysmonW;
                    }
                    return null;
                }
                // Target sizes, never animated ones. natural: the media pill before any squeeze,
                // so the fit maths below cannot loop through `compact`.
                function sizeOf(id, natural) {
                    var w = widgetFor(id);
                    if (!w) return 0;
                    if (natural && id === "media" && !vertical) return w.naturalWidth;
                    return vertical ? w.targetHeight : w.targetWidth;
                }

                // --- section math ----------------------------------------------------------
                readonly property real gap: barWindow.s(4)
                readonly property real groupGap: barWindow.s(8)
                readonly property real groupPad: barWindow.s(10)
                readonly property real sectionGap: barWindow.s(10)
                readonly property real inset: barWindow.isSolid ? barWindow.s(4) : 0

                function sectionSize(arr, natural) {
                    var total = 0, count = 0;
                    for (var i = 0; i < arr.length; i++) {
                        if (Array.isArray(arr[i])) {
                            var gw = 0, n = 0;
                            for (var j = 0; j < arr[i].length; j++) {
                                var w = sizeOf(arr[i][j], natural);
                                if (w > 0) { if (n > 0) gw += groupGap; gw += w; n++; }
                            }
                            if (n > 0) { total += gw + groupPad * 2; count++; }
                        } else {
                            var w2 = sizeOf(arr[i], natural);
                            if (w2 > 0) { total += w2; count++; }
                        }
                    }
                    return total + (count > 1 ? gap * (count - 1) : 0);
                }

                readonly property real lSize: sectionSize(leftArr, false)
                readonly property real cSize: sectionSize(centerArr, false)
                readonly property real rSize: sectionSize(rightArr, false)
                readonly property real lcGap: (lSize > 0 && cSize > 0) ? sectionGap : 0
                readonly property real crGap: (cSize > 0 && rSize > 0) ? sectionGap : 0
                readonly property real length: vertical ? height : width
                readonly property real minEdge: inset
                readonly property real maxEdge: length - inset

                // The System Panel packs the bar's centre and right away from itself (v2's "sys"
                // state); bar.packForPanel turns it off.
                readonly property bool packForPanel: ShellSettings.value("bar.packForPanel", false) === true
                readonly property bool packLeft: packForPanel && NotifCenterState.open && !vertical
                readonly property real cNatural: packLeft ? minEdge + lSize + lcGap : (length - cSize) / 2
                readonly property real cMin: lSize > 0 ? minEdge + lSize + lcGap : minEdge
                readonly property real cMax: rSize > 0 ? maxEdge - rSize - crGap - cSize : maxEdge - cSize
                readonly property real cPos: cMin <= cMax ? Math.max(cMin, Math.min(cMax, cNatural))
                                                          : Math.max(minEdge, Math.min(maxEdge - cSize, cNatural))
                readonly property real lPos: minEdge
                readonly property real rPacked: cSize > 0 ? cPos + cSize + crGap : (lSize > 0 ? lPos + lSize + sectionGap : minEdge)
                readonly property real rPos: rSize <= 0 ? maxEdge
                                           : (packLeft ? Math.min(maxEdge - rSize, rPacked) : maxEdge - rSize)

                function modulePos(id) {
                    var arr, base;
                    if (flatLeft.indexOf(id) !== -1) { arr = leftArr; base = lPos; }
                    else if (flatCenter.indexOf(id) !== -1) { arr = centerArr; base = cPos; }
                    else if (flatRight.indexOf(id) !== -1) { arr = rightArr; base = rPos; }
                    else return 0;
                    var offset = 0;
                    for (var i = 0; i < arr.length; i++) {
                        var item = arr[i];
                        if (Array.isArray(item)) {
                            var n = 0, off = offset + groupPad;
                            for (var j = 0; j < item.length; j++) {
                                var w = sizeOf(item[j], false);
                                if (item[j] === id) { if (n > 0) off += groupGap; return base + off; }
                                if (w > 0) { if (n > 0) off += groupGap; off += w; n++; }
                            }
                            if (n > 0) offset = off + groupPad + gap;
                        } else {
                            if (item === id) return base + offset;
                            var w2 = sizeOf(item, false);
                            if (w2 > 0) offset += w2 + gap;
                        }
                    }
                    return base;
                }

                // --- the slab: bar.width clusters the content into the middle N% of the edge ---
                readonly property real widthFrac: barWindow.isFill ? 1 : barWindow.barWidthPercent / 100
                readonly property real requestedW: (barWindow.fitWidth && !barWindow.isFill) ? 0 : Math.round(parent.width * widthFrac)
                readonly property real neededW: sectionSize(leftArr, true) + sectionSize(centerArr, true) + sectionSize(rightArr, true)
                    + lcGap + crGap + inset * 2
                readonly property bool squeezed: !vertical && !barWindow.fitWidth && requestedW < Math.min(neededW, parent.width)
                // Squeeze drops the media text first; past that the bar floors at its content.
                width: vertical ? barWindow.barHeight
                     : Math.max(requestedW, Math.min(neededW - (squeezed ? mediaW.compactSaving : 0), parent.width))
                height: vertical ? Math.round(parent.height * widthFrac) : barWindow.barHeight
                x: barWindow.barPosition === "right" ? parent.width - width
                 : barWindow.barPosition === "left" ? 0
                 : Math.round((parent.width - width) / 2)
                y: barWindow.barPosition === "bottom" ? parent.height - height
                 : barWindow.barPosition === "top" ? 0
                 : Math.round((parent.height - height) / 2)

                // Autohide slides the whole bar off its edge.
                transform: Translate {
                    x: (barWindow.barRevealed || !barWindow.isVertical) ? 0
                       : (barWindow.barPosition === "left" ? -(barWindow.width + barWindow.s(12)) : barWindow.width + barWindow.s(12))
                    y: (barWindow.barRevealed || barWindow.isVertical) ? 0
                       : (barWindow.barPosition === "top" ? -(barWindow.height + barWindow.s(12)) : barWindow.height + barWindow.s(12))
                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                }

                Rectangle {
                    id: solidBackground
                    visible: barWindow.isSolid
                    z: -2
                    anchors.fill: parent
                    radius: barWindow.isFill ? 0 : barWindow.pillRadius
                    color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, barWindow.barOpacity)
                }

                // Concave fillets that let the fill style hug the screen edge.
                EdgeCorner {
                    visible: barWindow.isFill
                    barWindow: barWindow
                    mocha: mocha
                    vertexX: barWindow.barPosition === "right" ? "right" : "left"
                    vertexY: barWindow.barPosition === "bottom" ? "bottom" : "top"
                    x: barWindow.isVertical ? (barWindow.barPosition === "left" ? parent.width : -width) : 0
                    y: barWindow.isVertical ? 0 : (barWindow.barPosition === "top" ? parent.height : -height)
                }
                EdgeCorner {
                    visible: barWindow.isFill
                    barWindow: barWindow
                    mocha: mocha
                    vertexX: barWindow.isVertical ? (barWindow.barPosition === "right" ? "right" : "left") : "right"
                    vertexY: barWindow.isVertical ? "bottom" : (barWindow.barPosition === "bottom" ? "bottom" : "top")
                    x: barWindow.isVertical ? (barWindow.barPosition === "left" ? parent.width : -width) : parent.width - width
                    y: barWindow.isVertical ? parent.height - height : (barWindow.barPosition === "top" ? parent.height : -height)
                }

                // One pill behind each group, spanning its first to last visible member.
                // A static pool so the blur Regions above can reference them.
                component GroupBg : Rectangle {
                    property var ids: []
                    readonly property var m: {
                        var first = -1, last = -1, lastW = 0;
                        for (var i = 0; i < ids.length; i++) {
                            var w = barContent.sizeOf(ids[i], false);
                            if (w <= 0) continue;
                            var p = barContent.modulePos(ids[i]);
                            if (first < 0) first = p;
                            last = p; lastW = w;
                        }
                        if (first < 0) return { pos: 0, size: 0 };
                        return { pos: first - barContent.groupPad, size: last + lastW - first + barContent.groupPad * 2 };
                    }
                    visible: m.size > 0 && (!barWindow.isSolid || barWindow.distinctPills)
                    x: barContent.vertical ? 0 : m.pos
                    y: barContent.vertical ? m.pos : (barContent.height - height) / 2
                    width: barContent.vertical ? barContent.width : m.size
                    height: barContent.vertical ? m.size : barWindow.barHeight
                    z: -1
                    radius: barWindow.pillRadius
                    color: barWindow.pillBg
                    border.width: 1
                    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08 * barWindow.pillBorderAlpha)
                    Behavior on x { enabled: barWindow.startupCascadeFinished && !barContent.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: barWindow.startupCascadeFinished && barContent.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on width { enabled: barWindow.startupCascadeFinished && !barContent.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on height { enabled: barWindow.startupCascadeFinished && barContent.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
                GroupBg { id: groupBg0; ids: barContent.groupDefs.length > 0 ? barContent.groupDefs[0] : [] }
                GroupBg { id: groupBg1; ids: barContent.groupDefs.length > 1 ? barContent.groupDefs[1] : [] }
                GroupBg { id: groupBg2; ids: barContent.groupDefs.length > 2 ? barContent.groupDefs[2] : [] }
                GroupBg { id: groupBg3; ids: barContent.groupDefs.length > 3 ? barContent.groupDefs[3] : [] }
                GroupBg { id: groupBg4; ids: barContent.groupDefs.length > 4 ? barContent.groupDefs[4] : [] }
                GroupBg { id: groupBg5; ids: barContent.groupDefs.length > 5 ? barContent.groupDefs[5] : [] }

                // --- the widgets, one static instance each ---------------------------------
                Actions {
                    id: actionsW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("actions"); grouped: barContent.isGrouped("actions")
                    targetX: barContent.modulePos("actions"); targetY: barContent.modulePos("actions")
                }
                Workspaces {
                    id: workspacesW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    workspacesModel: workspacesModel
                    shown: barContent.isPlaced("workspaces"); placed: shown; grouped: barContent.isGrouped("workspaces")
                    targetX: barContent.modulePos("workspaces"); targetY: barContent.modulePos("workspaces")
                }
                MediaPill {
                    id: mediaW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    shown: barContent.isPlaced("media"); placed: shown; grouped: barContent.isGrouped("media")
                    compact: barContent.squeezed
                    targetX: barContent.modulePos("media"); targetY: barContent.modulePos("media")
                }
                TimeDate {
                    id: timedateW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("timedate"); grouped: barContent.isGrouped("timedate")
                    targetX: barContent.modulePos("timedate"); targetY: barContent.modulePos("timedate")
                }
                Weather {
                    id: weatherW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("weather"); grouped: barContent.isGrouped("weather")
                    targetX: barContent.modulePos("weather"); targetY: barContent.modulePos("weather")
                }
                TrayPill {
                    id: trayW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    shown: barContent.isPlaced("tray"); placed: shown; grouped: barContent.isGrouped("tray")
                    targetX: barContent.modulePos("tray"); targetY: barContent.modulePos("tray")
                }
                Kb {
                    id: kbW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("kb"); grouped: barContent.isGrouped("kb")
                    targetX: barContent.modulePos("kb"); targetY: barContent.modulePos("kb")
                    revealed: barWindow.statusRevealed; revealDelay: 0
                }
                NetworkPill {
                    id: networkW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("network"); grouped: barContent.isGrouped("network")
                    targetX: barContent.modulePos("network"); targetY: barContent.modulePos("network")
                    revealed: barWindow.statusRevealed; revealDelay: 50
                }
                Awake {
                    id: awakeW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("awake"); grouped: barContent.isGrouped("awake")
                    targetX: barContent.modulePos("awake"); targetY: barContent.modulePos("awake")
                    revealed: barWindow.statusRevealed; revealDelay: 100
                }
                PowerPill {
                    id: powerW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("power"); grouped: barContent.isGrouped("power")
                    targetX: barContent.modulePos("power"); targetY: barContent.modulePos("power")
                    revealed: barWindow.statusRevealed; revealDelay: 100
                }
                Bt {
                    id: btW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("bt"); grouped: barContent.isGrouped("bt")
                    targetX: barContent.modulePos("bt"); targetY: barContent.modulePos("bt")
                    revealed: barWindow.statusRevealed; revealDelay: 100
                }
                Vol {
                    id: volW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("vol"); grouped: barContent.isGrouped("vol")
                    targetX: barContent.modulePos("vol"); targetY: barContent.modulePos("vol")
                    revealed: barWindow.statusRevealed; revealDelay: 150
                }
                Notif {
                    id: notifW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("notif"); grouped: barContent.isGrouped("notif")
                    targetX: barContent.modulePos("notif"); targetY: barContent.modulePos("notif")
                    revealed: barWindow.statusRevealed; revealDelay: 200
                }
                FocusPill {
                    id: focusW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("focus"); grouped: barContent.isGrouped("focus")
                    targetX: barContent.modulePos("focus"); targetY: barContent.modulePos("focus")
                }
                InfoPill {
                    id: infoW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("info"); grouped: barContent.isGrouped("info")
                    targetX: barContent.modulePos("info"); targetY: barContent.modulePos("info")
                }
                Vis {
                    id: visW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("vis"); grouped: barContent.isGrouped("vis")
                    targetX: barContent.modulePos("vis"); targetY: barContent.modulePos("vis")
                }
                SysMon {
                    id: sysmonW
                    barWindow: barWindow; mocha: mocha; vertical: barContent.vertical
                    placed: barContent.isPlaced("sysmon"); grouped: barContent.isGrouped("sysmon")
                    targetX: barContent.modulePos("sysmon"); targetY: barContent.modulePos("sysmon")
                }
            }
        }
    }
}
