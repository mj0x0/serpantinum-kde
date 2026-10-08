// Apps keeping the machine awake, with their count; collapses while none do. The 8 s
// grace rides out apps that drop and re-request (Firefox measured at 4.8-7.1 s).
import "../../../services/audio"
import "../../power"
import "../../../services/power"
import "../../../services/theme"
import QtQuick

StatusWidget {
    id: power
    readonly property int count: PowerInfo.activeCount
    readonly property bool holding: count > 0 || PowerInfo.screenBlocked || PowerInfo.sleepBlocked
    property bool shownHold: false
    onHoldingChanged: {
        if (holding) { hideGrace.stop(); shownHold = true; }
        else hideGrace.restart();
    }
    Timer { id: hideGrace; interval: 8000; onTriggered: power.shownHold = false }
    // base16's magenta slot; base16 isn't lightness-controlled, so floor it to keep the dark text readable.
    readonly property color accent: {
        var c = Colors.base16.base0d;
        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.max(c.hslLightness, 0.55), 1);
    }

    active: shownHold
    subWidth: powerRow.implicitWidth + barWindow.s(24)
    hovered: powerMouse.containsMouse

    function reportPos() {
        var c = power.reportCenter();
        PowerState.iconCenterX = c.x;
        PowerState.iconCenterY = c.y;
    }
    onXChanged: reportPos()
    onYChanged: reportPos()
    onWidthChanged: reportPos()
    Component.onCompleted: { shownHold = holding; reportPos(); }
    Connections {
        target: PowerState
        function onOpenChanged() { if (PowerState.open) power.reportPos(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        opacity: power.shownHold ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: power.accent; Behavior on color { ColorAnimation { duration: 400 } } }
            GradientStop { position: 1.0; color: Qt.lighter(power.accent, 1.3); Behavior on color { ColorAnimation { duration: 400 } } }
        }
    }
    Row {
        id: powerRow
        anchors.verticalCenter: parent.verticalCenter
        x: power.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(6)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f04b3}"
            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
            color: mocha.base
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !power.vertical && power.count > 0
            text: power.count
            font.family: Fonts.ui; font.pixelSize: barWindow.s(13); font.weight: Font.Black
            color: mocha.base
        }
    }
    MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Sounds.playSfx("system/quick_click.wav"); PowerState.toggle(); } }
}
