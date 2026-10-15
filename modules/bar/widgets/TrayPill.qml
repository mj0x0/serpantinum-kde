// Tray button in the status pills' chrome; it opens the drawer. Items pinned in
// Settings -> Tray are not counted here -- the TrayPinned module shows those.
import "../../../services/audio"
import "../../traydrawer"
import "../../../services/theme"
import "../../../services/tray"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

StatusWidget {
    id: trayPill
    stateAccent: Colors.palette.neutral_variant80
    property bool shown: true
    readonly property bool isOpen: TrayDrawerState.open && TrayDrawerState.screen === barWindow.screen

    readonly property int count: {
        var n = 0, all = SystemTray.items ? SystemTray.items.values : [];
        for (var i = 0; i < all.length; i++)
            if (!TrayOverrides.isPinned(all[i].id, all[i].title)) n++;
        return n;
    }

    active: shown && count > 0
    revealed: barWindow.statusRevealed
    subWidth: barWindow.s(34)
    hovered: trayMouse.containsMouse

    Component.onCompleted: TrayDrawerState.register(trayPill)
    Component.onDestruction: TrayDrawerState.unregister(trayPill)

    // Always the light neutral gradient, like the other filled status pills.
    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        opacity: trayPill.fillVisible ? 1.0 : 0.0
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
        color: trayPill.onColor
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
