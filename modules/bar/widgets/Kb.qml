// Keyboard layout (KWin /Layouts); click cycles to the next one.
import "../../../services/audio"
import "../../../services/theme"
import QtQuick
import Quickshell

StatusWidget {
    id: kb
    subWidth: kbRow.implicitWidth + barWindow.s(24)
    hovered: kbMouse.containsMouse

    Row {
        id: kbRow
        anchors.verticalCenter: parent.verticalCenter
        x: kb.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(8)
        Text { anchors.verticalCenter: parent.verticalCenter; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: kb.hovered ? mocha.text : mocha.overlay2 }
        Text { visible: !kb.vertical; anchors.verticalCenter: parent.verticalCenter; text: barWindow.kbLayout; font.family: Fonts.ui; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: mocha.text }
    }
    MouseArea {
        id: kbMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["gdbus", "call", "--session", "-d", "org.kde.KWin", "-o", "/Layouts", "-m", "org.kde.KeyboardLayouts.switchToNextLayout"]) }
    }
}
