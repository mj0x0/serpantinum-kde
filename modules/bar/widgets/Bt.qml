// Bluetooth: visible only while the adapter is on; opens the Bluetooth popup beneath itself.
import "../../../services/audio"
import "../../bluetooth"
import "../../../services/theme"
import QtQuick

StatusWidget {
    id: bt
    active: barWindow.btEnabled
    subWidth: btRow.implicitWidth + barWindow.s(24)
    hovered: btMouse.containsMouse

    function reportPos() {
        var c = bt.reportCenter();
        BluetoothState.iconCenterX = c.x;
        BluetoothState.iconCenterY = c.y;
    }
    onXChanged: reportPos()
    onYChanged: reportPos()
    onWidthChanged: reportPos()
    Component.onCompleted: reportPos()
    Connections {
        target: BluetoothState
        function onOpenChanged() { if (BluetoothState.open) bt.reportPos(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        opacity: barWindow.isBtOn ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.md3.secondary }
            GradientStop { position: 1.0; color: Qt.lighter(Colors.md3.secondary, 1.3) }
        }
    }
    Row {
        id: btRow
        anchors.verticalCenter: parent.verticalCenter
        x: bt.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(8)
        Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.btIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isBtOn ? mocha.base : mocha.subtext0 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: barWindow.btDevice
            visible: !bt.vertical && text !== ""
            font.family: Fonts.ui; font.pixelSize: barWindow.s(13); font.weight: Font.Black
            color: barWindow.isBtOn ? mocha.base : mocha.text
            width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight
        }
    }
    MouseArea { id: btMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Sounds.playSfx("system/quick_click.wav"); BluetoothState.toggle(); } }
}
