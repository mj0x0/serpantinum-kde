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

    readonly property color briColor: Qt.lighter(mocha.mauve, 1.1)
    readonly property color volColor: Qt.lighter(mocha.sapphire, 1.5)
    readonly property color micColor: Qt.lighter(mocha.mauve, 1.3)
    readonly property color capsColor: Qt.lighter(mocha.peach, 1.2)
    readonly property color numColor: Qt.lighter(mocha.sapphire, 1.4)
    readonly property color airColor: Qt.lighter(mocha.red, 1.2)
    readonly property color kbColor: Qt.lighter(mocha.green, 1.2)

    property string kind: OsdState.kind
    property int briVal: OsdState.briVal
    property string stateVal: OsdState.stateVal

    readonly property bool isToggleKind: kind === "capslock" || kind === "numlock" || kind === "airplane" || kind === "keyboard"
    readonly property bool isToggleActive: kind === "keyboard" || stateVal === "on" || stateVal === "true" || stateVal === "1"

    readonly property bool isToggleAllowed: {
        if (!isToggleKind) return true;
        if (isVerticalLayout) return false;
        if (kind === "capslock") return showCapsLock;
        if (kind === "numlock") return showNumLock;
        if (kind === "airplane") return showAirplane;
        if (kind === "keyboard") return showKeyboardLayout;
        return true;
    }

    property bool isVisible: OsdState.isVisible && isToggleAllowed

    readonly property color toggleActiveColor: {
        if (kind === "capslock") return capsColor;
        if (kind === "numlock") return numColor;
        if (kind === "airplane") return airColor;
        if (kind === "keyboard") return kbColor;
        return mocha.mauve;
    }

    readonly property string toggleTitle: {
        if (kind === "capslock") return "Caps Lock";
        if (kind === "numlock") return "Num Lock";
        if (kind === "airplane") return "Airplane Mode";
        if (kind === "keyboard") return "Keyboard Layout";
        return "";
    }

    // The layout kind reuses the toggle chassis with the layout name as its status.
    readonly property string toggleStatus: kind === "keyboard" ? stateVal : (isToggleActive ? "ON" : "OFF")

    readonly property PwNode activeSink: Audio.defaultSink || (Audio.outputs && Audio.outputs.length > 0 ? Audio.outputs[0] : null)
    readonly property int volVal: activeSink && activeSink.audio ? Math.round(activeSink.audio.volume * 100) : 0
    readonly property bool isMuted: activeSink && activeSink.audio ? activeSink.audio.muted : false

    readonly property PwNode activeSource: Audio.defaultSource || (Audio.inputs && Audio.inputs.length > 0 ? Audio.inputs[0] : null)
    readonly property int micVal: activeSource && activeSource.audio ? Math.round(activeSource.audio.volume * 100) : 0
    readonly property bool isMicMuted: activeSource && activeSource.audio ? activeSource.audio.muted : false

    readonly property bool isMutedState: {
        if (kind === "volume") return isMuted;
        if (kind === "mic") return isMicMuted;
        return false;
    }

    readonly property int currentVal: {
        if (kind === "volume") return volVal;
        if (kind === "mic") return micVal;
        return briVal;
    }

    // --- osd.* settings ---
    readonly property string orientation: "" + ShellSettings.value("osd.orientation", "horizontal")
    readonly property bool isVertical: orientation === "vertical"
    readonly property bool attachToBar: ShellSettings.value("osd.attachToBar", true) !== false
    readonly property real horizontalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.horizontalPosition", 50))))
    readonly property real verticalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.verticalPosition", 90))))
    readonly property bool showCapsLock: ShellSettings.value("osd.showCapsLock", true) !== false
    readonly property bool showNumLock: ShellSettings.value("osd.showNumLock", true) !== false
    readonly property bool showAirplane: ShellSettings.value("osd.showAirplane", true) !== false
    readonly property bool showKeyboardLayout: ShellSettings.value("osd.showKeyboardLayout", true) !== false

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
    readonly property bool isAttached: attachToBar && isSolid && !isBarEffectivelyHidden && (!isSideBar || !isToggleKind) && (isSideBar ? isVertical : !isVertical)
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

    function iconFor(): string {
        if (kind === "volume") return isMuted || volVal === 0 ? "󰖁" : (volVal > 50 ? "󰕾" : "󰖀");
        if (kind === "mic") return isMicMuted || micVal === 0 ? "󰍭" : "󰍬";
        if (kind === "capslock") return "󰬈";
        if (kind === "numlock") return "󰎠";
        if (kind === "airplane") return "󰀝";
        if (kind === "keyboard") return "󰌌";
        return briVal > 66 ? "󰃠" : (briVal > 33 ? "󰃟" : "󰃞");
    }

    function iconColorFor(hovered: bool): color {
        if (hovered) return mocha.text;
        if (kind === "volume") return isMuted ? mocha.overlay0 : volColor;
        if (kind === "mic") return isMicMuted ? mocha.overlay0 : micColor;
        if (isToggleKind) return isToggleActive ? toggleActiveColor : mocha.overlay0;
        return briColor;
    }

    function iconOffset(): int {
        if (kind === "airplane" || kind === "capslock" || kind === "volume") return -1;
        if (kind === "mic" || kind === "keyboard") return 0;
        return -3;
    }

    function activeColorFor(): color {
        if (kind === "volume") return isMuted ? mocha.surface2 : volColor;
        if (kind === "mic") return isMicMuted ? mocha.surface2 : micColor;
        return briColor;
    }

    function iconClicked() {
        OsdState.restartTimer();
        if (kind === "volume") {
            if (activeSink) Audio.toggleMute(activeSink);
        } else if (kind === "mic") {
            if (activeSource) Audio.toggleMute(activeSource);
        } else if (kind === "keyboard") {
            nextLayout();
        } else if (kind === "brightness") {
            briCmdThrottle.stop();
            briCmdThrottle.targetPct = -1;
            let target = briVal > 0 ? 0 : 100;
            OsdState.briVal = target;
            OsdState.setBrightness(target);
        }
    }

    function sliderMoved(val: real, dragging: bool) {
        OsdState.restartTimer();
        let pct = Math.max(0, Math.min(100, Math.round(val)));
        if (kind === "brightness") {
            OsdState.briVal = pct;
            briCmdThrottle.targetPct = pct;
            if (!dragging) briCmdThrottle.restart();
        } else if (kind === "volume") {
            cmdThrottle.targetPct = pct;
            if (!cmdThrottle.running) cmdThrottle.start();
        } else if (kind === "mic") {
            micThrottle.targetPct = pct;
            if (!micThrottle.running) micThrottle.start();
        }
    }

    function sliderReleased() {
        OsdState.restartTimer();
        if (kind === "brightness" && briCmdThrottle.targetPct >= 0) {
            briCmdThrottle.stop();
            OsdState.setBrightness(briCmdThrottle.targetPct);
            briCmdThrottle.targetPct = -1;
        }
    }

    function nextLayout() {
        Quickshell.execDetached(["gdbus", "call", "--session", "-d", "org.kde.KWin", "-o", "/Layouts",
                                 "-m", "org.kde.KeyboardLayouts.switchToNextLayout"]);
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
                stateVal: osdWindow.stateVal,
                toggleAllowed: osdWindow.isToggleAllowed,
                muted: osdWindow.isMutedState,
                sink: osdWindow.activeSink ? osdWindow.activeSink.name : null,
                source: osdWindow.activeSource ? osdWindow.activeSource.name : null,
                sourceBound: !!(osdWindow.activeSource && osdWindow.activeSource.audio),
                brightness: OsdState.brightness,
                caps: KbLocks.caps,
                num: KbLocks.num,
                locksAvailable: KbLocks.available,
                initialized: OsdState.isInitialized,
                visible: osdWindow.isVisible
            }, null, 1);
        }
        // Not `show`: that name collides with a qs ipc subcommand.
        function peek(kind: string): void {
            if (kind === "mic") OsdState.show("mic");
            else if (kind === "brightness") OsdState.show("brightness", OsdState.sysBrightness);
            else if (kind === "capslock" || kind === "numlock" || kind === "airplane") OsdState.show(kind, "on");
            else if (kind === "keyboard") OsdState.show("keyboard", "Hebrew");
            else OsdState.show("volume");
        }
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

    Timer {
        id: briCmdThrottle
        interval: 400
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                OsdState.setBrightness(targetPct);
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
                    iconOffsetX: osdWindow.iconOffset()
                    cornerRadius: osdWindow.s(8)
                    buttonIcon: osdWindow.iconFor()
                    iconFontSize: osdWindow.s(15)
                    accentColor: mocha.surface1
                    textColor: osdWindow.iconColorFor(isHoveredOrHighlighted)
                    onClicked: osdWindow.iconClicked()
                }

                Rectangle {
                    visible: osdWindow.isToggleKind
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: osdWindow.s(28)
                    Layout.preferredHeight: osdWindow.s(22)
                    radius: osdWindow.s(6)
                    color: osdWindow.isToggleActive ? Qt.rgba(osdWindow.toggleActiveColor.r, osdWindow.toggleActiveColor.g, osdWindow.toggleActiveColor.b, 0.2) : mocha.surface1
                    border.width: 1
                    border.color: osdWindow.isToggleActive ? osdWindow.toggleActiveColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: osdWindow.toggleStatus
                        font.family: Fonts.ui
                        font.pixelSize: osdWindow.s(10)
                        font.bold: true
                        color: osdWindow.isToggleActive ? osdWindow.toggleActiveColor : mocha.overlay0
                    }
                }

                V2.Draggable {
                    id: verticalSlider
                    visible: !osdWindow.isToggleKind
                    vertical: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdWindow.s(16)
                    Layout.alignment: Qt.AlignHCenter
                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: mocha.surface1

                    readonly property color activeColor: osdWindow.activeColorFor()

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
                    onDragFinished: osdWindow.sliderReleased()
                    onMoved: val => osdWindow.sliderMoved(val, verticalSlider.isDragging)
                }

                Item {
                    id: verticalValueContainer
                    visible: !osdWindow.isToggleKind
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
                        iconOffsetX: osdWindow.iconOffset()
                        buttonIcon: osdWindow.iconFor()
                        iconFontSize: osdWindow.s(15)
                        accentColor: mocha.surface1
                        textColor: osdWindow.iconColorFor(isHoveredOrHighlighted)
                        onClicked: osdWindow.iconClicked()
                    }
                }

                RowLayout {
                    visible: osdWindow.isToggleKind
                    anchors.left: parent.left
                    anchors.leftMargin: osdWindow.s(58)
                    anchors.right: parent.right
                    anchors.rightMargin: osdWindow.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0.0, Math.min(1.0, (osdContainer.animProgress - 0.2) / 0.8))
                    spacing: osdWindow.s(8)

                    Text {
                        Layout.fillWidth: true
                        text: osdWindow.toggleTitle
                        font.family: Fonts.ui
                        font.pixelSize: osdWindow.s(14)
                        font.bold: true
                        color: mocha.text
                        elide: Text.ElideRight
                    }

                    V2.ClickButton {
                        id: toggleBtn
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: osdWindow.s(24)
                        Layout.preferredWidth: implicitWidth
                        height: osdWindow.s(24)
                        cornerRadius: osdWindow.s(6)
                        horizontalPadding: osdWindow.s(10)
                        buttonText: osdWindow.toggleStatus
                        textFontSize: osdWindow.s(11)
                        accentColor: osdWindow.isToggleActive ? osdWindow.toggleActiveColor : mocha.surface1
                        textColor: osdWindow.isToggleActive ? mocha.base : mocha.subtext0

                        onClicked: {
                            OsdState.restartTimer();
                            if (osdWindow.kind === "keyboard") osdWindow.nextLayout();
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
                    visible: !osdWindow.isToggleKind && opacity > 0.01
                    showValueBubble: false

                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: mocha.surface1

                    readonly property color activeColor: osdWindow.activeColorFor()

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
                    onDragFinished: osdWindow.sliderReleased()
                    onMoved: val => osdWindow.sliderMoved(val, horizontalSlider.isDragging)
                }

                Item {
                    id: horizontalValueContainer
                    width: osdWindow.s(58)
                    height: parent.height
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0.0, Math.min(1.0, (osdContainer.animProgress - 0.2) / 0.8))
                    visible: !osdWindow.isToggleKind && opacity > 0.01

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
