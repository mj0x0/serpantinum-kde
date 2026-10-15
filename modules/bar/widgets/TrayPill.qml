// Tray button in the status pills' chrome. Items pinned in Settings -> Tray sit in the
// bar beside the button; everything else lives in the drawer it opens.
import "../../../services/audio"
import "../../traydrawer"
import "../../traymenu"
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

    readonly property var allItems: SystemTray.items ? SystemTray.items.values : []
    readonly property var pinnedItems: {
        var out = [];
        for (var i = 0; i < allItems.length; i++)
            if (TrayOverrides.isPinned(allItems[i].id, allItems[i].title)) out.push(allItems[i]);
        return out;
    }
    readonly property int drawerCount: allItems.length - pinnedItems.length
    readonly property int count: allItems.length

    readonly property real cell: barWindow.s(26)
    readonly property real buttonCell: barWindow.s(34)
    readonly property real runLength: pinnedItems.length * cell + (drawerCount > 0 ? buttonCell : 0)

    active: shown && (pinnedItems.length > 0 || drawerCount > 0)
    revealed: barWindow.statusRevealed
    subWidth: runLength
    subHeight: runLength
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

    Grid {
        anchors.centerIn: parent
        columns: trayPill.vertical ? 1 : (trayPill.pinnedItems.length + 1)
        spacing: 0

        Repeater {
            model: trayPill.pinnedItems
            delegate: Item {
                id: pin
                required property var modelData
                readonly property var ov: TrayOverrides.lookup(modelData.id, modelData.title)
                width: trayPill.cell
                height: trayPill.cell

                Item {
                    anchors.centerIn: parent
                    width: barWindow.s(17)
                    height: width
                    scale: pinMa.pressed ? 0.9 : (pinMa.containsMouse ? 1.12 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        visible: pin.ov !== null && pin.ov.glyph !== ""
                        text: pin.ov ? pin.ov.glyph : ""
                        font.family: (pin.ov && pin.ov.font) ? pin.ov.font : Fonts.icons
                        font.pixelSize: barWindow.s(16)
                        color: {
                            var k = (pin.ov && pin.ov.color) ? pin.ov.color : "";
                            if (!k) return trayPill.onColor;
                            return mocha[k] !== undefined ? mocha[k] : k;
                        }
                    }
                    Image {
                        anchors.fill: parent
                        visible: !(pin.ov !== null && pin.ov.glyph !== "")
                        source: pin.modelData.icon || ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(barWindow.s(34), barWindow.s(34))
                        smooth: true
                    }
                }

                MouseArea {
                    id: pinMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        Sounds.playSfx("system/quick_click.wav");
                        var it = pin.modelData;
                        if (mouse.button === Qt.MiddleButton) it.secondaryActivate();
                        else if (mouse.button === Qt.RightButton || it.onlyMenu) {
                            if (it.hasMenu || it.menu) {
                                var r = pin.mapToItem(null, 0, 0);
                                TrayMenuState.toggleBeside(it, Qt.rect(r.x, r.y, pin.width, pin.height), barWindow.screen);
                            } else it.activate();
                        } else it.activate();
                    }
                }
            }
        }

        Item {
            visible: trayPill.drawerCount > 0
            width: visible ? trayPill.buttonCell : 0
            height: visible ? trayPill.buttonCell : 0

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
    }
}
