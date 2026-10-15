// Tray items pinned in Settings -> Tray, as their own bar module. The drawer never
// shows these; the tray button only counts what is left.
import "../../../services/audio"
import "../../traymenu"
import "../../../services/theme"
import "../../../services/tray"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

StatusWidget {
    id: pinned
    stateAccent: mocha.text
    property bool shown: true

    readonly property var items: {
        var out = [], all = SystemTray.items ? SystemTray.items.values : [];
        for (var i = 0; i < all.length; i++)
            if (TrayOverrides.isPinned(all[i].id, all[i].title)) out.push(all[i]);
        return out;
    }

    readonly property real cell: barWindow.s(30)
    readonly property real runLength: cell * items.length

    active: shown && items.length > 0
    revealed: barWindow.statusRevealed
    subWidth: runLength
    subHeight: runLength
    hovered: false

    Grid {
        anchors.centerIn: parent
        columns: pinned.vertical ? 1 : pinned.items.length
        spacing: 0

        Repeater {
            model: pinned.items
            delegate: Item {
                id: pin
                required property var modelData
                readonly property var ov: TrayOverrides.lookup(modelData.id, modelData.title)
                readonly property bool hasGlyph: ov !== null && ov.glyph !== ""
                width: pinned.cell
                height: pinned.cell

                Item {
                    anchors.centerIn: parent
                    width: barWindow.s(18)
                    height: width
                    scale: pinMa.pressed ? 0.9 : (pinMa.containsMouse ? 1.12 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        visible: pin.hasGlyph
                        text: pin.hasGlyph ? pin.ov.glyph : ""
                        font.family: (pin.ov && pin.ov.font) ? pin.ov.font : Fonts.icons
                        font.pixelSize: barWindow.s(17)
                        color: {
                            var k = (pin.ov && pin.ov.color) ? pin.ov.color : "";
                            if (!k) return pinMa.containsMouse ? mocha.text : mocha.subtext0;
                            return mocha[k] !== undefined ? mocha[k] : k;
                        }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Image {
                        anchors.fill: parent
                        visible: !pin.hasGlyph
                        source: pin.modelData.icon || ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(barWindow.s(36), barWindow.s(36))
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
                        if (mouse.button === Qt.MiddleButton) {
                            it.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton || it.onlyMenu) {
                            if (it.hasMenu || it.menu) {
                                var r = pin.mapToItem(null, 0, 0);
                                TrayMenuState.toggleBeside(it, Qt.rect(r.x, r.y, pin.width, pin.height), barWindow.screen);
                            } else {
                                it.activate();
                            }
                        } else {
                            it.activate();
                        }
                    }
                }
            }
        }
    }
}
