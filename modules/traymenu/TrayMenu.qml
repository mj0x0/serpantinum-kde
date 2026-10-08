// Tray app menus drawn by the shell (QsMenuOpener) instead of Qt's native popup: a card by the
// tray icon, side cards for submenus, checkbox and radio states.
import "../../services/bar"
import "../../services/layout"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    screen: TrayMenuState.screen
    readonly property bool isOpen: TrayMenuState.open
    visible: isOpen || rootProg > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell-traymenu"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // The bar strip stays clickable, so another tray icon switches menus.
    mask: Region { item: barHole; intersection: Intersection.Xor }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }
    MatugenColors { id: c }

    property real rootProg: isOpen ? 1 : 0
    Behavior on rootProg { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Open submenus, deepest last: { entry, parentX, parentW, y }.
    property var stack: []

    function close() { TrayMenuState.hide(); }

    function openSub(level, entry, card, row) {
        if (stack.length > level && stack[level].entry === entry) {
            closeFrom(level + 1);
            return;
        }
        let r = row.mapToItem(null, 0, 0);
        let k = card.mapToItem(null, 0, 0);
        let next = stack.slice(0, level);
        next.push({ entry: entry, parentX: k.x, parentW: card.width, y: r.y - s(6) });
        stack = next;
    }
    function closeFrom(level) { if (stack.length > level) stack = stack.slice(0, level); }

    onIsOpenChanged: {
        stack = [];
        if (isOpen) keyCatcher.forceActiveFocus();
    }
    Connections {
        target: TrayMenuState
        function onItemChanged() { win.stack = []; }
    }

    Item {
        id: barHole
        readonly property real t: BarState.hidden ? 0 : BarState.bandThickness
        x: BarState.position === "right" ? win.width - t : 0
        y: BarState.position === "bottom" ? win.height - t : 0
        width: BarState.isVertical ? t : win.width
        height: BarState.isVertical ? win.height : t
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onEscapePressed: win.close()
    }

    MouseArea { anchors.fill: parent; enabled: win.isOpen; onClicked: win.close() }

    component MenuCard : Rectangle {
        id: card
        property var menuHandle: null
        property int level: 0
        property real progress: 0

        QsMenuOpener { id: opener; menu: card.menuHandle }

        // Reserve the lead column only when some entry has an icon or a toggle.
        readonly property bool hasLead: {
            let v = opener.children ? opener.children.values : [];
            for (let i = 0; i < v.length; i++)
                if (v[i] && (v[i].icon || v[i].buttonType !== QsMenuButtonType.None)) return true;
            return false;
        }

        width: Math.min(win.s(420), Math.max(win.s(200), col.implicitWidth + win.s(12)))
        height: col.implicitHeight + win.s(12)
        radius: Radius.outer(win.s(14))
        color: c.base
        border.width: 1
        border.color: Qt.rgba(c.surface2.r, c.surface2.g, c.surface2.b, 0.9)
        opacity: progress
        scale: 0.97 + 0.03 * progress

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: win.s(6)
            y: win.s(6)
            width: card.width - win.s(12)
            spacing: 0

            Repeater {
                model: opener.children
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property var entry: modelData
                    readonly property bool sep: entry ? entry.isSeparator : false
                    readonly property bool checked: entry ? entry.checkState === Qt.Checked : false
                    readonly property bool subOpen: win.stack.length > card.level && win.stack[card.level].entry === entry

                    Layout.fillWidth: true
                    implicitWidth: sep ? 0 : content.implicitWidth + win.s(20)
                    implicitHeight: sep ? win.s(9) : win.s(30)

                    Rectangle {
                        visible: row.sep
                        anchors.centerIn: parent
                        width: parent.width - win.s(12)
                        height: 1
                        color: Qt.rgba(c.text.r, c.text.g, c.text.b, 0.08)
                    }

                    Rectangle {
                        visible: !row.sep
                        anchors.fill: parent
                        radius: Radius.inner(win.s(9), win.s(12))
                        color: (rowMa.containsMouse || row.subOpen) && row.entry && row.entry.enabled ? c.surface1 : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    RowLayout {
                        id: content
                        visible: !row.sep
                        anchors.fill: parent
                        anchors.leftMargin: win.s(10)
                        anchors.rightMargin: win.s(10)
                        spacing: win.s(10)
                        opacity: row.entry && row.entry.enabled ? 1.0 : 0.4

                        Item {
                            visible: card.hasLead
                            Layout.preferredWidth: win.s(16)
                            Layout.preferredHeight: win.s(16)

                            Image {
                                anchors.fill: parent
                                visible: row.entry && row.entry.buttonType === QsMenuButtonType.None && !!row.entry.icon
                                source: row.entry && row.entry.icon ? row.entry.icon : ""
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            Rectangle {
                                visible: row.entry && row.entry.buttonType === QsMenuButtonType.CheckBox
                                anchors.fill: parent
                                anchors.margins: win.s(1)
                                radius: Radius.inner(win.s(4), win.s(5))
                                color: row.checked ? c.blue : "transparent"
                                border.width: row.checked ? 0 : Math.max(1, win.s(1.5))
                                border.color: c.overlay1
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.checked
                                    text: "\u{f012c}"   // md-check
                                    font.family: Fonts.icons
                                    font.pixelSize: win.s(12)
                                    color: c.crust
                                }
                            }
                            Rectangle {
                                visible: row.entry && row.entry.buttonType === QsMenuButtonType.RadioButton
                                anchors.fill: parent
                                anchors.margins: win.s(1)
                                radius: width / 2
                                color: "transparent"
                                border.width: Math.max(1, win.s(1.5))
                                border.color: row.checked ? c.blue : c.overlay1
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: row.checked
                                    width: parent.width * 0.5
                                    height: width
                                    radius: width / 2
                                    color: c.blue
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.entry ? row.entry.text : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.family: Fonts.ui
                            font.pixelSize: win.s(12)
                            color: c.text
                        }

                        Text {
                            visible: row.entry && row.entry.hasChildren
                            text: "\u{f0142}"   // md-chevron_right
                            font.family: Fonts.icons
                            font.pixelSize: win.s(14)
                            color: c.subtext0
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        enabled: !row.sep
                        hoverEnabled: true
                        cursorShape: row.entry && row.entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: {
                            if (!row.entry || !row.entry.enabled) return;
                            if (row.entry.hasChildren) win.openSub(card.level, row.entry, card, row);
                            else win.closeFrom(card.level);
                        }
                        onClicked: {
                            if (!row.entry || !row.entry.enabled) return;
                            if (row.entry.hasChildren) { win.openSub(card.level, row.entry, card, row); return; }
                            row.entry.triggered();
                            TrayMenuState.triggered();
                            win.close();
                        }
                    }
                }
            }
        }
    }

    // Root menu: by the icon on the bar's edge, clear of the bar like the popups.
    MenuCard {
        id: rootCard
        menuHandle: TrayMenuState.item ? TrayMenuState.item.menu : null
        level: 0
        progress: win.rootProg

        readonly property real m: win.s(8)
        // Beside the tray drawer's card there is no bar edge to slide from.
        readonly property string edge: TrayMenuState.beside ? "" : BarState.position
        readonly property rect br: TrayMenuState.besideRect
        x: TrayMenuState.beside
           ? (br.x + br.width + m + width <= win.width - m ? br.x + br.width + m : Math.max(m, br.x - m - width))
         : edge === "left" ? BarState.leftGap
         : edge === "right" ? win.width - width - BarState.rightGap
         : Math.max(m, Math.min(win.width - width - m, TrayMenuState.anchorX - width / 2))
        y: TrayMenuState.beside ? Math.max(m, Math.min(win.height - height - m, br.y))
         : edge === "top" ? BarState.topGap
         : edge === "bottom" ? win.height - height - BarState.bottomGap
         : Math.max(m, Math.min(win.height - height - m, TrayMenuState.anchorY - height / 2))
        transform: Translate {
            x: (rootCard.edge === "left" ? -1 : rootCard.edge === "right" ? 1 : 0) * win.s(8) * (1 - rootCard.progress)
            y: (rootCard.edge === "top" ? -1 : rootCard.edge === "bottom" ? 1 : 0) * win.s(8) * (1 - rootCard.progress)
        }
    }

    Repeater {
        model: win.stack.length
        delegate: MenuCard {
            id: sub
            required property int index
            readonly property var sd: win.stack.length > index ? win.stack[index] : null
            readonly property real gap: win.s(4)
            level: index + 1
            menuHandle: sd ? sd.entry : null
            progress: win.rootProg
            x: !sd ? 0 : (sd.parentX + sd.parentW + gap + width <= win.width - win.s(8)
                          ? sd.parentX + sd.parentW + gap
                          : Math.max(win.s(8), sd.parentX - gap - width))
            y: !sd ? 0 : Math.max(win.s(8), Math.min(win.height - height - win.s(8), sd.y))
        }
    }
}
