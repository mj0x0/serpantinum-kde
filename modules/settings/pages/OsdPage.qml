import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    OsdSection {
        Layout.fillWidth: true
        host: page.host
    }
}
