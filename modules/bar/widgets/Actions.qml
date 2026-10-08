// Quick action buttons: settings, search (launcher), focus dashboard; bar.actions picks which.
import "../../../services/audio"
import "../../../services/settings"
import "../../focustime"
import "../../launcher"
import "../../settings"
import QtQuick
import Quickshell

Rectangle {
    id: actions
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0

    readonly property var known: ["settings", "search", "focus"]
    readonly property var enabledActions: {
        let v = ShellSettings.value("bar.actions", null);
        if (!v || typeof v.length !== "number") return known;
        return known.filter(k => v.indexOf(k) !== -1);
    }
    readonly property bool hasContent: placed && enabledActions.length > 0

    readonly property real targetWidth: (hasContent && !vertical) ? leftLayout.width + barWindow.s(16) : 0
    readonly property real targetHeight: (hasContent && vertical) ? leftLayout.height + barWindow.s(16) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !actions.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && actions.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    visible: placed && (vertical ? height : width) > 0

    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08 * barWindow.pillBorderAlpha)
    clip: true

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady; interval: 10; onTriggered: actions.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    transform: Translate {
        x: (actions.showLayout || actions.vertical) ? 0 : barWindow.s(-200)
        y: (actions.showLayout || !actions.vertical) ? 0 : barWindow.s(-200)
        Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
        Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
    }

    Grid {
        id: leftLayout
        columns: actions.vertical ? 1 : Math.max(1, actions.enabledActions.length)
        x: actions.vertical ? (parent.width - width) / 2 : barWindow.s(8)
        y: actions.vertical ? barWindow.s(8) : (parent.height - height) / 2
        onColumnsChanged: Qt.callLater(leftLayout.forceLayout)
        spacing: barWindow.s(4)

        Repeater {
            model: actions.enabledActions
            delegate: Rectangle {
                id: btn
                required property string modelData
                readonly property bool isHovered: btnMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent"
                radius: barWindow.innerRadius
                width: barWindow.s(34)
                height: barWindow.s(34)
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: btn.modelData === "settings" ? "\u{f0493}" : btn.modelData === "search" ? "\u{f0349}" : "\u{f0109}"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(22)
                    color: btn.isHovered ? mocha.blue : mocha.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                    scale: btn.isHovered ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                }
                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Sounds.playSfx("system/quick_click.wav");
                        if (btn.modelData === "settings") SettingsState.toggle();
                        else if (btn.modelData === "search") LauncherState.toggle();
                        else FocusTimeState.toggle();
                    }
                }
            }
        }
    }
}
