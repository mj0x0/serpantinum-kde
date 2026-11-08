import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    BarPlacementSection {
        Layout.fillWidth: true
        host: page.host
    }
    BarStyleSection {
        Layout.fillWidth: true
        host: page.host
    }
    BarAutohideSection {
        Layout.fillWidth: true
        host: page.host
    }
    BarLayoutSection {
        Layout.fillWidth: true
        host: page.host
    }
}
