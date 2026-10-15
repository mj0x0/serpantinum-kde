// Volume and mic OSD: a pill on the overlay layer, sitting just inside the bar's edge.
// serpantinum v2's Osd, cut down to the two kinds Plasma lets us disable precisely.
import "../../services/bar"
import "../../services/layout"
import "../../services/osd"
import "../../services/theme"
import QtQuick
import Quickshell
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

    readonly property color accent: OsdState.kind === "mic" ? mocha.mauve : mocha.sapphire
    readonly property string glyph: {
        if (OsdState.kind === "mic")
            return OsdState.shownMuted ? "\u{f036d}" : "\u{f036c}";
        if (OsdState.shownMuted || OsdState.shownValue === 0) return "\u{f075f}";
        if (OsdState.shownValue < 34) return "\u{f057f}";
        if (OsdState.shownValue < 67) return "\u{f0580}";
        return "\u{f057e}";
    }

    Rectangle {
        id: card
        width: osd.s(296)
        height: osd.s(58)
        radius: Radius.outer(osd.s(14))
        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.07)

        // Sits inside whichever edge carries the bar, centred on the other axis.
        readonly property real edge: (BarState.hidden ? 0 : BarState.bandThickness) + osd.s(18)
        x: BarState.position === "left" ? edge
         : BarState.position === "right" ? osd.width - width - edge
         : (osd.width - width) / 2
        y: BarState.position === "top" ? edge
         : BarState.position === "bottom" ? osd.height - height - edge
         : (osd.height - height) / 2

        property real anim: OsdState.visible ? 1 : 0
        Behavior on anim { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        opacity: anim
        transform: Translate {
            x: BarState.position === "left" ? -osd.s(16) * (1 - card.anim)
             : BarState.position === "right" ? osd.s(16) * (1 - card.anim) : 0
            y: BarState.position === "bottom" ? osd.s(16) * (1 - card.anim)
             : (BarState.position === "top" ? -osd.s(16) * (1 - card.anim) : 0)
        }

        Text {
            id: icon
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
            id: pct
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
            id: track
            anchors.left: icon.right
            anchors.leftMargin: osd.s(14)
            anchors.right: pct.left
            anchors.rightMargin: osd.s(12)
            anchors.verticalCenter: parent.verticalCenter
            height: osd.s(6)
            radius: height / 2
            color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.9)

            Rectangle {
                width: Math.max(0, Math.min(1, OsdState.shownValue / 100)) * parent.width
                height: parent.height
                radius: parent.radius
                color: OsdState.shownMuted ? mocha.overlay2 : osd.accent
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
