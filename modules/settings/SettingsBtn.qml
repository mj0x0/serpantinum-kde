import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick

V2.ClickButton {
    id: btn
    required property var host

    property string label: ""
    buttonText: label
    buttonIcon: ""
    implicitHeight: btn.host.s(30)
    horizontalPadding: btn.host.s(14)
    cornerRadius: Radius.outer(btn.host.s(8))
    textFontSize: btn.host.s(11)
    accentColor: btn.host.surface1
    textColor: btn.host.text
}
