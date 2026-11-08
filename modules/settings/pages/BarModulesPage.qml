import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    BarMenuCard { host: page.host }
    BarWorkspacesCard { host: page.host }
    BarTimeDateCard { host: page.host }
    BarSysmonCard { host: page.host }
    BarBatteryCard { host: page.host }
    BarMediaCard { host: page.host }
}
