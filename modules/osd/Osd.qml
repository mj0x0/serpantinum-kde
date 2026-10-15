import "../../services/bar"
import "../../services/audio"
import "../../services/layout"
import "../../services/osd"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: osdWindow

    screen: OsdState.screen

    WlrLayershell.namespace: "osd"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region {
        item: (osdWindow.isVisible || osdContainer.animProgress > 0.001) ? osdContainer : null
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Scaler { id: scaler; currentWidth: osdWindow.areaW }
    MatugenColors { id: mocha }
    function s(val) { return scaler.s(val) }

    readonly property color volColor: Qt.lighter(mocha.sapphire, 1.5)
    readonly property color micColor: Qt.lighter(mocha.mauve, 1.3)

    property string kind: OsdState.kind
    property bool isVisible: OsdState.isVisible

    readonly property PwNode activeSink: Audio.defaultSink || (Audio.outputs && Audio.outputs.length > 0 ? Audio.outputs[0] : null)
    readonly property int volVal: activeSink && activeSink.audio ? Math.round(activeSink.audio.volume * 100) : 0
    readonly property bool isMuted: activeSink && activeSink.audio ? activeSink.audio.muted : false

    readonly property PwNode activeSource: Audio.defaultSource || (Audio.inputs && Audio.inputs.length > 0 ? Audio.inputs[0] : null)
    readonly property int micVal: activeSource && activeSource.audio ? Math.round(activeSource.audio.volume * 100) : 0
    readonly property bool isMicMuted: activeSource && activeSource.audio ? activeSource.audio.muted : false

    readonly property bool isMutedState: kind === "mic" ? isMicMuted : isMuted
    readonly property int currentVal: kind === "mic" ? micVal : volVal

    // --- osd.* settings ---
    readonly property string orientation: "" + ShellSettings.value("osd.orientation", "horizontal")
    readonly property bool isVertical: orientation === "vertical"
    readonly property bool attachToBar: ShellSettings.value("osd.attachToBar", true) !== false
    readonly property real horizontalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.horizontalPosition", 50))))
    readonly property real verticalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.verticalPosition", 90))))

    onAttachToBarChanged: OsdState.hide()

    // Upstream hides on every settings reload, not only the three keys below.
    Connections {
        target: ShellSettings
        function onCfgChanged() { OsdState.hide() }
    }

    // --- bar.* settings ---
    property bool barAutohide: ShellSettings.value("bar.autohide", false) === true
    onBarAutohideChanged: OsdState.hide()

    property string barStyle: "" + ShellSettings.value("bar.style", "modular")
    onBarStyleChanged: OsdState.hide()

    property string barPosition: BarState.position
    property real barOpacity: {
        let op = Number(ShellSettings.value("bar.opacity", 85));
        return op > 1.0 ? (op / 100.0) : op;
    }

    // BarState.hidden is autohide || fullscreen, fed by the bar window.
    readonly property bool isBarEffectivelyHidden: barAutohide || BarState.hidden
    property bool isSideBar: barPosition === "left" || barPosition === "right"
    property bool isRightBar: barPosition === "right"
    property bool isBottomBar: barPosition === "bottom"
    property bool isSolid: (barStyle === "solid" || barStyle === "fill") && Math.round(barOpacity * 100) >= 100
    readonly property bool isAttached: attachToBar && isSolid && !isBarEffectivelyHidden && (isSideBar ? isVertical : !isVertical)
    readonly property bool isVerticalLayout: isAttached ? isSideBar : isVertical

    // The bar's own height, no popup padding, so the pill sits flush against it.
    property real barHeight: BarState.thickness

    property real cornerRadius: Radius.outer(s(12))

    property real osdWidth: isVerticalLayout ? s(58) : s(296)
    property real osdHeight: isVerticalLayout ? s(296) : s(58)
    property real collapsedWidth: s(58)

    visible: isVisible || osdContainer.animProgress > 0.001

    // The output, not the window: a hidden PanelWindow reports 100x100.
    readonly property real areaW: osdWindow.screen ? osdWindow.screen.width : Screen.width
    readonly property real areaH: osdWindow.screen ? osdWindow.screen.height : Screen.height

    property real clampedX: {
        if (isAttached) {
            if (isSideBar) {
                if (isRightBar) {
                    return areaW - barHeight - osdWidth;
                } else {
                    return barHeight;
                }
            } else {
                return (areaW - osdWidth) / 2;
            }
        } else {
            return (areaW - osdWidth) * (horizontalPosition / 100.0);
        }
    }

    property real clampedY: {
        if (isAttached) {
            if (isSideBar) {
                return (areaH - osdHeight) / 2;
            } else {
                if (isBottomBar) {
                    return areaH - barHeight - osdHeight;
                } else {
                    return barHeight;
                }
            }
        } else {
            return (areaH - osdHeight) * (verticalPosition / 100.0);
        }
    }

    // Read-only: qs -p <checkout> ipc call osd state
    IpcHandler {
        target: "osd"
        function state(): string {
            return JSON.stringify({
                window: osdWindow.width + "x" + osdWindow.height,
                area: osdWindow.areaW + "x" + osdWindow.areaH,
                barPosition: osdWindow.barPosition,
                barStyle: osdWindow.barStyle,
                barOpacity: osdWindow.barOpacity,
                barHidden: osdWindow.isBarEffectivelyHidden,
                barThickness: Math.round(osdWindow.barHeight),
                attachToBar: osdWindow.attachToBar,
                isSolid: osdWindow.isSolid,
                isSideBar: osdWindow.isSideBar,
                orientationVertical: osdWindow.isVertical,
                isAttached: osdWindow.isAttached,
                layout: osdWindow.isVerticalLayout ? "vertical" : "horizontal",
                size: Math.round(osdWindow.osdWidth) + "x" + Math.round(osdWindow.osdHeight),
                x: Math.round(osdWindow.clampedX),
                y: Math.round(osdWindow.clampedY),
                containerX: Math.round(osdContainer.x),
                containerY: Math.round(osdContainer.y),
                containerSize: Math.round(osdContainer.width) + "x" + Math.round(osdContainer.height),
                kind: osdWindow.kind,
                value: osdWindow.currentVal,
                muted: osdWindow.isMutedState,
                sink: osdWindow.activeSink ? osdWindow.activeSink.name : null,
                source: osdWindow.activeSource ? osdWindow.activeSource.name : null,
                sourceBound: !!(osdWindow.activeSource && osdWindow.activeSource.audio),
                visible: osdWindow.isVisible
            }, null, 1);
        }
        // Not `show`: that name collides with a qs ipc subcommand.
        function peek(kind: string): void { OsdState.show(kind === "mic" ? "mic" : "volume") }
    }

    Timer {
        id: cmdThrottle
        interval: 50
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                if (targetPct > 0 && osdWindow.isMuted) {
                    if (osdWindow.activeSink && osdWindow.activeSink.audio && osdWindow.activeSink.audio.muted) {
                        Audio.toggleMute(osdWindow.activeSink);
                    }
                }
                if (osdWindow.activeSink) {
                    Audio.setVolume(osdWindow.activeSink, targetPct);
                }
                targetPct = -1;
            }
        }
    }

    Timer {
        id: micThrottle
        interval: 50
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                if (targetPct > 0 && osdWindow.isMicMuted) {
                    if (osdWindow.activeSource && osdWindow.activeSource.audio && osdWindow.activeSource.audio.muted) {
                        Audio.toggleMute(osdWindow.activeSource);
                    }
                }
                if (osdWindow.activeSource) {
                    Audio.setVolume(osdWindow.activeSource, targetPct);
                }
                targetPct = -1;
            }
        }
    }

    Item {
        id: osdContainer

        property real animProgress: osdWindow.isVisible ? 1.0 : 0.0
        Behavior on animProgress {
            NumberAnimation {
                duration: osdWindow.isVisible ? 450 : 300
                easing.type: osdWindow.isVisible ? Easing.OutQuint : Easing.InCubic
            }
        }

        property real dynamicCornerRadius: osdWindow.isAttached ? Math.max(0, Math.min(osdWindow.cornerRadius, (osdWindow.isSideBar ? width : height))) : 0

        x: {
            if (osdWindow.isAttached) {
                if (osdWindow.isSideBar && osdWindow.isRightBar) {
                    return (osdWindow.clampedX + osdWindow.osdWidth) - width;
                }
                return osdWindow.clampedX;
            }
            return (osdWindow.areaW - width) * (osdWindow.horizontalPosition / 100.0);
        }
        y: {
            if (osdWindow.isAttached) {
                if (!osdWindow.isSideBar && osdWindow.isBottomBar) {
                    return (osdWindow.clampedY + osdWindow.osdHeight) - height;
                }
                return osdWindow.clampedY;
            }
            return (osdWindow.areaH - height) * (osdWindow.verticalPosition / 100.0);
        }
        width: {
            if (osdWindow.isAttached) {
                if (osdWindow.isSideBar) {
                    return osdWindow.osdWidth * animProgress;
                }
                return osdWindow.osdWidth;
            }
            if (osdWindow.isVerticalLayout) {
                return osdWindow.osdWidth;
            }
            return osdWindow.collapsedWidth + (osdWindow.osdWidth - osdWindow.collapsedWidth) * animProgress;
        }
        height: {
            if (osdWindow.isAttached) {
                if (!osdWindow.isSideBar) {
                    return osdWindow.osdHeight * animProgress;
                }
                return osdWindow.osdHeight;
            }
            if (osdWindow.isVerticalLayout) {
                return osdWindow.collapsedWidth + (osdWindow.osdHeight - osdWindow.collapsedWidth) * animProgress;
            }
            return osdWindow.osdHeight;
        }
        opacity: osdWindow.isAttached ? ((osdWindow.isVisible || animProgress > 0.001) ? 1.0 : 0.0) : Math.max(0.0, Math.min(1.0, animProgress * 1.5))

        transformOrigin: {
            if (osdWindow.isAttached) {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? Item.Right : Item.Left;
                }
                return osdWindow.isBottomBar ? Item.Bottom : Item.Top;
            }
            return Item.Center;
        }

        // Concave fillets that blend the pill into the bar's edge.
        ShaderEffect {
            visible: osdWindow.isAttached && osdContainer.dynamicCornerRadius > 0.5
            x: {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? (parent.width - osdContainer.dynamicCornerRadius) : 0;
                }
                return -osdContainer.dynamicCornerRadius;
            }
            y: {
                if (osdWindow.isSideBar) {
                    return -osdContainer.dynamicCornerRadius;
                }
                return osdWindow.isBottomBar ? (parent.height - osdContainer.dynamicCornerRadius) : 0;
            }
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            property vector2d itemSize: Qt.vector2d(width, height)
            property real cornerIndex: {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? 3.0 : 2.0;
                }
                return osdWindow.isBottomBar ? 3.0 : 1.0;
            }
            property color color: mocha.base
            fragmentShader: Qt.resolvedUrl("../../services/reusables/assets/shaders/ui/corner_cutout.frag.qsb")
        }

        ShaderEffect {
            visible: osdWindow.isAttached && osdContainer.dynamicCornerRadius > 0.5
            x: {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? (parent.width - osdContainer.dynamicCornerRadius) : 0;
                }
                return parent.width;
            }
            y: {
                if (osdWindow.isSideBar) {
                    return parent.height;
                }
                return osdWindow.isBottomBar ? (parent.height - osdContainer.dynamicCornerRadius) : 0;
            }
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            property vector2d itemSize: Qt.vector2d(width, height)
            property real cornerIndex: {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? 1.0 : 0.0;
                }
                return osdWindow.isBottomBar ? 2.0 : 0.0;
            }
            property color color: mocha.base
            fragmentShader: Qt.resolvedUrl("../../services/reusables/assets/shaders/ui/corner_cutout.frag.qsb")
        }

        Rectangle {
            id: osdBox
            anchors.fill: parent
            color: mocha.base
            radius: osdWindow.cornerRadius
            border.width: osdWindow.isAttached ? 0 : 1
            border.color: osdWindow.isAttached ? "transparent" : mocha.surface0
            clip: true

            // Square off the two corners that meet the bar.
            Rectangle {
                visible: osdWindow.isAttached && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            Rectangle {
                visible: osdWindow.isAttached && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: mocha.base
            }

            HoverHandler {
                id: osdHoverHandler
                onHoveredChanged: {
                    OsdState.isHovered = hovered;
                    if (hovered) {
                        OsdState.cancelHide();
                    } else {
                        OsdState.requestHide();
                    }
                }
            }

            ColumnLayout {
                visible: osdWindow.isVerticalLayout
                anchors.fill: parent
                anchors.topMargin: osdWindow.s(14)
                anchors.bottomMargin: osdWindow.s(14)
                anchors.leftMargin: osdWindow.s(10)
                anchors.rightMargin: osdWindow.s(10)
                spacing: osdWindow.s(10)

                V2.IconButton {
                    Layout.alignment: Qt.AlignHCenter
                    size: osdWindow.s(26)
                    iconOffsetX: osdWindow.kind === "mic" ? 0 : -1
                    cornerRadius: osdWindow.s(8)
                    buttonIcon: {
                        if (osdWindow.kind === "mic") {
                            return osdWindow.isMicMuted || osdWindow.micVal === 0 ? "󰍭" : "󰍬";
                        }
                        return osdWindow.isMuted || osdWindow.volVal === 0 ? "󰖁" : (osdWindow.volVal > 50 ? "󰕾" : "󰖀");
                    }
                    iconFontSize: osdWindow.s(15)
                    accentColor: mocha.surface1
                    textColor: {
                        if (isHoveredOrHighlighted) return mocha.text;
                        if (osdWindow.kind === "mic") {
                            return osdWindow.isMicMuted ? mocha.overlay0 : osdWindow.micColor;
                        }
                        return osdWindow.isMuted ? mocha.overlay0 : osdWindow.volColor;
                    }
                    onClicked: {
                        OsdState.restartTimer();
                        if (osdWindow.kind === "mic") {
                            if (osdWindow.activeSource) {
                                Audio.toggleMute(osdWindow.activeSource);
                            }
                        } else if (osdWindow.activeSink) {
                            Audio.toggleMute(osdWindow.activeSink);
                        }
                    }
                }

                V2.Draggable {
                    id: verticalSlider
                    vertical: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdWindow.s(16)
                    Layout.alignment: Qt.AlignHCenter
                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: mocha.surface1

                    readonly property color activeColor: {
                        if (osdWindow.kind === "mic") {
                            return osdWindow.isMicMuted ? mocha.surface2 : osdWindow.micColor;
                        }
                        return osdWindow.isMuted ? mocha.surface2 : osdWindow.volColor;
                    }

                    accentColor: activeColor
                    gradColor1: activeColor
                    gradColor2: Qt.lighter(activeColor, 1.05)
                    gradColor3: Qt.lighter(activeColor, 1.10)
                    cornerRadius: osdWindow.s(5)
                    handleSize: osdWindow.s(22)
                    showValueBubble: false

                    handleColor: (osdWindow.isMutedState) ? mocha.overlay0 : Qt.lighter(activeColor, 1.15)
                    handleHoverColor: (osdWindow.isMutedState) ? mocha.subtext0 : Qt.lighter(activeColor, 1.5)
                    handleDragColor: (osdWindow.isMutedState) ? mocha.text : Qt.lighter(activeColor, 1.45)
                    handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                    onDragStarted: OsdState.cancelHide()
                    onDragFinished: OsdState.restartTimer()
                    onMoved: val => {
                        OsdState.restartTimer();
                        let pct = Math.max(0, Math.min(100, Math.round(val)));
                        if (osdWindow.kind === "mic") {
                            micThrottle.targetPct = pct;
                            if (!micThrottle.running) micThrottle.start();
                        } else {
                            cmdThrottle.targetPct = pct;
                            if (!cmdThrottle.running) cmdThrottle.start();
                        }
                    }
                }

                Item {
                    id: verticalValueContainer
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: osdWindow.s(26)
                    Layout.preferredHeight: osdWindow.s(26)

                    Text {
                        anchors.centerIn: parent
                        text: Math.round(verticalSlider.effectiveValue).toString()
                        font.family: Fonts.ui
                        font.pixelSize: osdWindow.s(13)
                        font.bold: true
                        color: osdWindow.isMutedState ? mocha.overlay0 : mocha.text
                    }
                }
            }

            Item {
                visible: !osdWindow.isVerticalLayout
                anchors.fill: parent

                Item {
                    width: osdWindow.s(58)
                    height: parent.height
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    V2.IconButton {
                        anchors.centerIn: parent
                        size: osdWindow.s(30)
                        cornerRadius: osdWindow.s(8)
                        iconOffsetX: osdWindow.kind === "mic" ? 0 : -1
                        buttonIcon: {
                            if (osdWindow.kind === "mic") {
                                return osdWindow.isMicMuted || osdWindow.micVal === 0 ? "󰍭" : "󰍬";
                            }
                            return osdWindow.isMuted || osdWindow.volVal === 0 ? "󰖁" : (osdWindow.volVal > 50 ? "󰕾" : "󰖀");
                        }
                        iconFontSize: osdWindow.s(15)
                        accentColor: mocha.surface1
                        textColor: {
                            if (isHoveredOrHighlighted) return mocha.text;
                            if (osdWindow.kind === "mic") {
                                return osdWindow.isMicMuted ? mocha.overlay0 : osdWindow.micColor;
                            }
                            return osdWindow.isMuted ? mocha.overlay0 : osdWindow.volColor;
                        }
                        onClicked: {
                            OsdState.restartTimer();
                            if (osdWindow.kind === "mic") {
                                if (osdWindow.activeSource) {
                                    Audio.toggleMute(osdWindow.activeSource);
                                }
                            } else if (osdWindow.activeSink) {
                                Audio.toggleMute(osdWindow.activeSink);
                            }
                        }
                    }
                }

                V2.Draggable {
                    id: horizontalSlider
                    width: Math.max(0, osdContainer.width - osdWindow.s(116))
                    height: osdWindow.s(18)
                    anchors.left: parent.left
                    anchors.leftMargin: osdWindow.s(58)
                    anchors.right: parent.right
                    anchors.rightMargin: osdWindow.s(58)
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0.0, Math.min(1.0, (osdContainer.animProgress - 0.2) / 0.8))
                    visible: opacity > 0.01
                    showValueBubble: false

                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: mocha.surface1

                    readonly property color activeColor: {
                        if (osdWindow.kind === "mic") {
                            return osdWindow.isMicMuted ? mocha.surface2 : osdWindow.micColor;
                        }
                        return osdWindow.isMuted ? mocha.surface2 : osdWindow.volColor;
                    }

                    accentColor: activeColor
                    gradColor1: activeColor
                    gradColor2: Qt.lighter(activeColor, 1.05)
                    gradColor3: Qt.lighter(activeColor, 1.10)
                    cornerRadius: osdWindow.s(5)
                    handleSize: osdWindow.s(22)

                    handleColor: (osdWindow.isMutedState) ? mocha.overlay0 : Qt.lighter(activeColor, 1.15)
                    handleHoverColor: (osdWindow.isMutedState) ? mocha.subtext0 : Qt.lighter(activeColor, 1.5)
                    handleDragColor: (osdWindow.isMutedState) ? mocha.text : Qt.lighter(activeColor, 1.45)
                    handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                    onDragStarted: OsdState.cancelHide()
                    onDragFinished: OsdState.restartTimer()
                    onMoved: val => {
                        OsdState.restartTimer();
                        let pct = Math.max(0, Math.min(100, Math.round(val)));
                        if (osdWindow.kind === "mic") {
                            micThrottle.targetPct = pct;
                            if (!micThrottle.running) micThrottle.start();
                        } else {
                            cmdThrottle.targetPct = pct;
                            if (!cmdThrottle.running) cmdThrottle.start();
                        }
                    }
                }

                Item {
                    id: horizontalValueContainer
                    width: osdWindow.s(58)
                    height: parent.height
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0.0, Math.min(1.0, (osdContainer.animProgress - 0.2) / 0.8))
                    visible: opacity > 0.01

                    Text {
                        anchors.centerIn: parent
                        text: Math.round(horizontalSlider.effectiveValue).toString()
                        font.family: Fonts.ui
                        font.pixelSize: osdWindow.s(13)
                        font.bold: true
                        color: osdWindow.isMutedState ? mocha.overlay0 : mocha.text
                    }
                }
            }
        }
    }
}
