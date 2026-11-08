// Masked, and clears itself on commit so a typed key never lingers on screen.
import QtQuick

Item {
    id: sf
    required property var host
    property string placeholder: ""
    signal committed(string v)
    implicitWidth: sf.host.s(200)
    implicitHeight: sf.host.s(32)
    SettingsPathField {
        host: sf.host
        anchors.fill: parent
        secret: true
        placeholder: sf.placeholder
        onCommitted: v => sf.committed(v)
    }
}
