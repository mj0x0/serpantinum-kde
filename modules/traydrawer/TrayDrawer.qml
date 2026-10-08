// Every tray icon in one card beside the bar's tray button. Left click activates, middle is the
// secondary action, right click opens the app's menu beside the card.
import "../../services/audio"
import "../traymenu"
import "../../services/bar"
import "../../services/layout"
import "../../services/theme"
import "../../services/tray"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: drawer

    screen: TrayDrawerState.screen
    readonly property bool isOpen: TrayDrawerState.open
    visible: isOpen || prog > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-traydrawer"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // The bar strip stays clickable, so the tray button can close the drawer again.
    mask: Region { item: barHole; intersection: Intersection.Xor }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }
    MatugenColors { id: c }

    property real prog: isOpen ? 1 : 0
    Behavior on prog { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    property string hoverTitle: ""

    function close() { TrayDrawerState.hide(); }

    onIsOpenChanged: {
        hoverTitle = "";
        if (isOpen) keyCatcher.forceActiveFocus();
        else if (TrayMenuState.beside) TrayMenuState.hide();
    }
    // Picking a menu entry is the end of the errand.
    Connections {
        target: TrayMenuState
        function onTriggered() { if (TrayMenuState.beside) drawer.close(); }
    }

    function openMenu(trayItem) {
        var r = card.mapToItem(null, 0, 0);
        TrayMenuState.toggleBeside(trayItem, Qt.rect(r.x, r.y, card.width, card.height), drawer.screen);
    }

    Item {
        id: barHole
        readonly property real t: BarState.hidden ? 0 : BarState.bandThickness
        x: BarState.position === "right" ? drawer.width - t : 0
        y: BarState.position === "bottom" ? drawer.height - t : 0
        width: BarState.isVertical ? t : drawer.width
        height: BarState.isVertical ? drawer.height : t
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onEscapePressed: drawer.close()
    }

    MouseArea { anchors.fill: parent; enabled: drawer.isOpen; onClicked: drawer.close() }

    Rectangle {
        id: card

        readonly property real m: drawer.s(8)
        readonly property string edge: BarState.position
        readonly property int columns: Math.max(1, Math.min(counter.count, BarState.isVertical ? 3 : 4))

        width: Math.max(grid.implicitWidth, drawer.s(120)) + drawer.s(20)
        height: grid.implicitHeight + label.implicitHeight + drawer.s(26)
        x: edge === "left" ? BarState.leftGap
         : edge === "right" ? drawer.width - width - BarState.rightGap
         : Math.max(m, Math.min(drawer.width - width - m, TrayDrawerState.anchorX - width / 2))
        y: edge === "top" ? BarState.topGap
         : edge === "bottom" ? drawer.height - height - BarState.bottomGap
         : Math.max(m, Math.min(drawer.height - height - m, TrayDrawerState.anchorY - height / 2))

        radius: Radius.outer(drawer.s(14))
        color: c.base
        border.width: 1
        border.color: Qt.rgba(c.surface2.r, c.surface2.g, c.surface2.b, 0.9)
        opacity: drawer.prog
        scale: 0.97 + 0.03 * drawer.prog
        transform: Translate {
            x: (card.edge === "left" ? -1 : card.edge === "right" ? 1 : 0) * drawer.s(8) * (1 - drawer.prog)
            y: (card.edge === "top" ? -1 : card.edge === "bottom" ? 1 : 0) * drawer.s(8) * (1 - drawer.prog)
        }

        MouseArea { anchors.fill: parent }

        Repeater { id: counter; model: SystemTray.items; delegate: Item { visible: false } }

        Grid {
            id: grid
            x: (card.width - implicitWidth) / 2
            y: drawer.s(10)
            columns: card.columns
            spacing: drawer.s(4)

            Repeater {
                model: SystemTray.items
                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property var ov: TrayOverrides.lookup(modelData.id, modelData.title)
                    width: drawer.s(40)
                    height: width
                    radius: Radius.inner(drawer.s(10), width / 2)
                    color: cellMa.containsMouse ? c.surface1 : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Item {
                        anchors.centerIn: parent
                        width: drawer.s(22)
                        height: width
                        scale: cellMa.pressed ? 0.9 : (cellMa.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                        Text {
                            anchors.centerIn: parent
                            visible: cell.ov !== null
                            text: cell.ov ? cell.ov.glyph : ""
                            font.family: (cell.ov && cell.ov.font) ? cell.ov.font : Fonts.icons
                            font.pixelSize: drawer.s(20)
                            color: {
                                var k = (cell.ov && cell.ov.color) ? cell.ov.color : "";
                                if (!k) return c.text;
                                return c[k] !== undefined ? c[k] : k;
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: cell.ov === null
                            source: cell.modelData.icon || ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(drawer.s(44), drawer.s(44))
                            smooth: true
                        }
                    }

                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onEntered: drawer.hoverTitle = cell.modelData.tooltipTitle || cell.modelData.title || cell.modelData.id || ""
                        onExited: if (drawer.hoverTitle !== "") drawer.hoverTitle = ""
                        onClicked: mouse => {
                            if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
                            var it = cell.modelData;
                            if (mouse.button === Qt.MiddleButton) {
                                it.secondaryActivate();
                            } else if (mouse.button === Qt.RightButton || it.onlyMenu) {
                                if (it.hasMenu || it.menu) drawer.openMenu(it);
                                else { it.activate(); drawer.close(); }
                            } else {
                                it.activate();
                                drawer.close();
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            y: grid.y + grid.implicitHeight + drawer.s(6)
            width: Math.max(grid.implicitWidth, drawer.s(120))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: drawer.hoverTitle !== "" ? drawer.hoverTitle : counter.count + (counter.count === 1 ? " app" : " apps")
            font.family: Fonts.ui
            font.weight: Font.Bold
            font.pixelSize: drawer.s(10)
            color: c.subtext0
        }
    }
}
