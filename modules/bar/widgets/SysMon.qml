// CPU, RAM and temperature from SysData, subscribed only while placed; click opens the
// System Usage quick action. Pill is ours; wave and circle are serpantinum v2's ring gauge.
import "../../../services/audio"
import "../../../services/sysdata"
import "../../../services/theme"
import QtQuick
import Quickshell

Rectangle {
    id: sysmon
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0

    readonly property string style: barWindow.sysmonStyle
    readonly property bool gaugeMode: style === "wave" || style === "circle"

    property bool subscribed: false
    readonly property bool wantSubscribe: placed && showLayout
    onWantSubscribeChanged: updateSubscription()
    function updateSubscription() {
        if (wantSubscribe && !subscribed) { subscribed = true; SysData.subscribe(); }
        else if (!wantSubscribe && subscribed) { subscribed = false; SysData.unsubscribe(); }
    }
    Component.onCompleted: updateSubscription()
    Component.onDestruction: if (subscribed) { subscribed = false; SysData.unsubscribe(); }

    readonly property real targetWidth: (placed && !vertical) ? hRow.implicitWidth + barWindow.s(20) : 0
    readonly property real targetHeight: (placed && vertical) ? vCol.implicitHeight + barWindow.s(20) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !sysmon.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && sysmon.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    visible: placed && (vertical ? height : width) > 0
    clip: true

    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05 * barWindow.pillBorderAlpha)

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady && barWindow.isDataReady; interval: 100; onTriggered: sysmon.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    property real wavePhase: 0.0
    NumberAnimation on wavePhase { from: 0; to: Math.PI * 2; duration: 1800; loops: Animation.Infinite; running: sysmon.subscribed && sysmon.visible }

    component SysPill : Rectangle {
        id: pill
        property real value: 0
        property string textVal: ""
        property string icon: ""
        property color accent: mocha.mauve

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
        readonly property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        readonly property real fillY: height * (1.0 - fillRatio)
        readonly property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? barWindow.s(3.5) * Math.sin(fillRatio * Math.PI) : 0
        readonly property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(sysmon.wavePhase) - Math.cos(sysmon.wavePhase))

        implicitWidth: barWindow.s(52)
        implicitHeight: barWindow.s(30)
        radius: barWindow.innerRadius
        color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.6)
        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.06)
        border.width: 1
        clip: true

        Canvas {
            id: pillCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (pill.fillRatio <= 0) return;
                ctx.save();
                var r = Math.min(pill.radius, Math.min(width, height) / 2);
                ctx.beginPath();
                ctx.moveTo(r, 0); ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r);
                ctx.lineTo(width, height - r); ctx.arcTo(width, height, width - r, height, r);
                ctx.lineTo(r, height); ctx.arcTo(0, height, 0, height - r, r);
                ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r);
                ctx.closePath();
                ctx.clip();
                ctx.beginPath();
                ctx.moveTo(0, pill.fillY);
                if (pill.waveAmp > 0) {
                    ctx.bezierCurveTo(width * 0.33, pill.fillY + Math.cos(sysmon.wavePhase + Math.PI) * pill.waveAmp, width * 0.66, pill.fillY + Math.sin(sysmon.wavePhase) * pill.waveAmp, width, pill.fillY);
                } else {
                    ctx.lineTo(width, pill.fillY);
                }
                ctx.lineTo(width, height); ctx.lineTo(0, height);
                ctx.closePath();
                var grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.lighter(pill.accent, 1.25).toString());
                grad.addColorStop(1, pill.accent.toString());
                ctx.fillStyle = grad;
                ctx.globalAlpha = 0.95;
                ctx.fill();
                ctx.restore();
            }
            Connections {
                target: sysmon
                enabled: pill.waveAmp > 0 && sysmon.visible
                function onWavePhaseChanged() { pillCanvas.requestPaint(); }
            }
            Connections {
                target: pill
                function onFillRatioChanged() { pillCanvas.requestPaint(); }
                function onAccentChanged() { pillCanvas.requestPaint(); }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: barWindow.s(4)
            Text { text: pill.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.subtext0; anchors.verticalCenter: parent.verticalCenter }
            Text { text: pill.textVal; font.family: Fonts.ui; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: mocha.text; anchors.verticalCenter: parent.verticalCenter }
        }

        // The filled part re-inks the label dark, clipped to the liquid.
        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height, Math.max(0, parent.height * pill.fillRatio - pill.waveCenterOffset))
            clip: true
            visible: pill.fillRatio > 0
            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: pill.height
                Row {
                    anchors.centerIn: parent
                    spacing: barWindow.s(4)
                    Text { text: pill.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: Qt.rgba(mocha.crust.r, mocha.crust.g, mocha.crust.b, 0.75); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: pill.textVal; font.family: Fonts.ui; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: mocha.crust; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }

    component SysGauge : Item {
        id: gauge
        property real value: 0
        property string textVal: ""
        property string icon: ""
        property color accent: mocha.mauve

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
        readonly property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        readonly property bool showText: textVal !== ""

        implicitWidth: barWindow.s(28)
        implicitHeight: barWindow.s(28)

        ShaderEffect {
            anchors.fill: parent
            property vector2d itemSize: Qt.vector2d(width, height)
            property real fillRatio: gauge.fillRatio
            property real strokeWidth: barWindow.s(2.2)
            property real useSineWave: sysmon.style === "circle" ? 0.0 : 1.0
            property color accentColor: gauge.accent
            property vector4d params: Qt.vector4d(barWindow.s(0.9), 0.0, 0.0, 0.0)
            fragmentShader: Qt.resolvedUrl("../../../services/reusables/assets/shaders/gauges/circular_wave_gauge.frag.qsb")
        }

        Text {
            anchors.centerIn: parent
            text: gauge.showText ? gauge.textVal : gauge.icon
            font.family: gauge.showText ? Fonts.ui : "Iosevka Nerd Font"
            font.pixelSize: barWindow.s(gauge.showText ? 9 : 11)
            font.weight: gauge.showText ? Font.Black : Font.Normal
            color: mocha.text
        }
    }

    // One stat, drawn as whichever shape the style asks for.
    component SysStat : Item {
        id: stat
        property string statKey: "cpu"
        property bool narrow: false

        readonly property real value: {
            if (statKey === "ram") return isNaN(SysData.ramPercent) ? 0 : SysData.ramPercent / 100.0;
            if (statKey === "temp") return Math.max(0, Math.min(1, isNaN(SysData.temp) ? 0 : SysData.temp / 100.0));
            return isNaN(SysData.cpu) ? 0 : SysData.cpu / 100.0;
        }
        readonly property string icon: statKey === "ram" ? "\u{f035b}" : (statKey === "temp" ? "\u{f050f}" : "\u{f035c}")
        readonly property color accent: statKey === "ram" ? mocha.sapphire : (statKey === "temp" ? mocha.red : mocha.mauve)
        readonly property string reading: {
            if (statKey === "ram") return Math.round(SysData.ramPercent) + "";
            if (statKey === "temp") return Math.round(SysData.temp) + "";
            return Math.round(SysData.cpu) + "";
        }
        // The pill has room for a unit; the gauge labels temperature only, as upstream does.
        readonly property string pillText: statKey === "temp" ? reading + "°" : (narrow ? reading : reading + "%")
        readonly property string gaugeText: statKey === "temp" ? reading : ""

        implicitWidth: shape.implicitWidth
        implicitHeight: shape.implicitHeight

        Loader {
            id: shape
            sourceComponent: sysmon.gaugeMode ? gaugeShape : pillShape
        }

        Component {
            id: pillShape
            SysPill {
                value: stat.value
                textVal: stat.pillText
                icon: stat.icon
                accent: stat.accent
                implicitWidth: barWindow.s(stat.narrow ? 40 : 52)
            }
        }

        Component {
            id: gaugeShape
            SysGauge {
                value: stat.value
                textVal: stat.gaugeText
                icon: stat.icon
                accent: stat.accent
            }
        }
    }

    Row {
        id: hRow
        visible: !sysmon.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(6)
        SysStat { statKey: "cpu" }
        SysStat { statKey: "ram" }
        SysStat { statKey: "temp" }
    }
    Column {
        id: vCol
        visible: sysmon.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(6)
        SysStat { statKey: "cpu"; narrow: true }
        SysStat { statKey: "ram"; narrow: true }
        SysStat { statKey: "temp"; narrow: true }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["qs", "-p", barWindow.shellPath + "/shell.qml", "ipc", "call", "floating", "openTab", "1"]) }
    }
}
