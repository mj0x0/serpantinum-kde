import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "City ID"
        glyph: "\u{f0146}"
        desc: "OpenWeather numeric id, from openweathermap.org/city"
        SettingsPathField {
            host: page.host
            implicitWidth: page.host.s(180)
            value: "" + ShellSettings.value("weather.cityId", "")
            onCommitted: v => ShellSettings.setValue("weather.cityId", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Units"
        glyph: "\u{f050f}"
        desc: "metric °C, imperial °F, standard K"
        SettingsChips {
            host: page.host
            options: ["metric", "imperial", "standard"]
            current: "" + ShellSettings.value("weather.unit", "metric")
            onPicked: v => ShellSettings.setValue("weather.unit", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "API key"
        glyph: "\u{f0306}"
        desc: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
            ? "Set. Type a new one to replace it."
            : "Not set. openweathermap.org gives you one free."
        Item {
            implicitWidth: keyField.implicitWidth + clearKey.implicitWidth + page.host.s(10)
            implicitHeight: keyField.implicitHeight

            SettingsSecretField {
                id: keyField
                host: page.host
                anchors.verticalCenter: parent.verticalCenter
                placeholder: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
                    ? "••••••••  press Enter to replace" : "paste key, press Enter"
                onCommitted: v => ShellSettings.setValue("weather.apiKey", ("" + v).trim())
            }
            SettingsBtn {
                id: clearKey
                host: page.host
                anchors.left: keyField.right
                anchors.leftMargin: page.host.s(10)
                anchors.verticalCenter: parent.verticalCenter
                label: "Clear"
                visible: ("" + ShellSettings.value("weather.apiKey", "")) !== ""
                onClicked: ShellSettings.setValue("weather.apiKey", "")
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Stored in settings.json. helpers/.env still works as a fallback for all three."
        font.family: page.host.fontFamily
        font.pixelSize: page.host.s(9)
        color: page.host.overlay0
        wrapMode: Text.Wrap
    }
}
