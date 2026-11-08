import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var host
    default property alias content: body.data
    spacing: 0

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: body.implicitHeight
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: parent.width
            spacing: page.host.s(6)
        }
    }
}
