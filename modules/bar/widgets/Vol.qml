// Volume: click opens the audio popup, right-click mutes, wheel nudges 5%.
import "../../volume"
import "../../../services/audio"
import "../../../services/theme"
import QtQuick

StatusWidget {
    id: vol
    subWidth: volRow.implicitWidth + barWindow.s(24)
    hovered: volMouse.containsMouse

    function reportPos() {
        var c = vol.reportCenter();
        VolumeState.iconCenterX = c.x;
        VolumeState.iconCenterY = c.y;
    }
    onXChanged: reportPos()
    onYChanged: reportPos()
    onWidthChanged: reportPos()
    Component.onCompleted: reportPos()
    Connections {
        target: VolumeState
        function onOpenChanged() { if (VolumeState.open) vol.reportPos(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        opacity: barWindow.isSoundActive ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.md3.tertiary }
            GradientStop { position: 1.0; color: Qt.lighter(Colors.md3.tertiary, 1.3) }
        }
    }
    Row {
        id: volRow
        anchors.verticalCenter: parent.verticalCenter
        x: vol.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: barWindow.volIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
            color: barWindow.isSoundActive ? mocha.base : mocha.subtext0
        }
        Text {
            visible: !vol.vertical
            anchors.verticalCenter: parent.verticalCenter
            text: barWindow.volPercent
            font.family: Fonts.ui; font.pixelSize: barWindow.s(13); font.weight: Font.Black
            color: barWindow.isSoundActive ? mocha.base : mocha.text
        }
    }
    MouseArea {
        id: volMouse
        hoverEnabled: true
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            Sounds.playSfx("system/quick_click.wav");
            if (mouse.button === Qt.RightButton) { if (Audio.defaultSink) Audio.toggleMute(Audio.defaultSink); }
            else VolumeState.toggle();
        }
        property int acc: 0
        onWheel: wheel => {
            acc += wheel.angleDelta.y;
            while (Math.abs(acc) >= 120) {
                var step = acc > 0 ? 5 : -5;
                acc -= acc > 0 ? 120 : -120;
                if (Audio.defaultSink) Audio.setVolume(Audio.defaultSink, Math.max(0, Math.min(100, barWindow.volPct + step)));
            }
        }
    }
}
