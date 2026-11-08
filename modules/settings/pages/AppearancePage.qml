import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    SettingsHeading { host: page.host; text: "Themes" }
    ThemeGrid {
        Layout.fillWidth: true
        host: page.host
    }
    SettingsHeading { host: page.host; text: "Shell look" }
    ThemeAppearanceSection {
        Layout.fillWidth: true
        host: page.host
    }
    SettingsHeading { host: page.host; text: "Colour generation" }
    ThemeMatugenSection {
        Layout.fillWidth: true
        host: page.host
    }
    SettingsHeading { host: page.host; text: "Applications" }
    ThemeAppsSection {
        Layout.fillWidth: true
        host: page.host
    }
    Text {
        Layout.fillWidth: true
        text: "Changes apply at once: the matugen hook re-renders every template in the background"
        font.family: page.host.fontFamily
        font.pixelSize: page.host.s(9)
        color: page.host.overlay0
        wrapMode: Text.Wrap
    }
}
