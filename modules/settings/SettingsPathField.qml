import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick

Item {
    id: pf
    required property var host
    property string value: ""
    property string placeholder: ""
    property bool secret: false
    signal committed(string v)
    implicitWidth: pf.host.s(220)
    implicitHeight: pf.host.s(32)
    onValueChanged: inp.text = pf.value

    // For a committed handler that stored something other than what was typed: `value`
    // still lags behind the settings file, so it cannot clear the field on its own.
    function reset(text) { inp.text = text }

    // Enter commits; so does leaving the field, as a pasted key must survive a click away.
    function commit() {
        var t = inp.text;
        if (pf.secret) { if (t !== "") { pf.committed(t); inp.text = ""; } }
        else if (t !== pf.value) pf.committed(t);
    }

    V2.Input {
        id: inp
        anchors.fill: parent
        text: pf.value
        placeholderText: pf.placeholder
        masked: pf.secret
        baseColor: pf.host.surface0
        accentColor: pf.host.accent
        textColor: pf.host.text
        subTextColor: pf.host.subtext0
        borderColor: Qt.alpha(pf.host.surface2, 0.6)
        cornerRadius: Radius.outer(pf.host.s(8))
        fontPixelSize: pf.host.s(11)
        onAccepted: pf.commit()
        onHasFocusChanged: if (!hasFocus) pf.commit()
    }
}
