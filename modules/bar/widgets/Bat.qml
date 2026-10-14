// Battery: classic (gradient wave fill), minimal (capsule with a cap) and text.
// serpantinum v2's BatFace and SideBatFace, merged into one orientation-aware widget.
import "../../../services/audio"
import "../../../services/reusables"
import "../../../services/settings"
import "../../../services/theme"
import "../../notifcenter"
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Rectangle {
    id: bat
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0

    readonly property string style: barWindow.batStyle
    readonly property bool isText: style === "text"
    readonly property bool isMinimal: style === "minimal"
    readonly property bool showPercent: !isDesktop && ShellSettings.value("bar.batShowPercent", true) !== false
    readonly property bool showIcon: ShellSettings.value("bar.batShowIcon", true) !== false

    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : true
    readonly property int batCap: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property string batPercent: batCap + "%"
    readonly property bool isCharging: UPower.displayDevice.ready
        && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property bool isActivelyCharging: isCharging && UPower.displayDevice.changeRate > 0.5
    readonly property string batIcon: isDesktop ? "\u{f0425}"
                                                : (isCharging ? "\u{f0084}" : (batCap > 20 ? "\u{f0079}" : "\u{f0083}"))
    readonly property string pillIcon: (!isDesktop && isMinimal && isCharging) ? "\u{f140b}" : batIcon

    readonly property color dynamicColor: {
        if (isDesktop) return mocha.red;
        if (isCharging) return Qt.lighter(mocha.green, 1.15);
        if (batCap <= 15) return mocha.red;
        if (batCap <= 25) return mocha.peach;
        return mocha.teal;
    }
    readonly property color calmFill: {
        if (isDesktop) return mocha.subtext0;
        if (isCharging) return mocha.green;
        if (batCap <= 15) return mocha.red;
        if (batCap <= 25) return mocha.peach;
        return mocha.teal;
    }

    // The wave only turns while charge is actually moving, so an idle bar animates nothing.
    property real wavePhase: 0.8
    Timer {
        id: waveSettle
        interval: bat.isCharging ? 30000 : 1800
        onTriggered: if (!bat.isActivelyCharging) waveAnim.stop()
    }
    NumberAnimation {
        id: waveAnim
        target: bat
        property: "wavePhase"
        from: 0
        to: Math.PI * 2
        duration: bat.isCharging ? 1200 : 2200
        loops: Animation.Infinite
        running: bat.visible && !bat.isDesktop && !bat.isText && bat.isActivelyCharging
                 && pill.fillRatio > 0.0 && pill.fillRatio < 1.0
    }
    onIsChargingChanged: waveSettle.restart()

    readonly property real pillAlong: vertical ? barWindow.s(isDesktop ? 30 : 40) : pill.targetAlong
    readonly property real pillAcross: vertical ? barWindow.s(isDesktop ? 30 : 28) : barWindow.s(30)
    readonly property real capSize: (!isDesktop && isMinimal) ? barWindow.s(5) : 0

    readonly property real contentAlong: isText ? (vertical ? textCol.implicitHeight : textRow.implicitWidth)
                                                : pillAlong + capSize
    readonly property real targetWidth: (placed && !vertical) ? contentAlong + barWindow.s(isText ? 20 : 10) : 0
    readonly property real targetHeight: (placed && vertical) ? contentAlong + barWindow.s(isText ? 20 : 10) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !bat.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && bat.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    visible: placed && (vertical ? height : width) > 0
    clip: true

    color: (grouped || isText) ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius
    border.width: (grouped || isText) ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05 * barWindow.pillBorderAlpha)

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady && barWindow.isDataReady; interval: 100; onTriggered: bat.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    // --- text style: icon and percent, no chrome ---
    Row {
        id: textRow
        visible: bat.isText && !bat.vertical
        anchors.centerIn: parent
        spacing: bat.isDesktop ? 0 : barWindow.s(6)
        Text {
            visible: bat.showIcon
            text: bat.batIcon
            font.family: "Iosevka Nerd Font"
            font.pixelSize: barWindow.s(bat.isDesktop ? 16 : 14.5)
            color: batMouse.containsMouse ? Qt.lighter(bat.dynamicColor, 1.15) : bat.dynamicColor
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Text {
            visible: bat.showPercent
            text: bat.batPercent
            font.family: Fonts.ui
            font.pixelSize: barWindow.s(12.6)
            font.bold: true
            color: batMouse.containsMouse ? Qt.lighter(mocha.text, 1.15) : mocha.text
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
    Column {
        id: textCol
        visible: bat.isText && bat.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(3)
        Text {
            visible: bat.showIcon
            text: bat.batIcon
            font.family: "Iosevka Nerd Font"
            font.pixelSize: barWindow.s(bat.isDesktop ? 16 : 14.5)
            color: batMouse.containsMouse ? Qt.lighter(bat.dynamicColor, 1.15) : bat.dynamicColor
            anchors.horizontalCenter: parent.horizontalCenter
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Text {
            visible: bat.showPercent
            text: "" + bat.batCap
            font.family: Fonts.ui
            font.pixelSize: barWindow.s(11)
            font.bold: true
            color: mocha.text
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // --- classic and minimal: a filled capsule, plus a cap nub for minimal ---
    Grid {
        id: capsule
        visible: !bat.isText
        anchors.centerIn: parent
        columns: bat.vertical ? 1 : 2
        spacing: 0

        // The cap leads in the vertical layout and trails in the horizontal one.
        Loader { active: bat.vertical; visible: active; sourceComponent: capBox }

        Rectangle {
            id: pill
            property real animValue: bat.isDesktop ? 0.0 : (UPower.displayDevice.ready ? UPower.displayDevice.percentage : 0.0)
            Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
            readonly property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
            readonly property real maxWaveAmp: bat.isCharging ? barWindow.s(4.5) : barWindow.s(2.5)
            readonly property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? maxWaveAmp * Math.sin(fillRatio * Math.PI) : 0

            readonly property color accentColor: batMouse.pressed ? Qt.darker(bat.dynamicColor, 1.15)
                                               : (batMouse.containsMouse ? Qt.lighter(bat.dynamicColor, 1.08) : bat.dynamicColor)

            readonly property real targetAlong: bat.isDesktop
                ? barWindow.s(32)
                : Math.max(iconMetrics.implicitWidth + barWindow.s(6) + percentMetrics.implicitWidth + barWindow.s(18),
                           barWindow.s(32))

            width: bat.vertical ? bat.pillAcross : bat.pillAlong
            height: bat.vertical ? bat.pillAlong : bat.pillAcross
            Behavior on width { enabled: !bat.vertical; NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }
            radius: barWindow.innerRadius
            color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.6)
            border.width: 1
            border.color: batMouse.containsMouse ? mocha.surface2 : mocha.surface1
            Behavior on border.color { ColorAnimation { duration: 150 } }
            clip: true

            Text {
                id: iconMetrics
                visible: false
                text: bat.pillIcon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: barWindow.s(bat.isDesktop ? 16 : 13.5)
            }
            Text {
                id: percentMetrics
                visible: false
                text: bat.showPercent ? bat.batPercent : ""
                font.family: Fonts.ui
                font.pixelSize: barWindow.s(12.6)
                font.bold: true
            }

            FluidWave {
                anchors.fill: parent
                visible: !bat.isDesktop && pill.fillRatio > 0.001
                radius: pill.radius
                fillLevel: pill.fillRatio
                waveAmp: {
                    if (pill.fillRatio >= 0.99 || pill.waveAmp <= 0) return 0;
                    const span = bat.vertical ? pill.height : pill.width;
                    return Math.min(pill.waveAmp, Math.min(span * pill.fillRatio, span * (1.0 - pill.fillRatio)));
                }
                phase: bat.wavePhase
                vertical: bat.vertical ? 1.0 : 0.0
                color1: bat.isMinimal ? bat.calmFill : Qt.lighter(pill.accentColor, 1.20)
                color2: bat.isMinimal ? bat.calmFill : pill.accentColor
            }

            Grid {
                id: pillContent
                anchors.centerIn: parent
                columns: bat.vertical ? 1 : 2
                spacing: (bat.isDesktop || bat.vertical) ? 0 : barWindow.s(6)
                Text {
                    visible: bat.showIcon
                    text: bat.pillIcon
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: barWindow.s(bat.isDesktop ? 16 : 13.5)
                    color: bat.isDesktop ? mocha.red : mocha.subtext0
                }
                Text {
                    visible: bat.showPercent && !bat.vertical
                    text: bat.batPercent
                    font.family: Fonts.ui
                    font.pixelSize: barWindow.s(12.6)
                    font.bold: true
                    color: mocha.text
                }
            }

            // The filled part re-inks the label dark, clipped to the liquid.
            Item {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: bat.vertical ? parent.width : Math.min(parent.width, Math.max(0, parent.width * pill.fillRatio))
                height: bat.vertical ? Math.min(parent.height, Math.max(0, parent.height * pill.fillRatio)) : parent.height
                clip: true
                visible: !bat.isDesktop && pill.fillRatio > 0
                Item {
                    width: pill.width
                    height: pill.height
                    y: bat.vertical ? -(pill.height - parent.height) : 0
                    Grid {
                        x: pillContent.x
                        y: pillContent.y
                        columns: pillContent.columns
                        spacing: pillContent.spacing
                        Text {
                            visible: bat.showIcon
                            text: bat.pillIcon
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: barWindow.s(bat.isDesktop ? 16 : 13.5)
                            color: Qt.rgba(mocha.crust.r, mocha.crust.g, mocha.crust.b, 0.85)
                        }
                        Text {
                            visible: bat.showPercent && !bat.vertical
                            text: bat.batPercent
                            font.family: Fonts.ui
                            font.pixelSize: barWindow.s(12.6)
                            font.bold: true
                            color: mocha.crust
                        }
                    }
                }
            }
        }

        Loader { active: !bat.vertical; visible: active; sourceComponent: capBox }
    }

    Component {
        id: capBox
        Item {
            visible: !bat.isDesktop && bat.isMinimal
            width: bat.vertical ? bat.pillAcross : bat.capSize
            height: bat.vertical ? bat.capSize : bat.pillAcross
            Rectangle {
                anchors.centerIn: parent
                width: bat.vertical ? Math.round(bat.pillAcross * 0.38) : barWindow.s(4)
                height: bat.vertical ? barWindow.s(3) : Math.round(bat.pillAcross * 0.38)
                radius: barWindow.s(1.5)
                color: pill.border.color
            }
        }
    }

    MouseArea {
        id: batMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { Sounds.playSfx("system/quick_click.wav"); NotifCenterState.toggle(); }
    }
}
