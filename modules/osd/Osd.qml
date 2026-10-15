// Volume and mic OSD: a pill on the overlay layer. Placement follows serpantinum v2 --
// it attaches to the bar only when the bar is solid/fill at full opacity and the
// orientations agree; otherwise it sits at osd.horizontalPosition/verticalPosition.
import "../../services/bar"
import "../../services/layout"
import "../../services/osd"
import "../../services/settings"
import "../../services/theme"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: osd

    WlrLayershell.namespace: "osd"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: OsdState.visible || card.anim > 0.001

    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: (OsdState.visible || card.anim > 0.001) ? card : null }

    Scaler { id: scaler; currentWidth: Screen.width }
    MatugenColors { id: mocha }
    function s(v) { return scaler.s(v) }

    // --- placement, upstream's rules ---
    readonly property bool attachToBar: ShellSettings.value("osd.attachToBar", true) !== false
    readonly property int horizontalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.horizontalPosition", 50))))
    readonly property int verticalPosition: Math.max(0, Math.min(100, Number(ShellSettings.value("osd.verticalPosition", 90))))
    readonly property bool isVertical: ("" + ShellSettings.value("osd.orientation", "horizontal")) === "vertical"

    readonly property string barStyle: "" + ShellSettings.value("bar.style", "modular")
    readonly property real barOpacity: {
        var op = Number(ShellSettings.value("bar.opacity", 85));
        return op > 1.0 ? op / 100.0 : op;
    }
    readonly property bool barAutohide: ShellSettings.value("bar.autohide", false) === true
    readonly property bool isSideBar: BarState.isVertical
    readonly property bool isSolid: (barStyle === "solid" || barStyle === "fill") && Math.round(barOpacity * 100) >= 100
    readonly property bool isAttached: attachToBar && isSolid && !barAutohide && !BarState.hidden
                                       && (isSideBar ? isVertical : !isVertical)
    readonly property bool isVerticalLayout: isAttached ? isSideBar : isVertical
    readonly property real barThickness: BarState.hidden ? 0 : BarState.bandThickness

    readonly property real osdWidth: isVerticalLayout ? s(58) : s(296)
    readonly property real osdHeight: isVerticalLayout ? s(296) : s(58)

    readonly property real clampedX: {
        if (!isAttached) return (osd.width - osdWidth) * (horizontalPosition / 100.0);
        if (!isSideBar) return (osd.width - osdWidth) / 2;
        return BarState.position === "right" ? osd.width - barThickness - osdWidth : barThickness;
    }
    readonly property real clampedY: {
        if (!isAttached) return (osd.height - osdHeight) * (verticalPosition / 100.0);
        if (isSideBar) return (osd.height - osdHeight) / 2;
        return BarState.position === "bottom" ? osd.height - barThickness - osdHeight : barThickness;
    }

    readonly property color accent: OsdState.kind === "mic" ? mocha.mauve : mocha.sapphire
    readonly property string glyph: {
        if (OsdState.kind === "mic")
            return OsdState.shownMuted ? "\u{f036d}" : "\u{f036c}";
        if (OsdState.shownMuted || OsdState.shownValue === 0) return "\u{f075f}";
        if (OsdState.shownValue < 34) return "\u{f057f}";
        if (OsdState.shownValue < 67) return "\u{f0580}";
        return "\u{f057e}";
    }
    readonly property real fill: Math.max(0, Math.min(1, OsdState.shownValue / 100))

    // Read-only: qs -p <checkout> ipc call osd state
    IpcHandler {
        target: "osd"
        function state(): string {
            return JSON.stringify({
                screen: osd.width + "x" + osd.height,
                barPosition: BarState.position,
                barStyle: osd.barStyle,
                barOpacity: osd.barOpacity,
                barHidden: BarState.hidden,
                barThickness: Math.round(osd.barThickness),
                attachToBar: osd.attachToBar,
                isSolid: osd.isSolid,
                isSideBar: osd.isSideBar,
                orientationVertical: osd.isVertical,
                isAttached: osd.isAttached,
                layout: osd.isVerticalLayout ? "vertical" : "horizontal",
                size: Math.round(osd.osdWidth) + "x" + Math.round(osd.osdHeight),
                x: Math.round(osd.clampedX),
                y: Math.round(osd.clampedY),
                cardX: Math.round(card.x),
                cardY: Math.round(card.y),
                visible: OsdState.visible
            }, null, 1);
        }
        function show(): void { OsdState.show("volume") }
    }

    Rectangle {
        id: card
        x: osd.clampedX
        y: osd.clampedY
        width: osd.osdWidth
        height: osd.osdHeight
        radius: Radius.outer(osd.s(14))
        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.07)

        property real anim: OsdState.visible ? 1 : 0
        Behavior on anim { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        opacity: anim
        // Slides in from the edge it is nearest.
        transform: Translate {
            x: osd.isVerticalLayout ? (BarState.position === "right" ? osd.s(16) * (1 - card.anim)
                                                                     : -osd.s(16) * (1 - card.anim)) : 0
            y: osd.isVerticalLayout ? 0
             : ((osd.isAttached && BarState.position === "top") || (!osd.isAttached && osd.verticalPosition < 50)
                ? -osd.s(16) * (1 - card.anim) : osd.s(16) * (1 - card.anim))
        }

        // --- horizontal: icon, bar, percentage in a row ---
        Item {
            anchors.fill: parent
            visible: !osd.isVerticalLayout

            Text {
                id: hIcon
                anchors.left: parent.left
                anchors.leftMargin: osd.s(18)
                anchors.verticalCenter: parent.verticalCenter
                text: osd.glyph
                font.family: Fonts.icons
                font.pixelSize: osd.s(22)
                color: OsdState.shownMuted ? mocha.overlay2 : osd.accent
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                id: hPct
                anchors.right: parent.right
                anchors.rightMargin: osd.s(18)
                anchors.verticalCenter: parent.verticalCenter
                text: OsdState.shownMuted ? "muted" : OsdState.shownValue + "%"
                font.family: Fonts.ui
                font.pixelSize: osd.s(12)
                font.weight: Font.Black
                color: OsdState.shownMuted ? mocha.overlay2 : mocha.text
            }
            Rectangle {
                anchors.left: hIcon.right
                anchors.leftMargin: osd.s(14)
                anchors.right: hPct.left
                anchors.rightMargin: osd.s(12)
                anchors.verticalCenter: parent.verticalCenter
                height: osd.s(6)
                radius: height / 2
                color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.9)
                Rectangle {
                    width: osd.fill * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: OsdState.shownMuted ? mocha.overlay2 : osd.accent
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }

        // --- vertical: icon on top, bar filling upward, percentage at the foot ---
        Item {
            anchors.fill: parent
            visible: osd.isVerticalLayout

            Text {
                id: vIcon
                anchors.top: parent.top
                anchors.topMargin: osd.s(18)
                anchors.horizontalCenter: parent.horizontalCenter
                text: osd.glyph
                font.family: Fonts.icons
                font.pixelSize: osd.s(22)
                color: OsdState.shownMuted ? mocha.overlay2 : osd.accent
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                id: vPct
                anchors.bottom: parent.bottom
                anchors.bottomMargin: osd.s(16)
                anchors.horizontalCenter: parent.horizontalCenter
                text: OsdState.shownMuted ? "\u{f075f}" : OsdState.shownValue + "%"
                font.family: OsdState.shownMuted ? Fonts.icons : Fonts.ui
                font.pixelSize: osd.s(OsdState.shownMuted ? 13 : 11)
                font.weight: Font.Black
                color: OsdState.shownMuted ? mocha.overlay2 : mocha.text
            }
            Rectangle {
                anchors.top: vIcon.bottom
                anchors.topMargin: osd.s(14)
                anchors.bottom: vPct.top
                anchors.bottomMargin: osd.s(12)
                anchors.horizontalCenter: parent.horizontalCenter
                width: osd.s(6)
                radius: width / 2
                color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.9)
                clip: true
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: osd.fill * parent.height
                    radius: parent.radius
                    color: OsdState.shownMuted ? mocha.overlay2 : osd.accent
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
