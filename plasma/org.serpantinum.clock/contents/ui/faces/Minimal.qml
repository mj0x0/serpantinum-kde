import QtQuick
import QtQuick.Effects

Item {
    id: root
    clip: true

    required property QtObject dateTime
    required property QtObject theme
    property bool smoothHands: false

    readonly property real minWidth: 80
    readonly property real minHeight: 40

    Text {
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.05
        text: root.dateTime.time
        font.family: root.theme.fontFamily
        font.pixelSize: height
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.weight: Font.Black
        color: root.theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowVerticalOffset: 1.5
            shadowHorizontalOffset: 0
            shadowBlur: 0.35
            shadowOpacity: 0.55
        }
    }
}
