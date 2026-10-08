// PipeWire outputs / inputs / streams. Node filtering from serpantinum v2 (see NOTICE);
// the look is our own v1 card language. Backend is Audio.qml - native, no pactl.

import "../../services/audio"
import "../../services/layout"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire

Item {
    id: window

    Scaler {
        id: scaler
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color accent:   _theme.blue
    readonly property color danger:   _theme.red

    readonly property string activeTab: VolumeState.tab

    // Upstream tints per tab (blue / mauve / green). In our palette blue and mauve
    // are both md3.primary, so inputs and streams take distinct roles instead.
    readonly property color tabColor: {
        if (window.activeTab === "inputs") return _theme.peach;      // md3.tertiary
        if (window.activeTab === "apps")   return _theme.sapphire;   // palette.primary70
        return _theme.blue;                                          // md3.primary
    }

    // The node the big header controls: whichever is default for this tab.
    // Streams have no default, so the header keeps showing the output.
    readonly property PwNode headerNode: {
        if (window.activeTab === "inputs") return Audio.defaultSource;
        return Audio.defaultSink;
    }
    readonly property int  headerVol:  headerNode && headerNode.audio ? Math.round(headerNode.audio.volume * 100) : 0
    readonly property bool headerMute: headerNode && headerNode.audio ? headerNode.audio.muted : false

    // Keyboard selection. -1 means "nothing picked yet", so the ring only appears
    // once you actually use the keys — the mouse path stays visually unchanged.
    property int selIndex: -1
    onActiveTabChanged: selIndex = -1

    function moveSel(delta) {
        var n = window.listModel.length;
        if (n === 0) { selIndex = -1; return; }
        selIndex = selIndex < 0 ? (delta > 0 ? 0 : n - 1)
                                : Math.max(0, Math.min(n - 1, selIndex + delta));
        nodeList.positionViewAtIndex(selIndex, ListView.Contain);
    }

    function activateSel() {
        if (window.activeTab === "apps") return;          // streams have no default
        var n = window.listModel.length;
        if (selIndex < 0 || selIndex >= n) return;
        var node = window.listModel[selIndex];
        if (window.activeTab === "outputs") Audio.setDefaultOutput(node);
        else Audio.setDefaultInput(node);
    }

    // Volume keys act on the selected row if there is one, else the header device.
    function targetNode() {
        var n = window.listModel.length;
        if (selIndex >= 0 && selIndex < n) return window.listModel[selIndex];
        return window.headerNode;
    }
    function nudgeVolume(delta) {
        var node = window.targetNode();
        if (!node || !node.audio) return;
        Audio.setVolume(node, Math.round(node.audio.volume * 100) + delta);
    }
    function toggleMuteTarget() { Audio.toggleMute(window.targetNode()); }

    // Escape belongs to the popup host; everything else is ours while we are shown.
    Shortcut { sequence: "1"; onActivated: VolumeState.tab = "outputs" }
    Shortcut { sequence: "2"; onActivated: VolumeState.tab = "inputs" }
    Shortcut { sequence: "3"; onActivated: VolumeState.tab = "apps" }
    Shortcut { sequence: "Tab"; onActivated: VolumeState.tab =
                   VolumeState.tab === "outputs" ? "inputs"
                 : VolumeState.tab === "inputs"  ? "apps" : "outputs" }
    Shortcut { sequence: "Down";   onActivated: window.moveSel(1) }
    Shortcut { sequence: "Up";     onActivated: window.moveSel(-1) }
    Shortcut { sequence: "Return"; onActivated: window.activateSel() }
    Shortcut { sequence: "Enter";  onActivated: window.activateSel() }
    Shortcut { sequence: "Right"; onActivated: window.nudgeVolume(5) }
    Shortcut { sequence: "Left";  onActivated: window.nudgeVolume(-5) }
    Shortcut { sequence: "+";     onActivated: window.nudgeVolume(5) }
    Shortcut { sequence: "=";     onActivated: window.nudgeVolume(5) }
    Shortcut { sequence: "-";     onActivated: window.nudgeVolume(-5) }
    Shortcut { sequence: "M";     onActivated: window.toggleMuteTarget() }

    readonly property var listModel: {
        if (window.activeTab === "inputs") return Audio.inputs;
        if (window.activeTab === "apps")   return Audio.apps;
        return Audio.outputs;
    }

    function nodeGlyph(node, tab) {
        if (tab === "inputs") return "\u{f036c}";                    // md-microphone
        if (tab === "apps")   return "\u{f147d}";                    // md-waveform
        var d = ("" + Audio.getNodeName(node)).toLowerCase();
        if (d.indexOf("headset") !== -1 || d.indexOf("headphone") !== -1)
            return "\u{f02cb}";                                      // md-headphones
        return "\u{f04c3}";                                          // md-speaker
    }

    // The level tile scales the knob with itself, so ui.radius 46 (half its 92) is a circle.
    readonly property real levelRadius: Radius.active ? window.s(Radius.value) : window.s(14)

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1; duration: 500; easing.type: Easing.OutExpo; running: true
    }

    Rectangle {
        id: cardMask
        anchors.fill: parent
        radius: Radius.outer(s(20))
        color: "white"
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        scale: 0.96 + (0.04 * introMain)
        opacity: introMain

        Rectangle {
            anchors.fill: parent
            radius: Radius.outer(s(20))
            color: window.base
            border.color: window.surface0
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            Rectangle {
                width: parent.width * 0.7; height: width; radius: width / 2
                x: (parent.width * 0.5 - width / 2) + Math.cos(window.globalOrbitAngle) * window.s(120)
                y: (parent.height * 0.4 - height / 2) + Math.sin(window.globalOrbitAngle) * window.s(90)
                color: window.headerMute ? window.danger : window.tabColor
                opacity: 0.05
                Behavior on color { ColorAnimation { duration: 400 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(16)
                spacing: window.s(12)

                // --- Header: the default device ------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(92)
                    spacing: window.s(12)

                    // Volume as a liquid level: pulsing outline, breathing halo, shadow, rippling Canvas.
                    Item {
                        Layout.preferredWidth: window.s(92)
                        Layout.preferredHeight: window.s(92)

                        // Wall-clock driven at 45ms, not a SequentialAnimation, so it never syncs to the halo.
                        Rectangle {
                            id: corePulse
                            anchors.centerIn: parent
                            width: parent.width + window.s(6)
                            height: width
                            radius: window.levelRadius + window.s(3)
                            color: "transparent"
                            border.color: window.headerMute ? window.danger : window.tabColor
                            border.width: Math.max(1, window.s(1.5))
                            z: -2

                            property real pulseOp: 0.0
                            property real pulseSc: 1.0
                            opacity: window.headerMute ? 0.0 : pulseOp
                            scale: pulseSc

                            Timer {
                                interval: 45
                                running: !window.headerMute
                                repeat: true
                                onTriggered: {
                                    var t = Date.now() / 1000;
                                    corePulse.pulseOp = 0.12 + Math.sin(t * 2.5) * 0.05;
                                    corePulse.pulseSc = 1.008 + Math.cos(t * 3.0) * 0.005;
                                }
                            }
                        }

                        // Breathing halo.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(10)
                            height: width
                            radius: window.levelRadius + window.s(5)
                            color: window.headerMute ? window.danger : window.tabColor
                            opacity: window.headerMute ? 0.15 : 0.06
                            z: -1
                            Behavior on color { ColorAnimation { duration: 300 } }

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                running: true
                                NumberAnimation { to: 1.015; duration: 2000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;   duration: 2000; easing.type: Easing.InOutSine }
                            }
                        }

                        MultiEffect {
                            source: centralCore
                            anchors.fill: centralCore
                            shadowEnabled: true
                            shadowColor: "#000000"
                            shadowOpacity: 0.5
                            shadowBlur: 1.2
                            shadowVerticalOffset: window.s(5)
                            z: -1
                        }

                        Rectangle {
                            id: centralCore
                            anchors.fill: parent
                            radius: window.levelRadius
                            color: window.surface0
                            border.width: 2
                            border.color: window.headerMute ? window.danger
                                                            : Qt.lighter(window.tabColor, 1.1)
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: 300 } }

                            Canvas {
                                id: orbWave
                                anchors.fill: parent

                                property real wavePhase: 0.0
                                NumberAnimation on wavePhase {
                                    // Runs wherever there is liquid. Below full it is the
                                    // surface; at full it drives the current beneath it.
                                    running: window.headerVol > 0
                                    loops: Animation.Infinite
                                    from: 0; to: Math.PI * 2; duration: 1200
                                }
                                onWavePhaseChanged: requestPaint()
                                readonly property real cornerR: window.levelRadius
                                onCornerRChanged: requestPaint()

                                // At 100% the liquid reaches the top edge, so the same curve is drawn below it
                                // instead - an internal current rather than a different visual language at full.
                                readonly property real submergedDepth: 0.24

                                                                // Canvas wants a CSS colour string; a QML color with
                                // alpha stringifies to #AARRGGBB, which it misreads.
                                function rgbaStr(col, a) {
                                    return "rgba(" + Math.round(col.r * 255) + ","
                                                   + Math.round(col.g * 255) + ","
                                                   + Math.round(col.b * 255) + ","
                                                   + a + ")";
                                }

                                Connections {
                                    target: window
                                    function onHeaderVolChanged()  { orbWave.requestPaint() }
                                    function onHeaderMuteChanged() { orbWave.requestPaint() }
                                    function onTabColorChanged()   { orbWave.requestPaint() }
                                }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    if (window.headerVol <= 0) return;

                                    var fillRatio = Math.min(1, window.headerVol / 100.0);
                                    var fillY = height * (1.0 - fillRatio);
                                    var r = Radius.fit(cornerR, width, height);

                                    ctx.save();
                                    ctx.beginPath();
                                    ctx.roundedRect(0, 0, width, height, r, r);
                                    ctx.clip();

                                    ctx.beginPath();
                                    ctx.moveTo(0, fillY);
                                    if (fillRatio < 0.99) {
                                        // Amplitude peaks at half full and vanishes at both ends.
                                        var waveAmp = window.s(6) * Math.sin(fillRatio * Math.PI);
                                        var cp1y = fillY + Math.sin(orbWave.wavePhase) * waveAmp;
                                        var cp2y = fillY + Math.cos(orbWave.wavePhase + Math.PI) * waveAmp;
                                        ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    } else {
                                        ctx.lineTo(width, 0);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    }
                                    ctx.closePath();

                                    var grad = ctx.createLinearGradient(0, 0, 0, height);
                                    var c = window.headerMute ? window.danger : window.tabColor;
                                    grad.addColorStop(0, Qt.lighter(c, 1.15).toString());
                                    grad.addColorStop(1, ("" + c));
                                    ctx.fillStyle = grad;
                                    ctx.fill();

                                    if (fillRatio >= 0.99) {
                                        // Same bezier and phase as the surface wave, so motion is continuous through 100%.
                                        var hi = Qt.lighter(c, 1.35);
                                        var depth = height * orbWave.submergedDepth;
                                        var subAmp = window.s(5);
                                        var s1 = depth + Math.sin(orbWave.wavePhase) * subAmp;
                                        var s2 = depth + Math.cos(orbWave.wavePhase + Math.PI) * subAmp;

                                        ctx.beginPath();
                                        ctx.moveTo(0, depth);
                                        ctx.bezierCurveTo(width * 0.33, s2, width * 0.66, s1, width, depth);
                                        ctx.lineTo(width, 0);
                                        ctx.lineTo(0, 0);
                                        ctx.closePath();
                                        ctx.fillStyle = orbWave.rgbaStr(hi, 0.16);
                                        ctx.fill();

                                        ctx.beginPath();
                                        ctx.moveTo(0, depth);
                                        ctx.bezierCurveTo(width * 0.33, s2, width * 0.66, s1, width, depth);
                                        ctx.strokeStyle = orbWave.rgbaStr(hi, 0.40);
                                        ctx.lineWidth = Math.max(1, window.s(1.5));
                                        ctx.stroke();
                                    }

                                    ctx.restore();
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                width: parent.width * 0.85
                                horizontalAlignment: Text.AlignHCenter
                                text: window.headerVol + "%"
                                font.family: Fonts.ui
                                font.weight: Font.Black
                                font.pixelSize: window.s(19)
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: window.s(8)
                                color: window.headerVol > 55 && !window.headerMute ? window.crust : window.text
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: window.s(4)

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Audio.getNodeName(window.headerNode) || "No device"
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: window.s(13)
                            color: window.text
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Audio.getNodeSubDesc(window.headerNode)
                            font.family: Fonts.ui
                            font.pixelSize: window.s(10)
                            color: window.subtext0
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: window.s(6)
                            spacing: window.s(10)

                            Text {
                                text: window.headerMute ? "\u{f0581}" : "\u{f057e}"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: window.s(16)
                                color: window.headerMute ? window.danger : window.subtext0
                                Behavior on color { ColorAnimation { duration: 200 } }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -window.s(6)
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { Sounds.playSfx("system/quick_click.wav"); Audio.toggleMute(window.headerNode); }
                                }
                            }

                            VolumeSlider {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(18)
                                value: window.headerVol
                                muted: window.headerMute
                                accent: window.tabColor
                                trackColor: window.surface1
                                radius: window.s(9)
                                onMoved: (pct) => Audio.setVolume(window.headerNode, pct)
                            }

                            Text {
                                Layout.preferredWidth: window.s(34)
                                horizontalAlignment: Text.AlignRight
                                text: window.headerVol + "%"
                                font.family: Fonts.ui
                                font.pixelSize: window.s(10)
                                color: window.subtext0
                            }
                        }
                    }
                }

                // --- Tabs ----------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(38)
                    radius: Radius.outer(window.s(11))
                    color: Qt.alpha(window.surface0, 0.6)

                    Row {
                        anchors.centerIn: parent
                        spacing: window.s(4)

                        Repeater {
                            model: [
                                { key: "outputs", glyph: "\u{f04c3}", label: "Outputs" },
                                { key: "inputs",  glyph: "\u{f036c}", label: "Inputs"  },
                                { key: "apps",    glyph: "\u{f147d}", label: "Streams" }
                            ]
                            delegate: Rectangle {
                                id: tabBtn
                                required property var modelData
                                readonly property bool isActive: window.activeTab === modelData.key
                                width: tabContent.implicitWidth + window.s(20)
                                height: window.s(30)
                                radius: Radius.outer(window.s(9))
                                color: tabBtn.isActive ? window.tabColor
                                     : (tabMa.containsMouse ? window.surface1 : "transparent")
                                Behavior on color { ColorAnimation { duration: 180 } }

                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: window.s(7)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabBtn.modelData.glyph
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(14)
                                        color: tabBtn.isActive ? window.crust : window.subtext0
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabBtn.modelData.label
                                        font.family: Fonts.ui
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(11)
                                        color: tabBtn.isActive ? window.crust : window.subtext0
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                }

                                MouseArea {
                                    id: tabMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { Sounds.playSfx("network/switch.wav"); VolumeState.tab = tabBtn.modelData.key; }
                                }
                            }
                        }
                    }
                }

                // --- Node list -----------------------------------------------
                ListView {
                    id: nodeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: window.s(8)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: window.listModel

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuint }
                    }
                    displaced: Transition {
                        NumberAnimation { property: "y"; duration: 280; easing.type: Easing.OutQuint }
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property PwNode node: row.modelData
                        // Streams have no "default", so nothing is ever highlighted there.
                        readonly property bool isActive: window.activeTab === "outputs" ? (node === Audio.defaultSink)
                                                       : window.activeTab === "inputs"  ? (node === Audio.defaultSource)
                                                       : false
                        readonly property int  vol:   node && node.audio ? Math.round(node.audio.volume * 100) : 0
                        readonly property bool muted: node && node.audio ? node.audio.muted : false

                        width: nodeList.width
                        // The default device's own slider is the header's, so its row
                        // drops the duplicate control and collapses.
                        height: isActive ? window.s(50) : window.s(84)
                        Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }

                        radius: Radius.outer(window.s(14))
                        color: row.isActive ? window.tabColor
                             : (rowMa.containsMouse ? window.surface1 : window.surface0)
                        readonly property bool isSel: window.selIndex === index
                        border.width: row.isSel ? 2 : 1
                        border.color: row.isSel ? window.tabColor
                                    : (row.isActive ? window.tabColor : Qt.alpha(window.surface1, 0.8))
                        Behavior on color { ColorAnimation { duration: 250 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: window.activeTab !== "apps"
                            cursorShape: window.activeTab !== "apps" && !row.isActive
                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (window.activeTab === "apps" || row.isActive) return;
                                Sounds.playSfx("system/quick_click.wav");
                                if (window.activeTab === "outputs") Audio.setDefaultOutput(row.node);
                                else Audio.setDefaultInput(row.node);
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: window.s(12)
                            anchors.rightMargin: window.s(12)
                            anchors.topMargin: window.s(10)
                            anchors.bottomMargin: window.s(10)
                            spacing: window.s(8)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: window.s(10)

                                Text {
                                    text: window.nodeGlyph(row.node, window.activeTab)
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(17)
                                    color: row.isActive ? window.crust : window.text
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(2)
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: window.activeTab === "apps" ? Audio.getNodeAppName(row.node)
                                                                          : Audio.getNodeName(row.node)
                                        font.family: Fonts.ui
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(12)
                                        color: row.isActive ? window.crust : window.text
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: row.isActive ? "Active default" : Audio.getNodeSubDesc(row.node)
                                        font.family: Fonts.ui
                                        font.pixelSize: window.s(9)
                                        color: row.isActive ? Qt.darker(window.crust, 1.4) : window.subtext0
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(18)
                                visible: !row.isActive
                                spacing: window.s(10)

                                Text {
                                    text: row.muted ? "\u{f0581}" : "\u{f057e}"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(13)
                                    color: row.muted ? window.danger : window.overlay0
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -window.s(5)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { Sounds.playSfx("system/quick_click.wav"); Audio.toggleMute(row.node); }
                                    }
                                }

                                VolumeSlider {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: window.s(16)
                                    value: row.vol
                                    muted: row.muted
                                    accent: window.tabColor
                                    trackColor: Qt.alpha(window.surface2, 0.7)
                                    radius: window.s(8)
                                    onMoved: (pct) => Audio.setVolume(row.node, pct)
                                }

                                Text {
                                    Layout.preferredWidth: window.s(32)
                                    horizontalAlignment: Text.AlignRight
                                    text: row.vol + "%"
                                    font.family: Fonts.ui
                                    font.pixelSize: window.s(9)
                                    color: window.subtext0
                                }
                            }
                        }
                    }
                }

                // --- Empty state ---------------------------------------------
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: nodeList.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: window.s(8)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\u{f0581}"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: window.s(30)
                            color: Qt.alpha(window.overlay0, 0.5)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.activeTab === "apps" ? "Nothing is playing"
                                : window.activeTab === "inputs" ? "No inputs" : "No outputs"
                            font.family: Fonts.ui
                            font.pixelSize: window.s(11)
                            color: window.overlay0
                        }
                    }
                }

                // Keys are invisible otherwise; one dim line beats a legend.
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: window.s(2)
                    horizontalAlignment: Text.AlignHCenter
                    text: "\u2191\u2193 pick   \u23ce default   \u2190\u2192 volume   M mute   1\u20133 tabs"
                    font.family: Fonts.ui
                    font.pixelSize: window.s(9)
                    color: Qt.alpha(window.overlay0, 0.75)
                    elide: Text.ElideRight
                }
            }
        }
    }
}
