// WiFi / ethernet / VPN state; opens the network popup beneath itself.
import "../../../services/audio"
import "../../../services/network"
import "../../network"
import "../../../services/theme"
import QtQuick
import Quickshell

StatusWidget {
    id: net
    subWidth: netRow.implicitWidth + barWindow.s(24)
    hovered: netMouse.containsMouse

    function reportPos() {
        var c = net.reportCenter();
        NetworkState.iconCenterX = c.x;
        NetworkState.iconCenterY = c.y;
    }
    onXChanged: reportPos()
    onYChanged: reportPos()
    onWidthChanged: reportPos()
    Component.onCompleted: reportPos()
    Connections {
        target: NetworkState
        function onOpenChanged() { if (NetworkState.open) net.reportPos(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: barWindow.innerRadius
        // Net.ready gates the 1-3s warm-up, where every device list is still empty.
        opacity: !Net.ready ? 0.0 : (barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? 1.0 : 0.0) : (barWindow.isWifiOn ? 1.0 : 0.0))
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.md3.primary }
            GradientStop { position: 1.0; color: Qt.lighter(Colors.md3.primary, 1.3) }
        }
    }

    Row {
        id: netRow
        anchors.verticalCenter: parent.verticalCenter
        x: net.vertical ? (parent.width - width) / 2 : barWindow.s(12)
        spacing: barWindow.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: barWindow.vpnActive ? "󰦝" : (barWindow.showEthernet ? "󰈀" : barWindow.wifiIcon)
            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
            color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.subtext0) : (barWindow.isWifiOn ? mocha.base : mocha.subtext0)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: barWindow.showEthernet ? barWindow.ethStatus : ((barWindow.isWifiOn ? (barWindow.wifiSsid !== "" ? barWindow.wifiSsid : "On") : "Off"))
            visible: !net.vertical && text !== ""
            font.family: Fonts.ui; font.pixelSize: barWindow.s(13); font.weight: Font.Black
            color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.text) : (barWindow.isWifiOn ? mocha.base : mocha.text)
            width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight
        }
    }
    MouseArea { id: netMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); NetworkState.toggle(); } }
}
