import "../../../services/shims"
import ".."
import QtQuick
import QtQuick.Layouts
import Quickshell

Notification {
    id: faceRoot

    fullSummary: model ? (model.summary || "Weather") : ""
    fullBody: model ? (model.body || "") : ""
    accentColor: ThemeBackend.peach

    iconArea: [
        Text {
            anchors.centerIn: parent
            text: "󰖕"
            font.family: "Iosevka Nerd Font"
            font.pixelSize: s(24)
            color: faceRoot.accentColor
        }
    ]

    headerArea: [
        Text {
            Layout.fillWidth: true
            text: model ? (model.displayName || model.appName || "Weather") : "Weather"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: s(11)
            color: ThemeBackend.subtext0
            elide: Text.ElideRight
        }
    ]
}
