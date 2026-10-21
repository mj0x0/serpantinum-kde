import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick

Item {
    id: st
    required property var host
    property int from: 0
    property int to: 99
    property int value: 0
    signal committed(int v)
    implicitWidth: st.host.s(120)
    implicitHeight: st.host.s(32)
    onValueChanged: num.value = st.value

    V2.NumberSelector {
        id: num
        anchors.fill: parent
        from: st.from
        to: st.to
        stepSize: 1
        decimals: 0
        value: st.value
        enabled: st.enabled
        baseColor: st.host.surface0
        accentColor: st.host.accent
        buttonColor: st.host.surface1
        buttonTextColor: st.host.text
        textColor: st.host.text
        subTextColor: st.host.subtext0
        borderColor: Qt.alpha(st.host.surface2, 0.6)
        cornerRadius: Radius.outer(st.host.s(8))
        fontFamily: st.host.fontFamily
        fontPixelSize: st.host.s(11)
        onTriggered: { var v = Math.round(num.value); if (v !== st.value) st.committed(v); }
    }
}
