// Active window: its app icon and caption from the KWin bridge, capped at 300 px and gone
// when nothing is focused; click opens the launcher. serpantinum v2's FocusWidget.
import "../../../services/audio"
import "../../launcher"
import "../../../services/window"
import "../../../services/theme"
import QtQuick
import Quickshell

Rectangle {
    id: focus
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    property bool isHovered: focusMouse.containsMouse

    readonly property var activeWin: {
        var w = WindowService.windows;
        for (var i = 0; i < w.length; i++) if (w[i].active) return w[i];
        return null;
    }
    readonly property string caption: activeWin ? ("" + (activeWin.caption || "")).trim() : ""
    readonly property string appId: activeWin ? ("" + (activeWin.appId || "")) : ""
    readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string iconName: entry && entry.icon ? entry.icon : appId
    readonly property bool hasWindow: caption !== ""

    readonly property real maxWidth: barWindow.s(300)
    readonly property real iconSize: barWindow.s(22)
    readonly property real maxTextWidth: Math.max(0, maxWidth - barWindow.s(24) - iconSize - hRow.spacing)
    readonly property real targetWidth: (placed && !vertical && hasWindow) ? Math.min(maxWidth, barWindow.s(24) + iconSize + hRow.spacing + titleText.width) : 0
    readonly property real targetHeight: (placed && vertical && hasWindow) ? barWindow.barHeight : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !focus.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && focus.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !focus.vertical; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: focus.vertical; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    visible: placed && ((vertical ? height : width) > 0 || opacity > 0)
    clip: true

    color: grouped ? "transparent" : (isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : barWindow.pillBg)
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 * barWindow.pillBorderAlpha : 0.05 * barWindow.pillBorderAlpha)
    Behavior on color { ColorAnimation { duration: 200 } }
    opacity: hasWindow ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    component AppIcon : Item {
        width: focus.iconSize; height: focus.iconSize
        Image {
            id: img
            anchors.fill: parent
            source: focus.iconName ? "image://icon/" + focus.iconName : ""
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !img.visible
            text: "✦"
            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14)
            color: mocha.subtext0
        }
    }

    Row {
        id: hRow
        visible: !focus.vertical
        anchors.verticalCenter: parent.verticalCenter
        x: barWindow.s(12)
        spacing: barWindow.s(8)
        AppIcon { anchors.verticalCenter: parent.verticalCenter }
        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: focus.caption
            font.family: Fonts.ui; font.pixelSize: barWindow.s(12); font.weight: Font.Bold
            color: mocha.text
            elide: Text.ElideRight
            width: Math.min(implicitWidth, focus.maxTextWidth)
        }
    }
    AppIcon { visible: focus.vertical; anchors.centerIn: parent }

    MouseArea { id: focusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Sounds.playSfx("system/quick_click.wav"); LauncherState.toggle(); } }
}
