// Tray button in the status pills' chrome; every tray icon lives in the drawer it opens.
import "../../../services/audio"
import "../../traydrawer"
import "../../../services/theme"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

StatusWidget {
    id: trayPill
    property bool shown: true
    readonly property int count: counter.count
    readonly property bool isOpen: TrayDrawerState.open && TrayDrawerState.screen === barWindow.screen

    active: shown && count > 0
    revealed: barWindow.statusRevealed
    subWidth: barWindow.s(34)
    hovered: trayMouse.containsMouse

    Component.onCompleted: TrayDrawerState.register(trayPill)
    Component.onDestruction: TrayDrawerState.unregister(trayPill)

    // Counts the items without drawing them.
    Repeater { id: counter; model: SystemTray.items; delegate: Item { visible: false } }

    // Always the light neutral gradient, like the other filled status pills.
    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.palette.neutral_variant80 }
            GradientStop { position: 1.0; color: Colors.palette.neutral_variant90 }
        }
    }

    Text {
        anchors.centerIn: parent
        text: "\u{f15fc}"   // md-dots_grid
        font.family: Fonts.icons
        font.pixelSize: barWindow.s(17)
        color: mocha.base
    }

    MouseArea {
        id: trayMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Sounds.playSfx("system/quick_click.wav");
            var p = trayPill.reportCenter();
            TrayDrawerState.toggle(p.x, p.y, barWindow.screen);
        }
    }
}
