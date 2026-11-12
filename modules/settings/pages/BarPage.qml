import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    BarStyleSection {
        Layout.fillWidth: true
        host: page.host
    }
    BarPlacementSection {
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
