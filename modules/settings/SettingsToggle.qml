import "../../services/reusables" as V2
import QtQuick

Item {
    id: tg
    required property var host
    property bool checked: false
    signal toggled(bool value)
    implicitWidth: tgInner.implicitWidth
    implicitHeight: tgInner.implicitHeight
    // v2's Toggle flips its own `checked` on click, which would sever the binding above.
    onCheckedChanged: tgInner.checked = tg.checked

    V2.Toggle {
        id: tgInner
        checked: tg.checked
        accentColor: tg.host.accent
        baseColor: tg.host.surface1
        handleColor: tg.host.crust
        handleOffColor: tg.host.text
        onToggled: c => tg.toggled(c)
    }
}
