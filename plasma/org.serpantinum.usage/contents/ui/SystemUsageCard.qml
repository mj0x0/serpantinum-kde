import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property QtObject theme

    property real value: 0.0
    property color colorBase: root.theme.surface0
    property color colorFill: root.theme.mauve
    property string icon: ""
    property string title: ""
    property string midText: ""
    property string valueText: ""
    property string subText: ""
    property alias bottomLeftText: root.subText

    property real wavePhase: 0.0
    property bool isLive: true
    property bool hasShadow: false
    property color shadowColor: Qt.rgba(0, 0, 0, 0.22)

    property bool compact: false

    function s(val) {
        return val;
    }

    property real cardRadius: compact ? s(Math.max(0, root.theme.clampedBorderRadius - 2)) : s(root.theme.clampedBorderRadius)
    property real contentMargins: compact ? s(10) : s(12)
    property real waveAmpMax: compact ? s(4) : s(5)

    property real iconSize: compact ? s(26) : s(28)
    property real iconCornerRadius: Math.min(iconSize / 2, s(root.theme.borderRadius))
    property real iconFontSize: compact ? s(14) : s(16)
    property real midTextFontSize: compact ? s(10.5) : s(13)
    property real titleFontSize: compact ? s(10.5) : s(13)
    property real subTextFontSize: compact ? s(11) : s(15)
    property real valueFontSize: compact ? s(18) : s(24)

    property string fontFamily: root.theme.fontFamily
    property color borderColor: Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.06)
    property color iconAccentColor: Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.6)
    property color iconTextColor: root.theme.subtext0
    property color midTextColor: Qt.rgba(root.theme.subtext0.r, root.theme.subtext0.g, root.theme.subtext0.b, 0.7)
    property color titleColor: root.theme.subtext0
    property color subTextColor: root.theme.subtext0
    property color valueTextColor: root.theme.text

    property color filledIconAccentColor: Qt.rgba(root.theme.crust.r, root.theme.crust.g, root.theme.crust.b, 0.15)
    property color filledTextColor: root.theme.crust
    property color filledMidTextColor: Qt.rgba(root.theme.crust.r, root.theme.crust.g, root.theme.crust.b, 0.6)
    property color filledTitleColor: Qt.rgba(root.theme.crust.r, root.theme.crust.g, root.theme.crust.b, 0.85)
    property color filledSubTextColor: root.theme.crust

    default property alias childItems: customContentBox.data

    readonly property real fillRatio: Math.max(0.0, Math.min(1.0, root.value))
    readonly property real fillY: height * (1.0 - root.fillRatio)
    readonly property real waveAmp: (root.fillRatio < 0.99 && root.fillRatio > 0.01) ? root.waveAmpMax * Math.sin(root.fillRatio * Math.PI) : 0
    readonly property real waveCenterOffset: root.waveAmp > 0 ? 0.375 * root.waveAmp * (Math.sin(root.wavePhase) - Math.cos(root.wavePhase)) : 0



    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.s(2)
        anchors.bottomMargin: -root.s(2)
        radius: root.cardRadius
        color: root.shadowColor
        visible: root.hasShadow
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: root.colorBase
        border.width: 1
        border.color: root.borderColor
    }

    FluidWave {
        id: fluidWave
        anchors.fill: parent
        theme: root.theme
        radius: root.cardRadius
        fillLevel: root.fillRatio
        waveAmp: root.waveAmp
        phase: root.wavePhase
        vertical: 1.0
        color1: Qt.lighter(root.colorFill, 1.18)
        color2: root.colorFill
        params: Qt.vector4d(0.94, 0.0, 0.0, 0.0)
        visible: root.fillRatio > 0.001
    }

    Item {
        anchors.fill: parent
        anchors.margins: root.contentMargins

        IconButton {
            id: baseCardIcon
            anchors.top: parent.top
            anchors.left: parent.left
            theme: root.theme
            size: Math.round(root.iconSize)
            cornerRadius: Math.round(root.iconCornerRadius)
            accentColor: root.iconAccentColor
            textColor: root.iconTextColor
            buttonIcon: root.icon
            iconFontSize: Math.round(root.iconFontSize)
            enabled: false
        }

        Row {
            anchors.verticalCenter: baseCardIcon.verticalCenter
            anchors.right: parent.right
            spacing: root.s(4)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: root.midTextFontSize
                color: root.midTextColor
                text: root.midText
                visible: root.midText !== ""
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: root.titleFontSize
                color: root.titleColor
                text: root.title
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: root.s(1)
            font.family: root.fontFamily
            font.weight: Font.DemiBold
            font.pixelSize: root.subTextFontSize
            color: root.subTextColor
            text: root.subText
            visible: root.subText !== ""
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            font.family: root.fontFamily
            font.weight: Font.Black
            font.pixelSize: root.valueFontSize
            color: root.valueTextColor
            text: root.valueText
        }
    }

    Item {
        id: waveClipBox
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(parent.height, Math.max(0, (parent.height * root.fillRatio) - root.waveCenterOffset))
        clip: true
        visible: root.value > 0

        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.height
            anchors.margins: root.contentMargins

            IconButton {
                id: filledCardIcon
                anchors.top: parent.top
                anchors.left: parent.left
                theme: root.theme
                size: Math.round(root.iconSize)
                cornerRadius: Math.round(root.iconCornerRadius)
                accentColor: root.filledIconAccentColor
                textColor: root.filledTextColor
                buttonIcon: root.icon
                iconFontSize: Math.round(root.iconFontSize)
                enabled: false
            }

            Row {
                anchors.verticalCenter: filledCardIcon.verticalCenter
                anchors.right: parent.right
                spacing: root.s(4)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: root.midTextFontSize
                    color: root.filledMidTextColor
                    text: root.midText
                    visible: root.midText !== ""
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: root.titleFontSize
                    color: root.filledTitleColor
                    text: root.title
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.bottomMargin: root.s(1)
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: root.subTextFontSize
                color: root.filledSubTextColor
                text: root.subText
                visible: root.subText !== ""
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                font.family: root.fontFamily
                font.weight: Font.Black
                font.pixelSize: root.valueFontSize
                color: root.filledTextColor
                text: root.valueText
            }
        }
    }

    Item {
        id: customContentBox
        anchors.fill: parent
        anchors.margins: root.contentMargins
        z: 10
    }
}
