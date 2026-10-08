// Keep-awake: occupies the bar only while the inhibition is held.
import "../../../services/audio"
import "../../../services/keepawake"
import "../../../services/theme"
import QtQuick

StatusWidget {
    id: awake
    active: KeepAwakeState.active
    subWidth: awakeRow.implicitWidth + barWindow.s(24)
    hovered: awakeMouse.containsMouse

    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        opacity: KeepAwakeState.active ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.palette.secondary60 }
            GradientStop { position: 1.0; color: Colors.palette.secondary80 }
        }
    }
    Row {
        id: awakeRow
        anchors.verticalCenter: parent.verticalCenter
        x: awake.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0176}"
            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
            color: KeepAwakeState.active ? mocha.base : mocha.text
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
    MouseArea { id: awakeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Sounds.playSfx("system/quick_click.wav"); KeepAwakeState.toggle(); } }
}
