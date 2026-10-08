// The bell: opens the System Panel; right-click toggles Do Not Disturb; dot = unread.
import "../../../services/audio"
import "../../notifcenter"
import "../../../services/dnd"
import "../../../services/notifications"
import QtQuick

StatusWidget {
    id: notif
    subWidth: barWindow.s(34)
    hovered: bellMouse.containsMouse
    subColor: hovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent"

    function reportPos() {
        var c = notif.reportCenter();
        NotifCenterState.iconCenterX = c.x;
        NotifCenterState.iconCenterY = c.y;
    }
    onXChanged: reportPos()
    onYChanged: reportPos()
    onWidthChanged: reportPos()
    Component.onCompleted: reportPos()
    Connections {
        target: NotifCenterState
        function onOpenChanged() { if (NotifCenterState.open) notif.reportPos(); }
    }

    Text {
        id: bell
        anchors.centerIn: parent
        text: DndState.enabled ? "󰂛" : "󰂚"
        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(20)
        color: DndState.enabled ? mocha.red : (bellMouse.containsMouse ? mocha.blue : mocha.text)
        Behavior on color { ColorAnimation { duration: 300 } }
    }
    Rectangle {
        anchors.left: bell.right
        anchors.top: bell.top
        anchors.leftMargin: -barWindow.s(4)
        anchors.topMargin: barWindow.s(2)
        width: barWindow.s(7); height: width; radius: width / 2
        color: mocha.blue
        border.width: 1
        border.color: mocha.base
        visible: opacity > 0.01
        opacity: (NotificationManager.unreadCount > 0 && !DndState.enabled) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    MouseArea {
        id: bellMouse
        hoverEnabled: true
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            Sounds.playSfx("system/quick_click.wav");
            if (mouse.button === Qt.RightButton) DndState.toggle();
            else NotifCenterState.toggle();
        }
    }
}
