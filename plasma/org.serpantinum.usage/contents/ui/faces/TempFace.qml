import QtQuick
import ".."

Item {
    id: root

    required property QtObject sysData
    required property QtObject theme
    property bool animate: false

    readonly property real minWidth: 100
    readonly property real minHeight: 70

    property bool compactMode: root.height < 100 || root.width < 140

    property real wavePhase: 0.0
    // Upstream animates the wave continuously; on NVIDIA's OpenGL path every rendered frame leaks, so the card is static by default.
    NumberAnimation on wavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
        running: root.visible && root.animate
    }

    property real rawTemp: isNaN(root.sysData.temp) ? 0.0 : root.sysData.temp
    property real tempC: rawTemp
    Behavior on tempC { enabled: root.visible && root.animate; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    SystemUsageCard {
        anchors.fill: parent
        theme: root.theme
        value: Math.max(0.0, Math.min(1.0, root.tempC / 100.0))
        colorBase: root.theme.surface0
        colorFill: root.theme.mauve
        icon: "\uF2C9"
        title: i18n("Temp")
        valueText: Math.round(root.tempC) + "°"
        wavePhase: root.wavePhase
        isLive: root.visible
        compact: root.compactMode
    }
}
