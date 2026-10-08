// serpantinum v2's System Panel (syspanel/SystemPanel.qml) as our notification centre:
// a full-height side sheet, built by PopupHost under the registry name notifcenter.
// KDE backends throughout; the KDE Connect ring, the Night Light temperature slider
// and uptime carry over from the old BatteryPopup.
import "../../services/airplane"
import "../../services/audio"
import "../../services/bar"
import "../../services/dnd"
import "../../services/kdeconnect"
import "../../services/keepawake"
import "../../services/layout"
import "../../services/network"
import "../../services/power"
import "../../services/reusables"
import "../../services/shims"
import "../bluetooth"
import "../network"
import "../power"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.UPower

Item {
    id: root
    focus: true

    signal closeRequested()

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(val) { return scaler.s(val); }

    readonly property bool isLeftAnchored: BarState.position === "right"
    readonly property real slideDistance: sidebarPanel.width > 0 ? sidebarPanel.width : root.s(420)
    readonly property real rowSlideDistance: root.s(12)
    // PopupHost leaves the entrance and exit to us (no host fade, zoom or box stretch).
    readonly property bool selfAnimates: true

    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : true

    readonly property real boxRadius: Radius.inner(root.s(20))
    readonly property real cardRadius: Radius.inner(root.s(14))
    readonly property real ringSize: root.s(104)
    // Follows the knob, and may still reach a circle at the top of its range.
    readonly property real ringRadius: Radius.inner(root.s(20), ringSize / 2)
    onRingRadiusChanged: batCanvas.requestPaint()
    readonly property color boxColor: Qt.darker(ThemeBackend.surface0, 1.04)

    readonly property color briColor: Qt.lighter(ThemeBackend.mauve, 1.1)
    readonly property color volColor: Qt.lighter(ThemeBackend.sapphire, 1.5)
    readonly property color tempColor: ThemeBackend.peach
    readonly property color profileColor: Qt.lighter(ThemeBackend.blue, 1.55)

    // --- user, OS, uptime, hibernate: one probe on open ----------------------
    property string avatarPath: ""
    property string osName: ""
    property string userName: Quickshell.env("USER") || "user"
    property bool canHibernate: false
    property real upBase: 0
    property real upAt: Date.now()
    property real nowTick: Date.now()
    readonly property int upTotalMins: Math.floor((upBase + (nowTick - upAt) / 1000) / 60)
    readonly property int upHours: Math.floor(upTotalMins / 60)
    readonly property int upMins: upTotalMins % 60
    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.nowTick = Date.now() }

    Process {
        id: sysProbe
        running: true
        command: ["sh", "-c",
            "for f in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -r \"$f\" ] && { echo \"avatar=$f\"; break; }; done; " +
            ". /etc/os-release 2>/dev/null; echo \"os=${PRETTY_NAME:-$NAME}\"; " +
            "echo \"uptime=$(cut -d. -f1 /proc/uptime)\"; " +
            "echo \"hib=$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var eq = lines[i].indexOf("=");
                    if (eq < 0) continue;
                    var k = lines[i].substring(0, eq), v = lines[i].substring(eq + 1).trim();
                    if (k === "avatar") root.avatarPath = v;
                    else if (k === "os") root.osName = v;
                    else if (k === "uptime") { root.upBase = Number(v) || 0; root.upAt = Date.now(); root.nowTick = Date.now(); }
                    else if (k === "hib") root.canHibernate = v.indexOf("\"yes\"") !== -1;
                }
            }
        }
    }

    // --- audio (native Pipewire) ---------------------------------------------
    readonly property real sysVolume: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    readonly property bool sysMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false
    property bool isDraggingVol: false
    Timer { id: volSyncDelay; interval: 800; onTriggered: root.isDraggingVol = false }
    onSysVolumeChanged: if (!root.isDraggingVol && volSlider.value !== sysVolume) volSlider.value = sysVolume

    // --- brightness: Plasma's ScreenBrightness (DDC/CI here); row hidden when absent ---
    property string briDisplay: ""
    property int briMax: 0
    property real sysBrightness: 0
    property bool isDraggingBri: false
    readonly property bool hasBrightness: briDisplay !== "" && briMax > 0
    Timer { id: briSyncDelay; interval: 800; onTriggered: root.isDraggingBri = false }
    onSysBrightnessChanged: if (!root.isDraggingBri && briSlider.value !== sysBrightness) briSlider.value = sysBrightness

    Process {
        id: briProbe
        running: true
        command: ["sh", "-c",
            "n=$(qdbus6 org.kde.ScreenBrightness /org/kde/ScreenBrightness org.kde.ScreenBrightness.DisplaysDBusNames 2>/dev/null | head -n1); " +
            "[ -n \"$n\" ] || exit 0; " +
            "b=$(qdbus6 org.kde.ScreenBrightness /org/kde/ScreenBrightness/$n org.kde.ScreenBrightness.Display.Brightness 2>/dev/null); " +
            "m=$(qdbus6 org.kde.ScreenBrightness /org/kde/ScreenBrightness/$n org.kde.ScreenBrightness.Display.MaxBrightness 2>/dev/null); " +
            "echo \"$n $b $m\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim().split(/\s+/);
                if (p.length < 3 || !p[0]) return;
                root.briDisplay = p[0];
                root.briMax = Number(p[2]) || 0;
                if (root.briMax > 0 && !root.isDraggingBri)
                    root.sysBrightness = Math.round((Number(p[1]) || 0) * 100 / root.briMax);
            }
        }
    }
    Timer { id: briRecheck; interval: 250; onTriggered: { briProbe.running = false; briProbe.running = true; } }
    // Event-driven: KDE's OSD keys and the KCM change it too. Dies with the panel.
    Process {
        id: briMonitor
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "gdbus", "monitor", "--session",
                  "--dest", "org.kde.ScreenBrightness", "--object-path", "/org/kde/ScreenBrightness"]
        stdout: SplitParser { onRead: line => { if (line.indexOf("BrightnessChanged") !== -1) briRecheck.restart(); } }
    }
    function setBrightness(pct) {
        if (!hasBrightness) return;
        var raw = Math.round(Math.max(0, Math.min(100, pct)) / 100 * briMax);
        // flag 1 = SuppressIndicator: no KDE OSD while our slider moves.
        Quickshell.execDetached(["qdbus6", "org.kde.ScreenBrightness", "/org/kde/ScreenBrightness/" + briDisplay,
                                 "org.kde.ScreenBrightness.Display.SetBrightness", "" + raw, "1"]);
    }

    // --- Night Light (KWin) ---------------------------------------------------
    // on = running && !daylight: running alone stays true all day at 6500K, and the
    // pairing also covers inhibition (which is what "Toggle Night Color" flips).
    property bool nightOn: false
    Process {
        id: nightPoller
        running: true
        command: ["sh", "-c",
            "r=$(qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.running 2>/dev/null); " +
            "d=$(qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.daylight 2>/dev/null); " +
            "[ \"$r\" = true ] && [ \"$d\" != true ] && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.nightOn = ((this.text || "").trim() === "on") }
    }
    Timer { id: nightRecheck; interval: 300; onTriggered: { nightPoller.running = false; nightPoller.running = true; } }
    Process {
        id: nightMonitor
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "gdbus", "monitor", "--session",
                  "--dest", "org.kde.KWin", "--object-path", "/org/kde/KWin/NightLight"]
        stdout: SplitParser { onRead: line => { if (line.indexOf("PropertiesChanged") !== -1) nightRecheck.restart(); } }
    }
    function toggleNightLight() {
        Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Toggle Night Color"]);
        nightRecheck.restart();
    }

    // Temperature: the configured night value (not the live one, 6500 by day), previewed
    // live while dragging and written to kwinrc on release.
    property int nightTemp: 4200
    readonly property int nightTempMin: 2500
    readonly property int nightTempMax: 6500
    property bool isDraggingTemp: false
    Process {
        id: nightTempReader
        running: true
        command: ["kreadconfig6", "--file", "kwinrc", "--group", "NightColor", "--key", "NightTemperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = parseInt((this.text || "").trim(), 10);
                if (!isNaN(t) && t >= 1000 && !root.isDraggingTemp)
                    root.nightTemp = Math.max(root.nightTempMin, Math.min(root.nightTempMax, t));
            }
        }
    }
    Timer {
        id: tempPreviewThrottle
        interval: 60
        property int pending: -1
        onTriggered: {
            if (pending > 0) {
                Quickshell.execDetached(["qdbus6", "org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight.preview", "" + pending]);
                pending = -1;
            }
        }
    }
    // stopPreview() FIRST: preview() only moves the live temperature, never kwinrc.
    function commitNightTemp() {
        Quickshell.execDetached(["sh", "-c",
            "qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.stopPreview 2>/dev/null; " +
            "kwriteconfig6 --file kwinrc --group NightColor --key NightTemperature " + root.nightTemp +
            " && qdbus6 org.kde.KWin /KWin reconfigure"]);
        nightRecheck.interval = 700;
        nightRecheck.restart();
    }

    // --- radios ---------------------------------------------------------------
    // "unavailable" was always "no DeviceType.Wifi device exists", never the radio flag.
    readonly property bool netReady: Net.ready
    // Held at the last known reading through Net's 1-3s warm-up: the device list is
    // empty there, and airplane mode would otherwise remember "no adapter, radio off".
    property bool wifiOnStore: false
    property bool wifiUsableStore: false
    Binding { target: root; property: "wifiOnStore"; value: Net.wifiPresent && Net.radioOn; when: root.netReady; restoreMode: Binding.RestoreNone }
    Binding { target: root; property: "wifiUsableStore"; value: Net.wifiPresent; when: root.netReady; restoreMode: Binding.RestoreNone }
    readonly property bool wifiOn: root.netReady ? (Net.wifiPresent && Net.radioOn) : root.wifiOnStore
    readonly property bool wifiUsable: root.netReady ? Net.wifiPresent : root.wifiUsableStore
    readonly property string wifiIcon: Net.radioIcon
    readonly property string wifiSsid: Net.wifiSsid
    function toggleWifi() { if (root.netReady) Net.setRadio(!root.wifiOn); }

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btPresent: btAdapter !== null && btAdapter !== undefined
    readonly property bool btOn: btPresent && btAdapter.enabled
    readonly property var btConnectedDev: {
        if (!btOn || !btAdapter.devices) return null;
        var v = btAdapter.devices.values;
        for (var i = 0; i < v.length; i++) if (v[i] && v[i].connected) return v[i];
        return null;
    }

    readonly property bool anyRadioOn: wifiOn || btOn
    // On only after the toggle engaged it and while every radio is still off; the flag outlives the panel.
    readonly property bool airplaneOn: AirplaneState.engaged && !anyRadioOn
    // A radio switched back on by hand makes the remembered states stale.
    onAnyRadioOnChanged: if (anyRadioOn) AirplaneState.forget()

    // --- power profile (PowerDevil, shared with the power panel) ---------------
    readonly property var profileDefs: [
        { key: "performance", glyph: "󰓅", label: "Performance" },
        { key: "balanced",    glyph: "󰗑", label: "Balanced" },
        { key: "power-saver", glyph: "󰌪", label: "Saver" }
    ]
    readonly property var profileOptions: profileDefs.filter(d => PowerInfo.choices.indexOf(d.key) !== -1)
    readonly property int profileIndex: {
        for (var i = 0; i < profileOptions.length; i++) if (profileOptions[i].key === PowerInfo.profile) return i;
        return -1;
    }

    // --- battery (laptops only) ---------------------------------------------------
    readonly property int batCapacity: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property int batSecs: !UPower.displayDevice.ready ? 0 : (isCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty)
    readonly property int batHours: Math.floor(batSecs / 3600)
    readonly property int batMins: Math.round((batSecs % 3600) / 60)
    readonly property color batColorFlat: !UPower.displayDevice.ready ? ThemeBackend.blue : (isCharging ? ThemeBackend.green : (batCapacity <= 20 ? ThemeBackend.red : ThemeBackend.blue))
    property real animCapacity: 0
    Behavior on animCapacity { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
    onBatCapacityChanged: animCapacity = batCapacity

    // --- intro / outro ----------------------------------------------------------------
    property real introContent: 0.0
    property real introTop: 0.0
    property real introSliders: 0.0
    property real introQuickActions: 0.0
    property real introNotifs: 0.0
    property real introPhone: 0.0
    property real introActions: 0.0
    property real introCore: 0.0

    // The sheet slides in solid on an emphasized decelerate curve; rows settle once it's mostly in.
    readonly property var curveIn: [0.05, 0.7, 0.1, 1.0, 1, 1]
    readonly property var curveOut: [0.3, 0.0, 0.8, 0.15, 1, 1]

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introContent"; from: 0; to: 1.0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveIn }
        SequentialAnimation { PauseAnimation { duration: 150 } NumberAnimation { target: root; property: "introTop";          from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 180 } NumberAnimation { target: root; property: "introSliders";      from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 210 } NumberAnimation { target: root; property: "introQuickActions"; from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 240 } NumberAnimation { target: root; property: "introNotifs";       from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 270 } NumberAnimation { target: root; property: "introPhone";        from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 300 } NumberAnimation { target: root; property: "introActions";      from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: 330 } NumberAnimation { target: root; property: "introCore";         from: 0; to: 1.0; duration: 260; easing.type: Easing.OutCubic } }
    }

    // Leaves as one piece: the rows stay put inside the sheet.
    NumberAnimation {
        id: closeSequence
        target: root
        property: "introContent"
        to: 0.0
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.curveOut
    }

    // PopupHost calls this on hide and waits the returned ms before tearing us down.
    function beginClose() {
        startupSequence.stop();
        closeSequence.start();
        return 220;
    }

    // --- keyboard ---------------------------------------------------------------------
    // Tab cycles sections; arrows move inside one; Enter or Space activates. Escape stays with the host.
    property string keyZone: ""
    property int quickIndex: 0
    property int powerIndex: 0
    readonly property var quickButtons: [qaNight, qaAwake, qaWifi, qaBt, qaAirplane]
    readonly property var keyZones: profileOptions.length > 0 ? ["notifs", "quick", "power", "profile"] : ["notifs", "quick", "power"]

    function cycleZone(step) {
        let z = keyZones;
        let i = z.indexOf(keyZone);
        keyZone = i < 0 ? (step > 0 ? z[0] : z[z.length - 1]) : z[(i + step + z.length) % z.length];
    }
    function keyMove(step, vertical) {
        if (keyZone === "") { keyZone = "notifs"; return; }
        if (keyZone === "notifs") {
            if (vertical) notifsBox.moveSelection(step);
            else notifsBox.setSelectedExpanded(step > 0);
        } else if (keyZone === "quick") {
            quickIndex = Math.max(0, Math.min(quickButtons.length - 1, quickIndex + step));
        } else if (keyZone === "power") {
            powerIndex = Math.max(0, Math.min(powerRepeater.count - 1, powerIndex + step));
        } else if (keyZone === "profile" && profileOptions.length > 0) {
            let i = Math.max(0, Math.min(profileOptions.length - 1, Math.max(0, profileIndex) + step));
            PowerInfo.setProfile(profileOptions[i].key);
        }
    }
    function keyActivate() {
        if (keyZone === "notifs") notifsBox.activateSelected();
        else if (keyZone === "quick") { let b = quickButtons[quickIndex]; if (b && !b.isDisabled) b.leftClicked(); }
        else if (keyZone === "power") { let c = powerRepeater.itemAt(powerIndex); if (c) c.keyActivate(); }
    }

    Shortcut { sequence: "Tab"; onActivated: root.cycleZone(1) }
    Shortcut { sequences: ["Shift+Tab", "Backtab"]; onActivated: root.cycleZone(-1) }
    Shortcut { sequence: "Down"; onActivated: root.keyMove(1, true) }
    Shortcut { sequence: "Up"; onActivated: root.keyMove(-1, true) }
    Shortcut { sequence: "Right"; onActivated: root.keyMove(1, false) }
    Shortcut { sequence: "Left"; onActivated: root.keyMove(-1, false) }
    Shortcut { sequences: ["Return", "Enter", "Space"]; onActivated: root.keyActivate() }
    Shortcut { sequences: ["Backspace", "Delete"]; onActivated: { root.keyZone = "notifs"; notifsBox.dismissSelected(); } }
    Shortcut { sequences: ["Shift+Backspace", "Shift+Delete"]; onActivated: notifsBox.animateClear() }
    Shortcut { sequence: "D"; onActivated: DndState.toggle() }

    Component.onCompleted: {
        animCapacity = batCapacity;
        volSlider.value = sysVolume;
        startupSequence.start();
    }
    Component.onDestruction: {
        briMonitor.running = false;
        nightMonitor.running = false;
    }

    // Runs a command and closes after the flash, before the host destroys us.
    Timer {
        id: actionTimer
        interval: 350
        property var cmd: []
        onTriggered: {
            if (cmd.length) Quickshell.execDetached(cmd);
            root.closeRequested();
        }
    }
    function runAndClose(cmd) { actionTimer.cmd = cmd; actionTimer.restart(); }

    // --- building blocks ------------------------------------------------------------
    component SlideIn : Translate {
        property real progress: 1.0
        x: (root.isLeftAnchored ? -root.rowSlideDistance : root.rowSlideDistance) * (1.0 - progress)
    }

    component QuickActionBtn : Rectangle {
        id: qaBtn
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: root.cardRadius

        property bool isActive: false
        property bool isDisabled: false
        property string iconText: ""
        property color activeColor: ThemeBackend.blue
        property bool keyFocused: false
        border.width: keyFocused ? root.s(2) : 0
        border.color: ThemeBackend.text

        signal leftClicked()
        signal rightClicked()

        color: isActive ? activeColor : (qaMa.containsMouse && !isDisabled ? ThemeBackend.surface1 : root.boxColor)
        Behavior on color { ColorAnimation { duration: 150 } }
        opacity: isDisabled ? 0.45 : 1.0
        scale: qaMa.pressed && !isDisabled ? 0.95 : (qaMa.containsMouse && !isDisabled ? 1.01 : 1.0)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }

        Text {
            anchors.centerIn: parent
            font.family: "Iosevka Nerd Font"
            font.pixelSize: root.s(22)
            color: qaBtn.isActive ? ThemeBackend.crust : (qaMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
            text: qaBtn.iconText
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: qaMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: qaBtn.isDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (!qaBtn.isDisabled) if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
                if (mouse.button === Qt.RightButton) qaBtn.rightClicked();
                else if (!qaBtn.isDisabled) qaBtn.leftClicked();
            }
        }
    }

    component UptimeBox : Rectangle {
        property string value: "00"
        property string unit: "HR"
        property color tint: ThemeBackend.blue
        width: root.s(38); height: root.s(38)
        radius: Radius.inner(root.s(9), root.s(12))
        color: ThemeBackend.surface1
        Rectangle { anchors.fill: parent; radius: parent.radius; color: parent.tint; opacity: 0.08 }
        Column {
            anchors.centerIn: parent
            spacing: -root.s(2)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: value
                font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(14)
                color: tint
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: unit
                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(7)
                color: ThemeBackend.subtext0
            }
        }
    }

    component BatteryContent : Item {
        id: bRoot
        property color contentTextColor: ThemeBackend.text
        property color iconColor: root.batColorFlat

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.s(20)
            anchors.rightMargin: root.s(20)
            spacing: root.s(16)

            Text {
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(32)
                color: bRoot.iconColor
                text: root.isCharging ? "󰂄" : (root.batCapacity > 20 ? "󰁹" : "󰂃")
                Behavior on color { ColorAnimation { duration: 400 } }
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                spacing: root.s(2)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(20)
                    color: bRoot.contentTextColor
                    text: Math.round(root.animCapacity) + "%"
                }

                Text {
                    property string timeString: {
                        if (!UPower.displayDevice.ready) return "";
                        if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged) return "Fully charged";
                        var t = (root.batHours === 0 && root.batMins === 0) ? "" : (root.batHours + "h " + root.batMins + "m ");
                        if (UPower.displayDevice.state === UPowerDeviceState.Charging) return t ? t + "until full" : "Charging";
                        return t ? t + "left" : "Discharging";
                    }
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(10)
                    color: bRoot.contentTextColor === ThemeBackend.crust ? Qt.alpha(ThemeBackend.crust, 0.85) : (root.isCharging ? ThemeBackend.green : ThemeBackend.subtext0)
                    text: timeString
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // --- the sheet ---------------------------------------------------------------------
    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.97)
        radius: Radius.inner(root.s(28))
        clip: true
        // Solid while it slides; only the first few frames fade, so it doesn't pop in.
        opacity: Math.min(1.0, root.introContent * 5)
        transform: Translate { x: (root.isLeftAnchored ? -root.slideDistance : root.slideDistance) * (1.0 - root.introContent) }

        // Squares off the screen-edge side.
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: root.isLeftAnchored ? parent.left : undefined
            anchors.right: root.isLeftAnchored ? undefined : parent.right
            width: sidebarPanel.radius + root.s(2)
            color: sidebarPanel.color
            visible: sidebarPanel.radius > 0
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(8)
            spacing: root.s(5)

            // 1. user header: avatar, name, OS; uptime; logout
            Rectangle {
                id: userBox
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(54)
                Layout.maximumHeight: root.s(54)
                radius: root.boxRadius
                color: root.boxColor
                opacity: root.introTop
                transform: SlideIn { progress: root.introTop }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(10)
                    spacing: root.s(10)

                    // Plain clip, not ImageBox: its MultiEffect mask resampled the photo soft.
                    ClippingRectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: root.s(34)
                        Layout.preferredHeight: root.s(34)
                        radius: Radius.inner(root.s(8), root.s(17))
                        color: root.avatarPath === "" ? ThemeBackend.surface1 : "transparent"

                        Image {
                            anchors.fill: parent
                            visible: root.avatarPath !== ""
                            source: root.avatarPath !== "" ? "file://" + root.avatarPath : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(root.s(34) * 2, root.s(34) * 2)
                            mipmap: true
                            smooth: true
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0004}"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.s(18)
                            color: ThemeBackend.text
                            visible: root.avatarPath === ""
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: root.userName
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: root.s(15)
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.osName !== "" ? root.osName : "Linux"
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Medium
                            font.pixelSize: root.s(10)
                            color: ThemeBackend.subtext0
                            elide: Text.ElideRight
                        }
                    }

                    // Uptime, kept from the old centre: HR : MIN with the pulsing colon.
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.s(4)
                        UptimeBox { value: root.upHours.toString().padStart(2, "0"); unit: "HR"; tint: ThemeBackend.blue }
                        Text {
                            text: ":"
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(18)
                            color: ThemeBackend.blue
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: 0.2; duration: 800; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                            }
                        }
                        UptimeBox { value: root.upMins.toString().padStart(2, "0"); unit: "MIN"; tint: ThemeBackend.green }
                    }

                    ClickButton {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: root.s(92)
                        Layout.preferredHeight: root.s(34)
                        horizontalPadding: root.s(10)
                        cornerRadius: Radius.inner(root.s(12), root.s(17))
                        buttonText: "Logout"
                        textFontSize: root.s(11)
                        buttonIcon: "󰍃"
                        iconFontSize: root.s(14)
                        accentColor: ThemeBackend.surface2
                        textColor: ThemeBackend.text
                        onTriggered: root.runAndClose(["qdbus6", "org.kde.Shutdown", "/Shutdown", "logout"])
                    }
                }
            }

            // 2. sliders: volume, brightness, night temperature
            Rectangle {
                id: slidersBox
                Layout.fillWidth: true
                Layout.preferredHeight: slidersCol.implicitHeight + root.s(20)
                Layout.maximumHeight: slidersCol.implicitHeight + root.s(20)
                radius: root.boxRadius
                color: root.boxColor
                opacity: root.introSliders
                transform: SlideIn { progress: root.introSliders }

                ColumnLayout {
                    id: slidersCol
                    anchors.fill: parent
                    anchors.margins: root.s(12)
                    spacing: root.s(6)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)

                        IconButton {
                            Layout.alignment: Qt.AlignVCenter
                            size: root.s(26)
                            centerInk: true
                            cornerRadius: Radius.inner(root.s(8), root.s(13))
                            buttonIcon: root.sysMuted || root.sysVolume === 0 ? "󰖁" : (root.sysVolume > 50 ? "󰕾" : "󰖀")
                            iconFontSize: root.s(15)
                            accentColor: ThemeBackend.surface1
                            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (root.sysMuted ? ThemeBackend.overlay0 : root.volColor)
                            onClicked: if (Audio.defaultSink) Audio.toggleMute(Audio.defaultSink)
                        }

                        Timer {
                            id: volCmdThrottle
                            interval: 50
                            property int targetPct: -1
                            onTriggered: {
                                if (targetPct < 0) return;
                                if (targetPct > 0 && root.sysMuted && Audio.defaultSink) Audio.toggleMute(Audio.defaultSink);
                                if (Audio.defaultSink) Audio.setVolume(Audio.defaultSink, targetPct);
                                targetPct = -1;
                            }
                        }

                        Draggable {
                            id: volSlider
                            Layout.fillWidth: true
                            implicitHeight: root.s(18)
                            from: 0.0; to: 100.0; stepSize: 1.0
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) }
                            value: root.sysVolume
                            backgroundColor: ThemeBackend.surface1
                            accentColor: root.sysMuted ? ThemeBackend.surface2 : root.volColor
                            gradColor1: root.sysMuted ? ThemeBackend.surface2 : root.volColor
                            gradColor2: root.sysMuted ? ThemeBackend.surface2 : Qt.lighter(root.volColor, 1.05)
                            gradColor3: root.sysMuted ? ThemeBackend.surface2 : Qt.lighter(root.volColor, 1.10)
                            cornerRadius: Radius.inner(root.s(6), root.s(9))
                            handleSize: root.s(22)
                            handleColor: root.sysMuted ? ThemeBackend.overlay0 : Qt.lighter(root.volColor, 1.15)
                            handleHoverColor: root.sysMuted ? ThemeBackend.subtext0 : Qt.lighter(root.volColor, 1.5)
                            handleDragColor: root.sysMuted ? ThemeBackend.text : Qt.lighter(root.volColor, 1.45)
                            handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                            onDragStarted: { volSyncDelay.stop(); root.isDraggingVol = true; }
                            onDragFinished: {
                                if (volCmdThrottle.running && volCmdThrottle.targetPct >= 0) { volCmdThrottle.stop(); volCmdThrottle.triggered(); }
                                volSyncDelay.restart();
                            }
                            onMoved: val => {
                                var pct = Math.max(0, Math.min(100, Math.round(val)));
                                volSlider.value = pct;
                                volCmdThrottle.targetPct = pct;
                                if (!volCmdThrottle.running) volCmdThrottle.start();
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)
                        visible: root.hasBrightness

                        IconButton {
                            Layout.alignment: Qt.AlignVCenter
                            size: root.s(26)
                            cornerRadius: Radius.inner(root.s(8), root.s(13))
                            centerInk: true
                            buttonIcon: root.sysBrightness > 66 ? "󰃠" : (root.sysBrightness > 33 ? "󰃟" : "󰃞")
                            iconFontSize: root.s(15)
                            accentColor: ThemeBackend.surface1
                            textColor: isHoveredOrHighlighted ? ThemeBackend.text : root.briColor
                            onClicked: {
                                briCmdThrottle.stop(); briCmdThrottle.targetPct = -1;
                                var target = root.sysBrightness > 0 ? 0 : 100;
                                root.sysBrightness = target;
                                root.setBrightness(target);
                            }
                        }

                        // DDC/CI is slow: batch the drag into a few writes.
                        Timer {
                            id: briCmdThrottle
                            interval: 400
                            property int targetPct: -1
                            onTriggered: { if (targetPct >= 0) { root.setBrightness(targetPct); targetPct = -1; } }
                        }

                        Draggable {
                            id: briSlider
                            Layout.fillWidth: true
                            implicitHeight: root.s(18)
                            from: 0.0; to: 100.0; stepSize: 1.0
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) }
                            value: root.sysBrightness
                            backgroundColor: ThemeBackend.surface1
                            accentColor: root.briColor
                            gradColor1: root.briColor
                            gradColor2: Qt.lighter(root.briColor, 1.05)
                            gradColor3: Qt.lighter(root.briColor, 1.10)
                            cornerRadius: Radius.inner(root.s(6), root.s(9))
                            handleSize: root.s(22)
                            handleColor: Qt.lighter(root.briColor, 1.15)
                            handleHoverColor: Qt.lighter(root.briColor, 1.3)
                            handleDragColor: Qt.lighter(root.briColor, 1.45)
                            handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                            onDragStarted: { briSyncDelay.stop(); root.isDraggingBri = true; }
                            onDragFinished: {
                                if (briCmdThrottle.targetPct >= 0) { briCmdThrottle.stop(); root.setBrightness(briCmdThrottle.targetPct); briCmdThrottle.targetPct = -1; }
                                briSyncDelay.restart();
                            }
                            onMoved: val => {
                                var pct = Math.max(0, Math.min(100, Math.round(val)));
                                root.sysBrightness = pct;
                                briSlider.value = pct;
                                briCmdThrottle.targetPct = pct;
                                if (!briSlider.isDragging) briCmdThrottle.restart();
                            }
                        }
                    }

                    // Night Light temperature, kept from the old centre: right = warmer.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)

                        IconButton {
                            Layout.alignment: Qt.AlignVCenter
                            size: root.s(26)
                            cornerRadius: Radius.inner(root.s(8), root.s(13))
                            buttonIcon: root.nightOn ? "󰖔" : "󰖙"
                            centerInk: true
                            iconFontSize: root.s(15)
                            accentColor: ThemeBackend.surface1
                            textColor: isHoveredOrHighlighted ? ThemeBackend.text : root.tempColor
                            onClicked: root.toggleNightLight()
                        }

                        Draggable {
                            id: tempSlider
                            Layout.fillWidth: true
                            implicitHeight: root.s(18)
                            from: 0; to: root.nightTempMax - root.nightTempMin; stepSize: 100
                            showValueBubble: true
                            valueFormatter: function(v) { return (root.nightTempMax - Math.round(v)) + "K" }
                            value: root.nightTempMax - root.nightTemp
                            backgroundColor: ThemeBackend.surface1
                            accentColor: root.tempColor
                            gradColor1: root.tempColor
                            gradColor2: Qt.lighter(root.tempColor, 1.1)
                            gradColor3: Qt.lighter(root.tempColor, 1.2)
                            cornerRadius: Radius.inner(root.s(6), root.s(9))
                            handleSize: root.s(22)
                            handleColor: Qt.lighter(root.tempColor, 1.15)
                            handleHoverColor: Qt.lighter(root.tempColor, 1.3)
                            handleDragColor: Qt.lighter(root.tempColor, 1.45)
                            handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                            onDragStarted: root.isDraggingTemp = true
                            onDragFinished: { root.isDraggingTemp = false; root.commitNightTemp(); }
                            onMoved: val => {
                                root.nightTemp = root.nightTempMax - Math.round(val);
                                tempSlider.value = val;
                                tempPreviewThrottle.pending = root.nightTemp;
                                if (!tempPreviewThrottle.running) tempPreviewThrottle.start();
                            }
                        }
                    }
                }
            }

            // 3. quick actions: night light, caffeine, wifi, bluetooth, airplane
            Item {
                id: quickActionsBox
                z: 5
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(73)
                Layout.maximumHeight: root.s(73)
                opacity: root.introQuickActions
                transform: SlideIn { progress: root.introQuickActions }

                RowLayout {
                    anchors.fill: parent
                    spacing: root.s(6)

                    QuickActionBtn {
                        id: qaNight
                        keyFocused: root.keyZone === "quick" && root.quickIndex === 0
                        iconText: "󰖔"
                        activeColor: ThemeBackend.peach
                        isActive: root.nightOn
                        onLeftClicked: root.toggleNightLight()
                    }

                    QuickActionBtn {
                        id: qaAwake
                        keyFocused: root.keyZone === "quick" && root.quickIndex === 1
                        iconText: "󰅶"
                        activeColor: Qt.tint(ThemeBackend.peach, "#5c3016")
                        isActive: KeepAwakeState.active
                        onLeftClicked: KeepAwakeState.toggle()
                        onRightClicked: PowerState.show()
                    }

                    QuickActionBtn {
                        id: qaWifi
                        keyFocused: root.keyZone === "quick" && root.quickIndex === 2
                        iconText: isActive ? root.wifiIcon : "󰤮"
                        activeColor: ThemeBackend.blue
                        isActive: root.wifiOn
                        isDisabled: !root.netReady || !root.wifiUsable
                        onLeftClicked: root.toggleWifi()
                        onRightClicked: NetworkState.show()
                    }

                    QuickActionBtn {
                        id: qaBt
                        keyFocused: root.keyZone === "quick" && root.quickIndex === 3
                        iconText: isActive ? "󰂯" : "󰂲"
                        activeColor: ThemeBackend.mauve
                        isActive: root.btOn
                        isDisabled: !root.btPresent
                        onLeftClicked: if (root.btPresent) root.btAdapter.enabled = !root.btAdapter.enabled
                        onRightClicked: BluetoothState.show()
                    }

                    QuickActionBtn {
                        id: qaAirplane
                        keyFocused: root.keyZone === "quick" && root.quickIndex === 4
                        iconText: "󰀝"
                        activeColor: ThemeBackend.red
                        isActive: root.airplaneOn
                        // Inert until Net.ready, or remember() would latch a warm-up reading.
                        isDisabled: !root.netReady || (!root.wifiUsable && !root.btPresent)
                        onLeftClicked: {
                            if (!root.airplaneOn) {
                                AirplaneState.remember(root.wifiOn, root.btOn);
                                if (root.wifiOn) root.toggleWifi();
                                if (root.btOn) root.btAdapter.enabled = false;
                            } else {
                                var restoreWifi = AirplaneState.remembered && AirplaneState.wifiBefore;
                                var restoreBt = AirplaneState.remembered && AirplaneState.btBefore;
                                if (!restoreWifi && !restoreBt) { restoreWifi = root.wifiUsable; restoreBt = !root.wifiUsable; }
                                if (restoreWifi && root.wifiUsable && !root.wifiOn) root.toggleWifi();
                                if (restoreBt && root.btPresent) root.btAdapter.enabled = true;
                                AirplaneState.forget();
                            }
                        }
                    }
                }
            }

            // 4. notifications
            NotificationBox {
                id: notifsBox
                keyActive: root.keyZone === "notifs"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: root.s(68)
                cornerRadius: root.boxRadius
                cardRadius: root.cardRadius
                baseColor: root.boxColor
                rootContext: root
                opacity: root.introNotifs
                transform: SlideIn { progress: root.introNotifs }
            }

            // 5. KDE Connect: the ring, kept from the old centre, with the ghost buttons.
            Rectangle {
                id: phoneBox
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(128)
                Layout.maximumHeight: root.s(128)
                radius: root.boxRadius
                color: root.boxColor
                opacity: root.introPhone
                transform: SlideIn { progress: root.introPhone }

                readonly property bool isDangerState: KConnState.online && !KConnState.charging && KConnState.charge >= 0 && KConnState.charge < 15
                readonly property color ringStart: ThemeBackend.blue
                readonly property color ringEnd: Qt.lighter(ringStart, 1.15)

                Connections {
                    target: KConnState
                    function onChargeChanged()   { batCanvas.requestPaint(); }
                    function onOnlineChanged()   { batCanvas.requestPaint(); }
                    function onChargingChanged() { batCanvas.requestPaint(); }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(12)
                    spacing: root.s(14)

                    Item {
                        id: ringSlot
                        Layout.preferredWidth: root.ringSize
                        Layout.preferredHeight: root.ringSize
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: centralCore
                            anchors.fill: parent
                            radius: root.ringRadius
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: ThemeBackend.surface0 }
                                GradientStop { position: 1.0; color: ThemeBackend.base }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: root.ringRadius
                                color: ThemeBackend.maroon
                                opacity: phoneBox.isDangerState ? 0.2 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 400 } }
                            }

                            Item {
                                id: ringAnim
                                anchors.fill: parent

                                property real pumpPhase: 0.0
                                NumberAnimation on pumpPhase {
                                    running: heroMa.containsMouse && KConnState.charging
                                    loops: Animation.Infinite
                                    from: 0.0; to: 1.0; duration: 1200; easing.type: Easing.InOutSine
                                    onStopped: batCanvas.requestPaint()
                                }
                                property real dischargePhase: 1.0
                                NumberAnimation on dischargePhase {
                                    running: heroMa.containsMouse && !KConnState.charging
                                    loops: Animation.Infinite
                                    from: 1.0; to: 0.0; duration: 1600; easing.type: Easing.InOutSine
                                    onStopped: batCanvas.requestPaint()
                                }
                                onPumpPhaseChanged: if (heroMa.containsMouse && KConnState.charging) batCanvas.requestPaint()
                                onDischargePhaseChanged: if (heroMa.containsMouse && !KConnState.charging) batCanvas.requestPaint()

                                Canvas {
                                    id: batCanvas
                                    anchors.fill: parent

                                    // The inset rounded rect as perimeter segments (top-centre start, clockwise), so
                                    // progress, the surge and the drain can be stroked as any [from, to] range of it.
                                    function geom() {
                                        var inset = root.s(8);
                                        var L = width - 2 * inset;
                                        var r = Math.max(0, Math.min(root.ringRadius - inset, L / 2));
                                        var st = L - 2 * r, q = Math.PI * r / 2, x = inset, y = inset;
                                        var segs = [
                                            { line: true, x0: x + L / 2, y0: y, x1: x + L - r, y1: y, len: st / 2 },
                                            { line: false, cx: x + L - r, cy: y + r, a0: -Math.PI / 2, len: q },
                                            { line: true, x0: x + L, y0: y + r, x1: x + L, y1: y + L - r, len: st },
                                            { line: false, cx: x + L - r, cy: y + L - r, a0: 0, len: q },
                                            { line: true, x0: x + L - r, y0: y + L, x1: x + r, y1: y + L, len: st },
                                            { line: false, cx: x + r, cy: y + L - r, a0: Math.PI / 2, len: q },
                                            { line: true, x0: x, y0: y + L - r, x1: x, y1: y + r, len: st },
                                            { line: false, cx: x + r, cy: y + r, a0: Math.PI, len: q },
                                            { line: true, x0: x + r, y0: y, x1: x + L / 2, y1: y, len: st / 2 }
                                        ];
                                        return { x: x, y: y, L: L, r: r, segs: segs, P: 4 * st + 2 * Math.PI * r };
                                    }
                                    function segPoint(sg, t) {
                                        if (sg.line) { var f = sg.len > 0 ? t / sg.len : 0; return { x: sg.x0 + (sg.x1 - sg.x0) * f, y: sg.y0 + (sg.y1 - sg.y0) * f }; }
                                        var rr = sg.len / (Math.PI / 2), a = sg.a0 + (rr > 0 ? t / rr : 0);
                                        return { x: sg.cx + rr * Math.cos(a), y: sg.cy + rr * Math.sin(a) };
                                    }
                                    function pointAt(g, d) {
                                        d = Math.max(0, Math.min(g.P, d));
                                        for (var i = 0; i < g.segs.length; i++) {
                                            if (d <= g.segs[i].len || i === g.segs.length - 1) return segPoint(g.segs[i], Math.min(d, g.segs[i].len));
                                            d -= g.segs[i].len;
                                        }
                                        return { x: g.x + g.L / 2, y: g.y };
                                    }
                                    function tracePath(ctx, g) {
                                        var x = g.x, y = g.y, L = g.L, r = g.r;
                                        ctx.beginPath();
                                        ctx.moveTo(x + L / 2, y);
                                        ctx.lineTo(x + L - r, y);
                                        ctx.arcTo(x + L, y, x + L, y + r, r);
                                        ctx.lineTo(x + L, y + L - r);
                                        ctx.arcTo(x + L, y + L, x + L - r, y + L, r);
                                        ctx.lineTo(x + r, y + L);
                                        ctx.arcTo(x, y + L, x, y + L - r, r);
                                        ctx.lineTo(x, y + r);
                                        ctx.arcTo(x, y, x + r, y, r);
                                        ctx.closePath();
                                    }
                                    function strokeRange(ctx, g, from, to, widthPx, style, alpha) {
                                        var a = Math.max(0, from), b = Math.min(g.P, to);
                                        if (b - a <= 0.5) return;
                                        ctx.beginPath();
                                        var pos = 0, started = false;
                                        for (var i = 0; i < g.segs.length; i++) {
                                            var sg = g.segs[i], s0 = pos, s1 = pos + sg.len;
                                            pos = s1;
                                            if (sg.len <= 0 || s1 <= a || s0 >= b) continue;
                                            var ta = Math.max(a, s0) - s0, tb = Math.min(b, s1) - s0;
                                            var p0 = segPoint(sg, ta);
                                            if (!started) { ctx.moveTo(p0.x, p0.y); started = true; }
                                            if (sg.line) { var p1 = segPoint(sg, tb); ctx.lineTo(p1.x, p1.y); }
                                            else { var rr = sg.len / (Math.PI / 2); ctx.arc(sg.cx, sg.cy, rr, sg.a0 + ta / rr, sg.a0 + tb / rr, false); }
                                        }
                                        ctx.lineWidth = widthPx;
                                        ctx.strokeStyle = style;
                                        ctx.globalAlpha = alpha;
                                        ctx.stroke();
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        var g = geom();
                                        var pct = (KConnState.online && KConnState.charge >= 0) ? (KConnState.charge / 100) : 0;
                                        var endLen = pct * g.P;
                                        ctx.lineCap = "round";
                                        ctx.lineJoin = "round";

                                        tracePath(ctx, g);
                                        ctx.lineWidth = root.s(4);
                                        ctx.strokeStyle = ThemeBackend.surface1;
                                        ctx.globalAlpha = 1.0;
                                        ctx.stroke();

                                        var fillGrad = ctx.createLinearGradient(0, height, width, 0);
                                        fillGrad.addColorStop(0, phoneBox.ringStart.toString());
                                        fillGrad.addColorStop(1, phoneBox.ringEnd.toString());
                                        strokeRange(ctx, g, 0, endLen, root.s(7), fillGrad, 1.0);

                                        if (heroMa.containsMouse && pct > 0.02) {
                                            if (KConnState.charging) {
                                                var surge = ringAnim.pumpPhase * (endLen + 0.095 * g.P) - 0.048 * g.P;
                                                if (surge > 0 && surge < endLen) {
                                                    strokeRange(ctx, g, surge - 0.064 * g.P, Math.min(endLen, surge + 0.064 * g.P), root.s(11), phoneBox.ringStart.toString(), 0.5 * Math.sin(ringAnim.pumpPhase * Math.PI));
                                                    strokeRange(ctx, g, surge - 0.032 * g.P, Math.min(endLen, surge + 0.032 * g.P), root.s(14), phoneBox.ringEnd.toString(), 0.8 * Math.sin(ringAnim.pumpPhase * Math.PI));
                                                }
                                                if (ringAnim.pumpPhase > 0.7) {
                                                    var flarePhase = (ringAnim.pumpPhase - 0.7) / 0.3;
                                                    var tip = pointAt(g, endLen);
                                                    ctx.beginPath();
                                                    ctx.arc(tip.x, tip.y, root.s(3.5) + flarePhase * root.s(7), 0, 2 * Math.PI);
                                                    ctx.fillStyle = phoneBox.ringEnd.toString();
                                                    ctx.globalAlpha = (1.0 - flarePhase) * 0.6;
                                                    ctx.fill();
                                                }
                                            } else {
                                                var drainCenter = ringAnim.dischargePhase * endLen;
                                                for (var d = 0; d < 2; d++) {
                                                    var spread = (0.032 + d * 0.024) * g.P;
                                                    strokeRange(ctx, g, drainCenter - spread, Math.min(endLen, drainCenter + spread), root.s(7) + (1 - d) * root.s(1), phoneBox.ringEnd.toString(), 0.2 * Math.sin(ringAnim.dischargePhase * Math.PI));
                                                }
                                            }
                                        }
                                        ctx.globalAlpha = 1.0;
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: root.s(3)
                                    Text {
                                        visible: KConnState.online && KConnState.charging
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(14)
                                        color: phoneBox.ringStart
                                        text: "󰂄"
                                    }
                                    Text {
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Black
                                        font.pixelSize: KConnState.online ? root.s(20) : root.s(22)
                                        color: KConnState.online ? ThemeBackend.text : ThemeBackend.overlay0
                                        text: KConnState.online ? (KConnState.charge >= 0 ? KConnState.charge + "%" : "—") : "󰏰"
                                    }
                                }
                            }

                            MouseArea {
                                id: heroMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: batCanvas.requestPaint()
                                onExited: batCanvas.requestPaint()
                                // Click refreshes, double-click rings the phone.
                                onClicked: KConnState.refresh()
                                onDoubleClicked: KConnState.ring()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.s(4)

                        // Name, then signal bars and a charging bolt on the same line, like a phone's status bar.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(8)

                            Text {
                                Layout.fillWidth: true
                                Layout.maximumWidth: implicitWidth
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: root.s(14)
                                color: KConnState.online ? ThemeBackend.text : ThemeBackend.overlay0
                                text: KConnState.online ? KConnState.deviceName : "Phone disconnected"
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }

                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                visible: KConnState.online && KConnState.sigStrength >= 0
                                spacing: root.s(2)
                                readonly property real tallest: root.s(4) + 3 * root.s(2.5)
                                height: tallest
                                Repeater {
                                    model: 4
                                    delegate: Rectangle {
                                        required property int index
                                        width: root.s(3)
                                        height: root.s(4) + index * root.s(2.5)
                                        y: parent.tallest - height
                                        radius: Radius.inner(root.s(1.5), root.s(1.5))
                                        color: index < KConnState.sigStrength ? phoneBox.ringStart : Qt.alpha(ThemeBackend.text, 0.18)
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }
                            }

                            // Some phones report strength without a network type ("Unknown").
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: KConnState.online && !!KConnState.sigType && KConnState.sigType !== "Unknown"
                                text: KConnState.sigType
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: root.s(10)
                                color: ThemeBackend.subtext0
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: KConnState.online && KConnState.charging
                                text: "\u{f140b}"   // md-lightning_bolt
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(13)
                                color: phoneBox.ringStart
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            visible: !KConnState.online
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(10)
                            color: ThemeBackend.overlay0
                            text: "KDE Connect"
                        }

                        // Ghost buttons: a chip fades in only on hover.
                        Row {
                            spacing: root.s(6)
                            visible: opacity > 0.01
                            opacity: KConnState.online ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 250 } }

                            Repeater {
                                model: [
                                    { icon: "󰆏", act: "clip",   tip: "Send clipboard" },
                                    { icon: "󰉋", act: "browse", tip: "Browse files" },
                                    { icon: "󰂚", act: "ring",   tip: "Ring" }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    width: root.s(34); height: root.s(34)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Radius.inner(width / 2)
                                        color: ThemeBackend.surface1
                                        opacity: kaMa.containsMouse ? 0.9 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(16)
                                        color: kaMa.containsMouse ? ThemeBackend.blue : ThemeBackend.overlay1
                                        text: modelData.icon
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }
                                    MouseArea {
                                        id: kaMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
                                            if (modelData.act === "clip") KConnState.sendClipboard();
                                            else if (modelData.act === "browse") KConnState.browse();
                                            else if (modelData.act === "ring") KConnState.ring();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 6. power actions: hold to fill, or click twice (remote input can't hold)
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(73)
                Layout.maximumHeight: root.s(73)
                spacing: root.s(6)

                readonly property var actions: [
                    { cmd: "lock",      icon: "\u{f033e}", weight: 1.0, danger: false, run: ["loginctl", "lock-session"] },
                    { cmd: "sleep",     icon: "ᶻ 𝗓 𝗓", weight: 1.0, danger: false, run: ["sh", "-c", "loginctl lock-session; systemctl suspend"] },
                    { cmd: "hibernate", icon: "󰤄",     weight: 1.5, danger: true,  run: ["sh", "-c", "loginctl lock-session; systemctl hibernate"] },
                    { cmd: "reboot",    icon: "󰑓",     weight: 2.5, danger: false, run: ["systemctl", "reboot"] },
                    { cmd: "poweroff",  icon: "\u{f0425}", weight: 3.5, danger: true,  run: ["systemctl", "poweroff", "-i"] }
                ].filter(a => a.cmd !== "hibernate" || root.canHibernate)

                Repeater {
                    id: powerRepeater
                    model: parent.actions

                    delegate: Rectangle {
                        id: actionCapsule
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: root.boxRadius
                        clip: true

                        opacity: root.introActions
                        transform: SlideIn { progress: root.introActions }

                        color: actionMa.containsMouse ? ThemeBackend.surface1 : root.boxColor
                        Behavior on color { ColorAnimation { duration: 200 } }
                        scale: actionMa.pressed ? (0.98 - 0.01 * modelData.weight) : (actionMa.containsMouse ? 1.02 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                        property real fillLevel: 0.0
                        property bool triggered: false
                        property real flashOpacity: 0.0
                        readonly property bool keyFocused: root.keyZone === "power" && root.powerIndex === index
                        border.width: keyFocused ? root.s(2) : 0
                        border.color: ThemeBackend.text
                        // Keyboard: the first press arms (as a click does), the second confirms.
                        function keyActivate() {
                            if (triggered || committing) return;
                            Sounds.playSfx(armed ? "reusables/fillbutton/button.wav" : "system/quick_click.wav");
                            drainAnim.stop();
                            armAnim.stop();
                            if (armed) {
                                disarmTimer.stop();
                                armed = false;
                                committing = true;
                                fillAnim.duration = 200;
                                fillAnim.start();
                            } else {
                                fillAnim.stop();
                                armed = true;
                                armAnim.start();
                                disarmTimer.restart();
                            }
                        }
                        property bool armed: false
                        property bool committing: false
                        property double pressedAt: 0

                        Timer { id: disarmTimer; interval: 3000; onTriggered: actionCapsule.disarm() }
                        function disarm() {
                            armed = false;
                            if (committing || triggered) return;
                            armAnim.stop();
                            drainAnim.duration = Math.round(900 * fillLevel);
                            drainAnim.start();
                        }

                        Canvas {
                            id: actionWaveCanvas
                            anchors.fill: parent
                            visible: actionCapsule.fillLevel > 0.001
                            renderTarget: Canvas.Image
                            renderStrategy: Canvas.Immediate

                            property real wavePhase: 0.0
                            NumberAnimation on wavePhase {
                                running: actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                loops: Animation.Infinite
                                from: 0; to: Math.PI * 2; duration: 800
                            }
                            onWavePhaseChanged: requestPaint()
                            Connections {
                                target: actionCapsule
                                function onFillLevelChanged() { actionWaveCanvas.requestPaint() }
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                if (actionCapsule.fillLevel <= 0.001) return;
                                var r = Radius.fit(actionCapsule.radius, width, height);
                                var fillY = height * (1.0 - actionCapsule.fillLevel);
                                ctx.save();
                                ctx.beginPath();
                                ctx.moveTo(r, 0); ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r);
                                ctx.lineTo(width, height - r); ctx.arcTo(width, height, width - r, height, r);
                                ctx.lineTo(r, height); ctx.arcTo(0, height, 0, height - r, r);
                                ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r);
                                ctx.closePath();
                                ctx.clip();
                                ctx.beginPath();
                                ctx.moveTo(0, fillY);
                                if (actionCapsule.fillLevel < 0.99) {
                                    var waveAmp = root.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI);
                                    ctx.bezierCurveTo(width * 0.33, fillY + Math.cos(wavePhase + Math.PI) * waveAmp, width * 0.66, fillY + Math.sin(wavePhase) * waveAmp, width, fillY);
                                    ctx.lineTo(width, height); ctx.lineTo(0, height);
                                } else {
                                    ctx.lineTo(width, 0); ctx.lineTo(width, height); ctx.lineTo(0, height);
                                }
                                ctx.closePath();
                                ctx.fillStyle = (actionCapsule.modelData.danger ? ThemeBackend.red : ThemeBackend.blue).toString();
                                ctx.fill();
                                ctx.restore();
                            }
                        }

                        Rectangle {
                            anchors.fill: parent; radius: actionCapsule.radius; color: "#ffffff"
                            opacity: actionCapsule.flashOpacity
                            PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                        }

                        Text {
                            anchors.centerIn: parent
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.s(24)
                            color: actionMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0
                            text: actionCapsule.modelData.icon
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Item {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            height: actionCapsule.height * actionCapsule.fillLevel
                            clip: true
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(24)
                                color: ThemeBackend.crust
                                text: actionCapsule.modelData.icon
                            }
                        }

                        // Durations are set at press/release, never bound to the level they animate.
                        NumberAnimation { id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0; easing.type: Easing.InSine
                            onFinished: {
                                actionCapsule.triggered = true;
                                actionCapsule.flashOpacity = 0.6;
                                cardFlashAnim.start();
                                root.runAndClose(actionCapsule.modelData.run);
                            }
                        }
                        NumberAnimation { id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0; easing.type: Easing.OutQuad }
                        NumberAnimation { id: armAnim; target: actionCapsule; property: "fillLevel"; to: 0.5; duration: 220; easing.type: Easing.OutCubic }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.s(6)
                            text: "Click again"
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: root.s(9)
                            color: ThemeBackend.crust
                            opacity: actionCapsule.armed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: actionMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onPressed: {
                                if (actionCapsule.triggered || actionCapsule.committing) return;
                                Sounds.playSfx(actionCapsule.armed ? "reusables/fillbutton/button.wav" : "system/quick_click.wav");
                                drainAnim.stop();
                                armAnim.stop();
                                if (actionCapsule.armed) {
                                    disarmTimer.stop();
                                    actionCapsule.armed = false;
                                    actionCapsule.committing = true;
                                    fillAnim.duration = 200;
                                    fillAnim.start();
                                    return;
                                }
                                actionCapsule.pressedAt = Date.now();
                                fillAnim.duration = Math.round(550 * actionCapsule.modelData.weight * (1.0 - actionCapsule.fillLevel));
                                fillAnim.start();
                            }
                            function letGo() {
                                if (actionCapsule.triggered || actionCapsule.committing || actionCapsule.fillLevel >= 1.0) return;
                                fillAnim.stop();
                                // A quick tap arms instead of draining; a second click confirms.
                                if (Date.now() - actionCapsule.pressedAt < 300) {
                                    actionCapsule.armed = true;
                                    armAnim.start();
                                    disarmTimer.restart();
                                    return;
                                }
                                drainAnim.duration = Math.round(1500 * actionCapsule.fillLevel);
                                drainAnim.start();
                            }
                            onReleased: letGo()
                            onCanceled: letGo()
                        }
                    }
                }
            }

            // 7. battery (laptops) and the power profile switch
            Rectangle {
                id: batteryBox
                Layout.fillWidth: true
                Layout.preferredHeight: root.isDesktop ? root.s(48) : root.s(72)
                Layout.maximumHeight: Layout.preferredHeight
                visible: root.isDesktop ? root.profileOptions.length > 0 : true
                radius: root.boxRadius
                color: root.isDesktop ? "transparent" : root.boxColor
                clip: true
                opacity: root.introCore
                transform: SlideIn { progress: root.introCore }

                property real fillLevel: root.animCapacity / 100
                property real maxWaveAmp: root.isCharging ? root.s(9) : root.s(1.8)
                property real waveAmp: (fillLevel < 0.99 && fillLevel > 0.01) ? maxWaveAmp * Math.sin(fillLevel * Math.PI) : 0

                Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    visible: !root.isDesktop && batteryBox.fillLevel > 0.001
                    renderTarget: Canvas.Image
                    renderStrategy: Canvas.Immediate
                    property real wavePhase: 0.0
                    NumberAnimation on wavePhase {
                        running: !root.isDesktop && batteryBox.fillLevel > 0.0 && batteryBox.fillLevel < 1.0
                        loops: Animation.Infinite
                        from: 0; to: Math.PI * 2; duration: root.isCharging ? 1200 : 3400
                    }
                    onWavePhaseChanged: requestPaint()
                    Connections {
                        target: batteryBox
                        function onFillLevelChanged() { waveCanvas.requestPaint() }
                        function onWaveAmpChanged() { waveCanvas.requestPaint() }
                    }
                    Connections {
                        target: root
                        function onBatColorFlatChanged() { waveCanvas.requestPaint() }
                        function onIsChargingChanged() { waveCanvas.requestPaint() }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (batteryBox.fillLevel <= 0.001) return;
                        var r = Radius.fit(batteryBox.radius, width, height);
                        var currentW = width * batteryBox.fillLevel;
                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(0, 0);
                        if (batteryBox.fillLevel < 0.99 && batteryBox.waveAmp > 0) {
                            var waveAmp = Math.min(batteryBox.waveAmp, currentW);
                            ctx.lineTo(currentW, 0);
                            ctx.bezierCurveTo(currentW + Math.cos(wavePhase + Math.PI) * waveAmp, height * 0.33, currentW + Math.sin(wavePhase) * waveAmp, height * 0.66, currentW, height);
                            ctx.lineTo(0, height);
                        } else {
                            ctx.lineTo(currentW, 0); ctx.lineTo(currentW, height); ctx.lineTo(0, height);
                        }
                        ctx.closePath();
                        ctx.clip();
                        ctx.beginPath();
                        ctx.moveTo(r, 0); ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r);
                        ctx.lineTo(width, height - r); ctx.arcTo(width, height, width - r, height, r);
                        ctx.lineTo(r, height); ctx.arcTo(0, height, 0, height - r, r);
                        ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();
                        ctx.fillStyle = root.batColorFlat.toString();
                        ctx.fill();
                        ctx.restore();
                    }
                }

                BatteryContent {
                    anchors.fill: parent
                    contentTextColor: ThemeBackend.text
                    iconColor: root.batColorFlat
                    visible: !root.isDesktop
                }

                Item {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    visible: !root.isDesktop
                    property real phaseOffset: Math.sin(waveCanvas.wavePhase) - Math.cos(waveCanvas.wavePhase)
                    property real centerOffset: batteryBox.fillLevel > 0.01 && batteryBox.fillLevel < 0.99 ? 0.375 * batteryBox.waveAmp * phaseOffset : 0
                    width: Math.max(0, Math.min(parent.width, (parent.width * batteryBox.fillLevel) + centerOffset))
                    clip: true
                    BatteryContent {
                        width: batteryBox.width
                        height: batteryBox.height
                        contentTextColor: ThemeBackend.crust
                        iconColor: ThemeBackend.crust
                    }
                }

                Item {
                    anchors.fill: root.isDesktop ? parent : undefined
                    anchors.right: root.isDesktop ? undefined : parent.right
                    anchors.verticalCenter: root.isDesktop ? undefined : parent.verticalCenter
                    anchors.rightMargin: root.isDesktop ? 0 : root.s(12)
                    implicitWidth: root.isDesktop ? parent.width : profileSwitch.implicitWidth
                    implicitHeight: profileSwitch.implicitHeight
                    visible: root.profileOptions.length > 0

                    Rectangle {
                        visible: !root.isDesktop
                        anchors.fill: parent
                        anchors.topMargin: root.s(1.5)
                        anchors.bottomMargin: -root.s(1.5)
                        radius: profileSwitch.cornerRadius
                        color: Qt.rgba(0, 0, 0, 0.25)
                    }

                    Rectangle {
                        z: 10
                        anchors.fill: parent
                        visible: root.keyZone === "profile"
                        color: "transparent"
                        radius: root.cardRadius
                        border.width: root.s(2)
                        border.color: ThemeBackend.text
                    }

                    Switch {
                        id: profileSwitch
                        anchors.fill: parent
                        implicitWidth: root.isDesktop ? parent.width : root.s(80) * root.profileOptions.length
                        implicitHeight: root.isDesktop ? root.s(48) : root.s(52)
                        cornerRadius: root.cardRadius
                        fontPixelSize: root.isDesktop ? root.s(14) : root.s(22)
                        options: root.profileOptions.map(d => root.isDesktop ? d.glyph + " " + d.label : d.glyph)
                        accentColor: root.profileColor
                        baseColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        activeTextColor: ThemeBackend.crust
                        currentIndex: Math.max(0, root.profileIndex)
                        onValueChanged: (idx, val) => { if (root.profileOptions[idx]) PowerInfo.setProfile(root.profileOptions[idx].key); }
                    }
                }
            }
        }
    }
}
