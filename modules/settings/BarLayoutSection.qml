// The module arranger, upstream's bar/general/BarLayoutEditor.qml.

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var host

    spacing: root.host.s(6)

    Text {
        Layout.fillWidth: true
        Layout.topMargin: root.host.s(8)
        text: "Layout"
        font.family: root.host.fontFamily
        font.pixelSize: root.host.s(12)
        color: root.host.text
    }

    BarArranger {
        Layout.fillWidth: true
        host: root.host
    }
}
