// serpantinum v2's screenshot overlay on KDE (see NOTICE). The screen is frozen once when
// the overlay opens (helpers/kwinshot, falling back to spectacle), the selection is drawn
// over that image, and helpers/screenshot.sh crops the freeze - so the saved file is the
// pixels that were selected. Video mode hands the same selection to gpu-screen-recorder.

import "../../services/caching"
import "../../services/layout"
import "../../services/record"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot"
    WlrLayershell.keyboardFocus: root.armed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: root.armed
    screen: root.targetScreen

    // --- Scaling + theme ----------------------------------------------------
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    Caching { id: paths }
    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color mauve:    _theme.mauve
    readonly property color red:      _theme.red
    readonly property color green:    _theme.green

    readonly property real radius: Radius.outer(8)
    readonly property color dimColor: Qt.alpha(crust, 0.72)

    // Take the shot as soon as the region drag ends, instead of requiring a second
    // click on the toolbar shutter. Off by default.
    readonly property bool captureOnRelease: ShellSettings.value("screenshot.captureOnRelease", false) === true

    // --- Lifecycle ----------------------------------------------------------
    readonly property bool wanted: ScreenshotState.open
    property bool armed: false
    property bool isLoading: false
    property bool animateChanges: false
    property bool isEditMode: false
    property string freezeImg: ""
    // Once the helper has the freeze it owns the file, so we must not delete it.
    property bool freezeHandedOff: false

    property string freezePath: ""
    property bool freezeStarted: false
    property bool freezeFromKwinshot: false
    // kwinshot needs an installed KWin grant; without one it fails once, then spectacle.
    property bool kwinshotUsable: true
    property bool kwinshotPending: false

    readonly property string shellRoot: ("" + Quickshell.shellDir).replace(/^file:\/\//, "")
    readonly property string helper: root.shellRoot + "/helpers/screenshot.sh"
    readonly property string kwinshot: root.shellRoot + "/helpers/kwinshot/kwinshot"
    readonly property string runPath: paths.getRunDir("screenshot")
    readonly property string cachePath: paths.getCacheDir("screenshot")

    property string targetMonitorName: ""
    readonly property var targetScreen: {
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === root.targetMonitorName)
                return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    readonly property real screenW: root.screen ? root.screen.width : root.width
    readonly property real screenH: root.screen ? root.screen.height : root.height

    // What kwinshot captures: this output's rect in KWin's logical workspace coordinates.
    readonly property string screenRect: {
        let sc = root.targetScreen;
        if (!sc || sc.width <= 0 || sc.height <= 0) return "";
        return `${Math.round(sc.x)},${Math.round(sc.y)} ${Math.round(sc.width)}x${Math.round(sc.height)}`;
    }

    // The freeze is this monitor at whatever resolution the capture produced; selection
    // coords are logical, so everything handed to magick goes through this.
    readonly property real freezeScale: (freezeBackground.sourceSize.width > 0 && root.width > 0)
        ? freezeBackground.sourceSize.width / root.width
        : (root.devicePixelRatio || 1.0)

    onWantedChanged: { if (root.wanted) root.begin(); else root.finish(); }

    function begin() {
        if (outputProc.running || kwinshotProc.running || freezeProc.running
            || freezeCheckProc.running) return;
        isLoading = true;
        isEditMode = ScreenshotState.editMode;
        isVideoMode = false;
        isMaximized = false;
        isSelecting = false;
        isScanningQr = false;
        showQrPopup = false;
        freezeHandedOff = false;
        animateChanges = false;
        qrModel.clear();
        loadCachedRegion();
        recHdr = ShellSettings.value("record.hdr", true) === true;
        recAudio = "" + ShellSettings.value("record.audio", "system");
        if (audioModes.indexOf(recAudio) < 0) recAudio = "system";
        RecordState.refreshHdr();
        isLoading = false;
        // After loading, so the mode change still preselects the screen over the cached region.
        isVideoMode = ScreenshotState.videoMode;

        freezeStarted = false;
        freezePath = root.runPath + "/freeze_" + Date.now() + ".png";
        // kwinshot captures a named output, so the freeze waits on this answer (~2 ms).
        outputProc.running = true;
    }

    function finish() {
        // A cancelled capture is not kwinshot's fault, so stop the watchdog before it fires.
        kwinshotWatchdog.stop();
        armed = false;
        animateChanges = false;
        isSelecting = false;
        isScanningQr = false;
        showQrPopup = false;
        hasSelection = false;
        if (freezeImg !== "" && !freezeHandedOff)
            Quickshell.execDetached(["rm", "-f", freezeImg]);
        freezeImg = "";
    }

    // qs ipc call screenshot state: what the overlay thinks it is doing, for the freeze hunt.
    function debugState() {
        return JSON.stringify({
            wanted: root.wanted, armed: root.armed, visible: root.visible,
            backingWindowVisible: root.backingWindowVisible,
            width: root.width, height: root.height, screen: root.screen ? root.screen.name : null,
            keyboardFocus: root.WlrLayershell.keyboardFocus,
            activeFocus: root.contentItem ? root.contentItem.activeFocus : null,
            freezeImg: root.freezeImg, freezePath: root.freezePath, freezeStarted: root.freezeStarted,
            freezeFromKwinshot: root.freezeFromKwinshot, kwinshotUsable: root.kwinshotUsable,
            kwinshotPending: root.kwinshotPending, imageStatus: freezeBackground.status,
            procs: { output: outputProc.running, kwinshot: kwinshotProc.running,
                     spectacle: freezeProc.running, check: freezeCheckProc.running, qr: qrProc.running },
            isSelecting: root.isSelecting, hasSelection: root.hasSelection, isVideoMode: root.isVideoMode,
            recHdr: root.recHdr, recAudio: root.recAudio, hdrAvailable: root.hdrAvailable,
            regionString: root.regionString, fullScreenSelected: root.fullScreenSelected,
            sinceToggleMs: Date.now() - ScreenshotState.lastToggle
        });
    }

    function grabFocus() {
        if (!root.armed || !root.contentItem) return;
        root.contentItem.forceActiveFocus();
    }

    // KWin's own idea of the focused output; kscreen-doctor cannot answer this.
    Process {
        id: outputProc
        command: ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
                  "--object-path", "/KWin", "--method", "org.kde.KWin.activeOutputName"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = ("" + this.text).match(/'([^']*)'/);
                root.targetMonitorName = m ? m[1] : "";
                root.startFreeze();
            }
        }
        // A binary that cannot start emits no output and no `exited`, only running: false.
        onRunningChanged: { if (!outputProc.running) root.startFreeze(); }
    }

    function dropFreeze() {
        if (root.freezePath !== "") Quickshell.execDetached(["rm", "-f", root.freezePath]);
    }

    function freezeFailed() {
        root.dropFreeze();
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Screenshot",
                                 "Screenshot failed", "spectacle could not capture the screen."]);
        ScreenshotState.hide();
    }

    function armOverlay() {
        root.freezeImg = root.freezePath;
        // The target output is only known now; a video open preselected it before that.
        if (root.isVideoMode) root.selectWholeScreen();
        root.armed = true;
        // The freeze is not instant, so re-arm the re-press guard from when the UI appears.
        ScreenshotState.lastToggle = Date.now();
        root.grabFocus();
        Qt.callLater(root.grabFocus);
        Qt.callLater(() => { root.animateChanges = true; });
    }

    // Freeze once, before the overlay maps (otherwise it is in its own screenshot), and
    // never re-freeze afterwards. kwinshot asks KWin directly; spectacle costs ~210 ms.
    function startFreeze() {
        if (root.freezeStarted || !root.wanted) return;
        root.freezeStarted = true;
        root.freezeFromKwinshot = root.kwinshotUsable && root.screenRect !== "";
        if (!root.freezeFromKwinshot) {
            root.startSpectacle();
            return;
        }
        kwinshotProc.command = [root.kwinshot, "--geometry", root.screenRect,
                                "--out", root.freezePath];
        root.kwinshotPending = true;
        // Armed first, because a helper that cannot start resolves inside the next line.
        kwinshotWatchdog.restart();
        kwinshotProc.running = true;
    }

    function startSpectacle() {
        freezeProc.command = ["spectacle", "-b", "-n", "-m", "-o", root.freezePath];
        freezeProc.running = true;
    }

    // A half-written freeze is dropped and the retry gets its own path, so nothing the
    // abandoned kwinshot still holds open can reach spectacle's file.
    function fallBackToSpectacle() {
        root.dropFreeze();
        if (!root.wanted) return;
        root.freezeFromKwinshot = false;
        root.freezePath = root.runPath + "/freeze_" + Date.now() + ".png";
        root.startSpectacle();
    }

    function kwinshotDone(ok) {
        if (!root.kwinshotPending) return;
        root.kwinshotPending = false;
        kwinshotWatchdog.stop();
        if (!root.wanted) {
            root.dropFreeze();
            return;
        }
        if (ok) {
            freezeCheckProc.running = true;
            return;
        }
        root.kwinshotUsable = false;
        root.fallBackToSpectacle();
    }

    Process {
        id: kwinshotProc
        onExited: (exitCode) => root.kwinshotDone(exitCode === 0)
        // An unbuilt helper never emits `exited`; running just drops back to false.
        onRunningChanged: { if (!kwinshotProc.running) root.kwinshotDone(false); }
    }

    // A wedged capture would otherwise hold the shortcut for kwinshot's own 4 s ceiling.
    Timer {
        id: kwinshotWatchdog
        interval: 500
        onTriggered: {
            if (!root.kwinshotPending) return;
            root.kwinshotPending = false;
            root.kwinshotUsable = false;
            kwinshotProc.running = false;
            root.fallBackToSpectacle();
        }
    }

    Process {
        id: freezeProc
        onExited: (exitCode) => {
            if (!root.wanted) {
                root.dropFreeze();
                return;
            }
            if (exitCode !== 0) root.freezeFailed();
            else freezeCheckProc.running = true;
        }
    }

    // spectacle exits 0 without writing the file when a second instance is already live,
    // so the exit code alone does not prove there is a freeze to draw on.
    Process {
        id: freezeCheckProc
        command: ["test", "-s", root.freezePath]
        onExited: (exitCode) => {
            if (!root.wanted) {
                root.dropFreeze();
                return;
            }
            if (exitCode === 0) {
                root.armOverlay();
                return;
            }
            if (root.freezeFromKwinshot) {
                root.kwinshotUsable = false;
                root.fallBackToSpectacle();
                return;
            }
            root.freezeFailed();
        }
    }

    // --- Region, remembered across opens ------------------------------------
    FileView {
        id: geometryFile
        path: root.cachePath + "/geometry"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    function loadCachedRegion() {
        geometryFile.reload();
        let parts = ("" + geometryFile.text()).trim().split(",");
        let n = parts.map(p => parseFloat(p));
        let ok = parts.length === 4 && n.every(v => isFinite(v) && v >= 0) && n[2] > 10 && n[3] > 10;
        root.startX = ok ? n[0] : 0;
        root.startY = ok ? n[1] : 0;
        root.endX = ok ? root.startX + n[2] : 0;
        root.endY = ok ? root.startY + n[3] : 0;
        root.hasSelection = ok;
        root.preStartX = root.startX; root.preStartY = root.startY;
        root.preEndX = root.endX; root.preEndY = root.endY;
    }

    function saveCache() {
        if (!root.hasSelection || root.isVideoMode) return;
        geometryFile.setText(Math.round(root.selX) + "," + Math.round(root.selY) + ","
                             + Math.round(root.selW) + "," + Math.round(root.selH));
    }

    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0

    Behavior on startX { enabled: root.animateChanges && !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on startY { enabled: root.animateChanges && !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on endX { enabled: root.animateChanges && !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on endY { enabled: root.animateChanges && !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

    property bool hasSelection: false
    property bool isSelecting: false
    property bool isMaximized: false
    property real preStartX: 0
    property real preStartY: 0
    property real preEndX: 0
    property real preEndY: 0

    readonly property real selX: Math.min(startX, endX)
    readonly property real selY: Math.min(startY, endY)
    readonly property real selW: Math.abs(endX - startX)
    readonly property real selH: Math.abs(endY - startY)

    // Pixels inside the freeze, not the Wayland layout: the helper crops that one image.
    readonly property string geometryString:
        `${Math.round(selX * freezeScale)},${Math.round(selY * freezeScale)} ${Math.round(selW * freezeScale)}x${Math.round(selH * freezeScale)}`

    property int interactionMode: 0
    property real anchorX: 0; property real anchorY: 0
    property real initX: 0; property real initY: 0
    property real initW: 0; property real initH: 0

    property bool isScanningQr: false
    property bool showQrPopup: false
    property bool isQrSuccess: false
    ListModel { id: qrModel }

    function selectWholeScreen() {
        root.startX = 0; root.startY = 0;
        root.endX = root.screenW; root.endY = root.screenH;
        root.hasSelection = true;
    }

    function toggleMaximize() {
        if (!isMaximized) {
            preStartX = root.startX; preStartY = root.startY;
            preEndX = root.endX; preEndY = root.endY;
            root.selectWholeScreen();
            isMaximized = true;
        } else {
            root.startX = preStartX; root.startY = preStartY;
            root.endX = preEndX; root.endY = preEndY;
            isMaximized = false;
        }
        root.saveCache();
    }

    // --- Video: a whole-screen selection is GSR's zero-copy output path, so the mode starts there.
    property bool isVideoMode: false
    // Parked photo region; kept apart from maximize's pre* so F11 in video mode cannot clobber it.
    property rect photoRegion: Qt.rect(0, 0, 0, 0)

    property bool recHdr: true
    property string recAudio: "system"
    readonly property var audioModes: ["off", "system", "system+mic"]
    readonly property bool hdrAvailable: RecordState.isHdr(root.targetMonitorName)

    function setRecHdr(v) {
        if (v === root.recHdr) return;
        root.recHdr = v;
        ShellSettings.setValue("record.hdr", v);
    }

    function setRecAudio(v) {
        if (v === root.recAudio) return;
        root.recAudio = v;
        ShellSettings.setValue("record.audio", v);
    }

    readonly property bool fullScreenSelected:
        Math.abs(selX) <= 1 && Math.abs(selY) <= 1
        && Math.abs(selW - root.width) <= 1 && Math.abs(selH - root.height) <= 1

    // GSR's -region in logical global coordinates, unlike geometryString's freeze pixels.
    readonly property string regionString: {
        let sc = root.targetScreen;
        let ox = sc ? sc.x : 0, oy = sc ? sc.y : 0;
        return `${Math.round(selW)}x${Math.round(selH)}+${Math.round(ox + selX)}+${Math.round(oy + selY)}`;
    }

    onIsVideoModeChanged: {
        if (root.isLoading) return;
        root.isMaximized = false;

        if (root.isVideoMode) {
            root.photoRegion = Qt.rect(root.startX, root.startY, root.endX - root.startX, root.endY - root.startY);
            root.selectWholeScreen();
        } else {
            let r = root.photoRegion;
            root.startX = r.x; root.startY = r.y;
            root.endX = r.x + r.width; root.endY = r.y + r.height;
            root.hasSelection = Math.abs(r.width) >= 10 && Math.abs(r.height) >= 10;
        }
    }

    function startRecording() {
        if (!root.hasSelection) return;
        RecordState.start({
            output: root.targetMonitorName,
            region: root.fullScreenSelected ? "" : root.regionString,
            hdr: root.hdrAvailable && root.recHdr,
            audio: root.recAudio
        });
        ScreenshotState.hide();
    }

    function videoAction() {
        if (RecordState.recording) {
            RecordState.stop();
            ScreenshotState.hide();
        } else {
            root.startRecording();
        }
    }

    // --- Capture ------------------------------------------------------------
    function capture(openEditor) {
        if (!root.hasSelection || root.freezeImg === "") return;
        let args = ["bash", root.helper, "--geometry", root.geometryString, "--freeze", root.freezeImg];
        if (openEditor) args.push("--edit");
        root.freezeHandedOff = true;
        root.animateChanges = false;
        Quickshell.execDetached(args);
        ScreenshotState.hide();
    }

    Shortcut { sequence: "Escape"; enabled: root.armed; onActivated: ScreenshotState.hide() }
    Shortcut { sequence: "Return"; enabled: root.armed; onActivated: { if (root.isVideoMode) root.videoAction(); else root.capture(root.isEditMode) } }
    Shortcut { sequence: "Space"; enabled: root.armed; onActivated: { if (root.isVideoMode) root.videoAction(); else root.capture(root.isEditMode) } }
    Shortcut { sequence: "Tab"; enabled: root.armed; onActivated: root.isVideoMode = !root.isVideoMode }
    Shortcut { sequence: "Left"; enabled: root.armed; onActivated: root.isVideoMode = false }
    Shortcut { sequence: "Right"; enabled: root.armed; onActivated: root.isVideoMode = true }
    Shortcut { sequence: "F11"; enabled: root.armed; onActivated: root.toggleMaximize() }
    // The record shortcut while the overlay is already up switches it to video mode.
    Connections { target: ScreenshotState; function onVideoModeChanged() { if (root.armed && ScreenshotState.videoMode) root.isVideoMode = true } }

    component AnimWrap: Item {
        property bool isShown: false
        property real contentWidth: 0
        property real rightPadding: s(6)
        property real targetWidth: contentWidth + rightPadding

        width: isShown ? targetWidth : 0
        height: parent.height
        opacity: isShown ? 1.0 : 0.0
        clip: true

        Behavior on width { enabled: root.animateChanges; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
        Behavior on opacity { enabled: root.animateChanges; NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
        visible: width > 0

        default property alias content: internalWrapper.children
        Item {
            id: internalWrapper
            width: contentWidth
            height: parent.height
        }
    }

    Image {
        id: freezeBackground
        z: 0
        anchors.fill: parent
        source: root.freezeImg !== "" ? ("file://" + root.freezeImg) : ""
        asynchronous: false
        cache: false
        fillMode: Image.PreserveAspectCrop
    }

    Item {
        id: overlayContent
        anchors.fill: parent

        Item {
            anchors.fill: parent
            z: 1

            Rectangle {
                anchors.fill: parent
                color: root.dimColor
                opacity: (!root.isSelecting && !root.hasSelection) ? 1.0 : 0.0
                Behavior on opacity { enabled: root.animateChanges; NumberAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: root.isVideoMode ? "Drag a region, or record the whole screen" : "Select a region to capture"
                    font.family: Fonts.ui; font.weight: Font.DemiBold; font.pixelSize: s(24); color: root.text
                }
            }
            Item {
                anchors.fill: parent
                opacity: (root.isSelecting || root.hasSelection) ? 1.0 : 0.0
                Behavior on opacity { enabled: root.animateChanges; NumberAnimation { duration: 150 } }
                Rectangle { x: 0; y: 0; width: parent.width; height: root.selY; color: root.dimColor }
                Rectangle { x: 0; y: root.selY + root.selH; width: parent.width; height: parent.height - (root.selY + root.selH); color: root.dimColor }
                Rectangle { x: 0; y: root.selY; width: root.selX; height: root.selH; color: root.dimColor }
                Rectangle { x: root.selX + root.selW; y: root.selY; width: parent.width - (root.selX + root.selW); height: root.selH; color: root.dimColor }
            }
        }

        MultiEffect {
            id: structuralGlow
            source: selectionFrame
            anchors.fill: selectionFrame
            opacity: selectionFrame.opacity
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: root.isSelecting ? 0.75 : 0.55
            shadowBlur: root.isSelecting ? s(2.0) : s(1.4)
            shadowVerticalOffset: s(4)
            z: 5
            Behavior on shadowOpacity { enabled: root.animateChanges; NumberAnimation { duration: 200 } }
            Behavior on shadowBlur { enabled: root.animateChanges; NumberAnimation { duration: 200 } }
            visible: opacity > 0
        }

        Rectangle {
            id: selectionFrame
            opacity: (root.isSelecting || root.hasSelection) ? 1.0 : 0.0
            x: root.selX; y: root.selY; width: root.selW; height: root.selH
            color: "transparent"
            border.color: (root.showQrPopup && root.isQrSuccess) ? root.green : (root.isVideoMode ? root.red : root.mauve)
            border.width: s(2)
            z: 6
            visible: opacity > 0
        }

        Repeater {
            model: qrModel
            delegate: Rectangle {
                opacity: (root.showQrPopup && model.qSuccess && model.qW > 0) ? 1.0 : 0.0
                property real pad: (root.showQrPopup && model.qSuccess) ? s(5) : 0
                x: model.qW > 0 ? (model.qX - pad) : model.qX
                y: model.qH > 0 ? (model.qY - pad) : model.qY
                width: model.qW > 0 ? (model.qW + (pad * 2)) : 0
                height: model.qH > 0 ? (model.qH + (pad * 2)) : 0
                color: Qt.alpha(root.green, 0.25)
                border.color: root.green
                border.width: s(3)
                radius: root.radius
                z: 34
                Behavior on opacity { enabled: root.animateChanges; NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                Behavior on pad { enabled: root.animateChanges; NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                visible: opacity > 0
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            z: 20

            function getInteractionMode(mx, my, mods) {
                if (!root.hasSelection) return 1;
                if (mods & Qt.ShiftModifier) return 2;
                let margin = s(24);
                let onLeftLine = Math.abs(mx - root.selX) <= margin;
                let onRightLine = Math.abs(mx - (root.selX + root.selW)) <= margin;
                let onTopLine = Math.abs(my - root.selY) <= margin;
                let onBottomLine = Math.abs(my - (root.selY + root.selH)) <= margin;
                let widthCheck = mx >= (root.selX - margin) && mx <= (root.selX + root.selW + margin);
                let heightCheck = my >= (root.selY - margin) && my <= (root.selY + root.selH + margin);

                if (onTopLine && onLeftLine) return 3;
                if (onTopLine && onRightLine) return 5;
                if (onBottomLine && onLeftLine) return 8;
                if (onBottomLine && onRightLine) return 10;
                if (onTopLine && widthCheck) return 4;
                if (onBottomLine && widthCheck) return 9;
                if (onLeftLine && heightCheck) return 6;
                if (onRightLine && heightCheck) return 7;
                return 1;
            }

            onPositionChanged: (mouse) => {
                let mode = root.isSelecting ? root.interactionMode : getInteractionMode(mouse.x, mouse.y, mouse.modifiers);
                switch(mode) {
                    case 2: cursorShape = Qt.ClosedHandCursor; break;
                    case 3: case 10: cursorShape = Qt.SizeFDiagCursor; break;
                    case 5: case 8: cursorShape = Qt.SizeBDiagCursor; break;
                    case 4: case 9: cursorShape = Qt.SizeVerCursor; break;
                    case 6: case 7: cursorShape = Qt.SizeHorCursor; break;
                    default: cursorShape = Qt.CrossCursor; break;
                }

                if (!root.isSelecting) return;
                let dx = mouse.x - root.anchorX; let dy = mouse.y - root.anchorY;
                let clamp = (val, min, max) => Math.max(min, Math.min(max, val));

                if (root.interactionMode === 1) {
                    root.endX = clamp(mouse.x, 0, root.width); root.endY = clamp(mouse.y, 0, root.height);
                } else if (root.interactionMode === 2) {
                    let targetX = clamp(root.initX + dx, 0, root.width - root.initW); let targetY = clamp(root.initY + dy, 0, root.height - root.initH);
                    root.startX = targetX; root.startY = targetY; root.endX = targetX + root.initW; root.endY = targetY + root.initH;
                } else {
                    let nx = root.initX, ny = root.initY, nw = root.initW, nh = root.initH;
                    if ([3, 6, 8].includes(root.interactionMode)) { nx = clamp(root.initX + dx, 0, root.initX + root.initW - 10); nw = root.initW + (root.initX - nx); }
                    if ([5, 7, 10].includes(root.interactionMode)) { nw = clamp(root.initW + dx, 10, root.width - root.initX); }
                    if ([3, 4, 5].includes(root.interactionMode)) { ny = clamp(root.initY + dy, 0, root.initY + root.initH - 10); nh = root.initH + (root.initY - ny); }
                    if ([8, 9, 10].includes(root.interactionMode)) { nh = clamp(root.initH + dy, 10, root.height - root.initY); }
                    root.startX = nx; root.startY = ny; root.endX = nx + nw; root.endY = ny + nh;
                }
            }

            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) { ScreenshotState.hide(); return; }

                root.isScanningQr = false;
                root.showQrPopup = false;

                root.interactionMode = getInteractionMode(mouse.x, mouse.y, mouse.modifiers);
                root.isSelecting = true;
                if (root.interactionMode !== 1) root.isMaximized = false;
                root.anchorX = mouse.x; root.anchorY = mouse.y;
                root.initX = root.selX; root.initY = root.selY; root.initW = root.selW; root.initH = root.selH;

                if (root.interactionMode === 1) {
                    let clamp = (val, min, max) => Math.max(min, Math.min(max, val));
                    let clampedX = clamp(mouse.x, 0, root.width); let clampedY = clamp(mouse.y, 0, root.height);
                    root.startX = clampedX; root.startY = clampedY; root.endX = clampedX; root.endY = clampedY;
                    root.hasSelection = false; root.isMaximized = false;
                }
            }

            onReleased: {
                if (!root.isSelecting) return;
                root.isSelecting = false;
                if (root.selW > 10 && root.selH > 10) {
                    root.hasSelection = true;
                    root.saveCache();
                    // Fresh mouse selection -> capture right away on release instead of
                    // waiting for the toolbar shutter. interactionMode 1 is a new rectangle.
                    if (root.captureOnRelease && root.interactionMode === 1 && !root.isVideoMode) {
                        root.capture(root.isEditMode);
                        return;
                    }
                } else if (root.interactionMode === 1) {
                    let clamp = (val, min, max) => Math.max(min, Math.min(max, val));
                    let left = clamp(root.startX - 20, 0, Math.max(0, root.width - 40));
                    let top = clamp(root.startY - 20, 0, Math.max(0, root.height - 40));
                    root.startX = left;
                    root.startY = top;
                    root.endX = left + 40;
                    root.endY = top + 40;
                    root.hasSelection = true;
                    root.saveCache();
                } else {
                    root.hasSelection = false;
                }
            }
        }

        Item {
            id: toolbar
            z: 30

            property real totalHeight: s(120)
            property bool fitsOutsideBottom: (root.selY + root.selH + totalHeight + s(15)) <= root.height

            property bool shouldShow: root.hasSelection && !root.isSelecting && !root.isScanningQr && !root.showQrPopup
            opacity: shouldShow ? 1.0 : 0.0
            Behavior on opacity {
                enabled: root.animateChanges && !root.isSelecting
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            visible: opacity > 0

            width: toolbarRow.width + s(20)
            height: totalHeight

            x: Math.max(s(10), Math.min(parent.width - width - s(10), root.selX + (root.selW / 2) - (width / 2)))
            y: fitsOutsideBottom ? (root.selY + root.selH + s(15)) :
               ((root.selY - height - s(15)) >= 0 ? (root.selY - height - s(15)) : (root.height - height - s(15)))

            Rectangle {
                anchors.fill: parent
                color: root.base
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.08)
                border.width: s(1)
                radius: root.radius

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                }
            }

            Row {
                id: toolbarRow
                anchors.top: parent.top
                anchors.topMargin: s(10)
                anchors.horizontalCenter: parent.horizontalCenter
                height: root.s(36)
                spacing: 0

                Item {
                    width: s(110) + s(6); height: parent.height

                    V2.Switch {
                        id: modeSwitch
                        width: s(110)
                        height: s(36)
                        options: ["\u{f0104}", "\u{f03d}"]   // md-camera, fa-video-camera
                        currentIndex: root.isVideoMode ? 1 : 0
                        accentColor: root.mauve
                        baseColor: root.surface0
                        textColor: root.text
                        activeTextColor: root.crust
                        cornerRadius: root.radius
                        fontFamily: Fonts.icons
                        fontPixelSize: s(16)

                        Connections {
                            target: root
                            function onIsVideoModeChanged() {
                                modeSwitch.currentIndex = root.isVideoMode ? 1 : 0;
                            }
                        }

                        onValueChanged: function(index, value) {
                            root.isVideoMode = (index === 1);
                        }
                        onToggled: function(index) {
                            root.isVideoMode = (index === 1);
                        }
                    }
                }

                AnimWrap {
                    isShown: root.isVideoMode && root.hdrAvailable; contentWidth: s(96)
                    V2.Switch {
                        id: hdrSwitch
                        width: s(96)
                        height: s(36)
                        options: ["SDR", "HDR"]
                        currentIndex: root.recHdr ? 1 : 0
                        accentColor: root.red
                        baseColor: root.surface0
                        textColor: root.text
                        activeTextColor: root.crust
                        cornerRadius: root.radius
                        fontFamily: Fonts.ui
                        fontPixelSize: s(12)

                        Connections {
                            target: root
                            function onRecHdrChanged() {
                                hdrSwitch.currentIndex = root.recHdr ? 1 : 0;
                            }
                        }

                        onValueChanged: function(index, value) { root.setRecHdr(index === 1) }
                        onToggled: function(index) { root.setRecHdr(index === 1) }
                    }
                }

                AnimWrap {
                    isShown: root.isVideoMode; contentWidth: s(132)
                    V2.Switch {
                        id: audioSwitch
                        width: s(132)
                        height: s(36)
                        options: ["\u{f0581}", "\u{f057e}", "\u{f036c}"]   // volume-off, volume-high, microphone
                        currentIndex: Math.max(0, root.audioModes.indexOf(root.recAudio))
                        accentColor: root.red
                        baseColor: root.surface0
                        textColor: root.text
                        activeTextColor: root.crust
                        cornerRadius: root.radius
                        fontFamily: Fonts.icons
                        fontPixelSize: s(16)

                        Connections {
                            target: root
                            function onRecAudioChanged() {
                                audioSwitch.currentIndex = Math.max(0, root.audioModes.indexOf(root.recAudio));
                            }
                        }

                        onValueChanged: function(index, value) { root.setRecAudio(root.audioModes[index]) }
                        onToggled: function(index) { root.setRecAudio(root.audioModes[index]) }
                    }
                }

                AnimWrap {
                    isShown: !root.isVideoMode; contentWidth: s(36)
                    V2.IconButton { size: s(36); cornerRadius: root.radius; centerInk: true; buttonIcon: "\u{f03eb}"; iconFontSize: s(18); accentColor: root.surface0; textColor: root.text; onClicked: root.capture(true) }
                }

                AnimWrap {
                    isShown: !root.isVideoMode; contentWidth: s(36)
                    V2.IconButton { size: s(36); cornerRadius: root.radius; centerInk: true; buttonIcon: "\u{f0433}"; iconFontSize: s(18); accentColor: root.surface0; textColor: root.text; onClicked: root.performQrScan() }
                }

                AnimWrap {
                    isShown: !root.isVideoMode; contentWidth: s(36)
                    V2.IconButton { size: s(36); cornerRadius: root.radius; centerInk: true; buttonIcon: root.isMaximized ? "\u{f066}" : "\u{f065}"; iconFontSize: s(18); accentColor: root.surface0; textColor: root.text; onClicked: root.toggleMaximize() }
                }

                Item {
                    width: s(36); height: parent.height
                    V2.IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        size: s(36); cornerRadius: root.radius; centerInk: true; buttonIcon: "\u{f0156}"; iconFontSize: s(18); accentColor: root.red; textColor: root.crust; onClicked: ScreenshotState.hide()
                    }
                }
            }

            Item {
                id: captureSection
                anchors.bottom: parent.bottom
                anchors.bottomMargin: s(12)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: s(56)
                z: 10

                Rectangle {
                    id: leftLineBase
                    height: s(4)
                    radius: s(2)
                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
                    anchors.left: parent.left
                    anchors.leftMargin: s(24)
                    anchors.right: actionBtnContainer.left
                    anchors.rightMargin: s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: actionArea.containsMouse ? parent.width : 0
                        radius: s(2)
                        Behavior on width { enabled: root.animateChanges; NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.isVideoMode ? root.red : root.mauve }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }

                Item {
                    id: actionBtnContainer
                    width: s(56)
                    height: width
                    anchors.centerIn: parent
                    z: 20

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: root.isVideoMode ? Qt.alpha(root.red, 0.4) : Qt.alpha(root.surface1, 0.8)
                        border.width: s(2)
                        Behavior on border.color { enabled: root.animateChanges; ColorAnimation { duration: 250 } }
                    }

                    Rectangle {
                        width: actionArea.pressed ? s(32) : (actionArea.containsMouse ? s(40) : s(36))
                        height: width
                        radius: (root.isVideoMode && RecordState.recording) ? s(6) : width / 2
                        anchors.centerIn: parent
                        color: root.isVideoMode ? root.red : root.mauve
                        Behavior on color { enabled: root.animateChanges; ColorAnimation { duration: 250 } }
                        Behavior on width { enabled: root.animateChanges; NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                    }

                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.isVideoMode) root.videoAction();
                            else root.capture(root.isEditMode);
                        }
                    }
                }

                Rectangle {
                    id: rightLineBase
                    height: s(4)
                    radius: s(2)
                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
                    anchors.right: parent.right
                    anchors.rightMargin: s(24)
                    anchors.left: actionBtnContainer.right
                    anchors.leftMargin: s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: actionArea.containsMouse ? parent.width : 0
                        radius: s(2)
                        Behavior on width { enabled: root.animateChanges; NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: root.isVideoMode ? root.red : root.mauve }
                        }
                    }
                }
            }
        }

        Repeater {
            model: qrModel
            delegate: Rectangle {
                id: qrPopupItem
                opacity: (root.showQrPopup && !root.isSelecting) ? 1.0 : 0.0

                x: model.qTargetX
                y: model.qTargetY + (model.fitsTop ? (1.0 - opacity) * s(15) : -(1.0 - opacity) * s(15))

                width: qrPopupLayout.implicitWidth + s(32)
                height: s(52)
                radius: root.radius
                color: root.base
                border.color: model.qSuccess ? root.green : root.red
                border.width: s(2)

                property bool isHovered: maHover.containsMouse
                scale: isHovered ? 1.0 : model.qBaseScale
                z: isHovered ? 100 : (40 - index)
                transformOrigin: Item.Center

                Behavior on opacity { enabled: root.animateChanges; NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                Behavior on scale { enabled: root.animateChanges; NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

                visible: opacity > 0

                MouseArea { id: maHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                RowLayout {
                    id: qrPopupLayout
                    anchors.centerIn: parent
                    spacing: s(8)

                    Text {
                        text: model.qText
                        color: model.qSuccess ? root.text : root.red
                        font.family: Fonts.ui
                        font.pixelSize: s(13)
                        font.weight: Font.DemiBold
                        Layout.maximumWidth: s(400)
                        Layout.leftMargin: s(8)
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }

                    Rectangle { visible: model.qSuccess; width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: root.surface0; radius: s(1) }

                    V2.IconButton {
                        visible: model.qSuccess
                        size: s(36)
                        cornerRadius: root.radius
                        centerInk: true
                        buttonIcon: "\u{f018f}"
                        iconFontSize: s(18)
                        accentColor: root.surface0
                        textColor: root.text
                        onClicked: {
                            // The shell owns the selection, so decoded text never reaches a shell.
                            Quickshell.clipboardText = model.qText;
                            root.showQrPopup = false;
                        }
                    }

                    V2.IconButton {
                        visible: model.qSuccess && (model.qText.startsWith("http://") || model.qText.startsWith("https://"))
                        size: s(36)
                        cornerRadius: root.radius
                        centerInk: true
                        buttonIcon: "\u{f0339}"
                        iconFontSize: s(18)
                        accentColor: root.surface0
                        textColor: root.text
                        onClicked: {
                            Quickshell.execDetached(["xdg-open", model.qText]);
                            ScreenshotState.hide();
                        }
                    }

                    Rectangle { width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: root.surface0; radius: s(1) }
                    V2.IconButton { size: s(36); cornerRadius: root.radius; centerInk: true; buttonIcon: "\u{f0156}"; iconFontSize: s(18); accentColor: root.red; textColor: root.crust; onClicked: root.showQrPopup = false }
                }
            }
        }
    }

    // --- QR scan ------------------------------------------------------------
    Process {
        id: qrProc
        stdout: StdioCollector { onStreamFinished: root.onQrResult(this.text) }
    }

    function performQrScan() {
        if (qrProc.running || root.freezeImg === "" || !root.hasSelection) return;
        root.isScanningQr = true;
        root.showQrPopup = false;
        qrModel.clear();
        qrProc.command = ["bash", root.helper, "--scan-qr", "--geometry", root.geometryString,
                          "--freeze", root.freezeImg];
        qrProc.running = true;
    }

    function onQrResult(out) {
        root.isScanningQr = false;
        if (!root.armed) return;
        let res = ("" + out).trim();
        qrModel.clear();

        if (res === "") {
            qrModel.append({
                qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0,
                qText: "Scan timed out or failed.", qSuccess: false,
                qTargetX: root.selX + (root.selW / 2) - s(100), qTargetY: root.selY + (root.selH / 2),
                qBaseScale: 1.0, fitsTop: false
            });
            root.isQrSuccess = false;
            root.showQrPopup = true;
            return;
        }

        let lines = res.split('\n');
        let anySuccess = false;
        let qrs = [];

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line === "") continue;
            let delimiterIdx = line.indexOf('|||');
            if (delimiterIdx === -1) continue;

            let coordStr = line.substring(0, delimiterIdx);
            // One pass, or a payload's literal "\n" would come back as a real newline.
            let actualText = line.substring(delimiterIdx + 3).replace(/\\(.)/g, (m, c) => c === 'n' ? '\n' : c);
            let coords = coordStr.split(',');

            if (coords.length === 4 && !isNaN(parseInt(coords[0]))) {
                let scale = root.freezeScale || 1.0;
                let x = parseInt(coords[0]) / scale;
                let y = parseInt(coords[1]) / scale;
                let w = parseInt(coords[2]) / scale;
                let h = parseInt(coords[3]) / scale;

                let successState = !(actualText === "NOT_FOUND" || actualText.startsWith("ERROR:"));
                if (successState) anySuccess = true;
                let cleanText = successState ? actualText : (actualText === "NOT_FOUND" ? "No QR code found." : actualText);

                let estTextWidth = Math.min(s(400), cleanText.length * s(8.5));
                let pw = estTextWidth + (successState ? s(140) : s(40));
                let ph = s(52);
                let absX = root.selX + x;
                let absY = root.selY + y;
                let cx = absX + (w / 2);
                let fitsTop = (absY - ph - s(15)) >= root.selY;
                let idealX = cx - (pw / 2);
                let targetX = Math.max(s(10), Math.min(root.width - pw - s(10), idealX));
                let targetY = fitsTop ? (absY - ph - s(15)) : (absY + h + s(15));

                qrs.push({ qX: absX, qY: absY, qW: w, qH: h, qText: cleanText, qSuccess: successState, pw: pw, ph: ph, targetX: targetX, targetY: targetY, cx: targetX + (pw / 2), cy: targetY + (ph / 2), scale: 1.0, fitsTop: fitsTop });
            }
        }

        // Overlapping cards shrink until they clear each other.
        for (let pass = 0; pass < 5; pass++) {
            for (let i = 0; i < qrs.length; i++) {
                for (let j = i + 1; j < qrs.length; j++) {
                    let A = qrs[i]; let B = qrs[j];
                    let dx = Math.abs(A.cx - B.cx); let dy = Math.abs(A.cy - B.cy);
                    let req_x = (A.pw * A.scale + B.pw * B.scale) / 2 + s(10);
                    let req_y = (A.ph * A.scale + B.ph * B.scale) / 2 + s(10);

                    if (dx < req_x && dy < req_y) {
                        let factorX = dx > 0 ? (dx - s(10)) * 2 / (A.pw + B.pw) : 0;
                        let factorY = dy > 0 ? (dy - s(10)) * 2 / (A.ph + B.ph) : 0;
                        let maxFactor = Math.max(factorX, factorY);
                        maxFactor = Math.max(0.35, maxFactor);
                        A.scale = Math.min(A.scale, maxFactor); B.scale = Math.min(B.scale, maxFactor);
                    }
                }
            }
        }

        if (qrs.length === 0) {
            qrModel.append({
                qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0,
                qText: "No QR code found.", qSuccess: false,
                qTargetX: root.selX + (root.selW / 2) - s(100), qTargetY: root.selY + (root.selH / 2),
                qBaseScale: 1.0, fitsTop: false
            });
        } else {
            for (let i = 0; i < qrs.length; i++) {
                qrModel.append({ qX: qrs[i].qX, qY: qrs[i].qY, qW: qrs[i].qW, qH: qrs[i].qH, qText: qrs[i].qText, qSuccess: qrs[i].qSuccess, qTargetX: qrs[i].targetX, qTargetY: qrs[i].targetY, qBaseScale: qrs[i].scale, fitsTop: qrs[i].fitsTop });
            }
        }

        root.isQrSuccess = anySuccess;
        root.showQrPopup = true;
    }
}
