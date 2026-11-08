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

    property real rawRam: isNaN(root.sysData.ramPercent) ? 0.0 : root.sysData.ramPercent / 100.0
    property real ramUsage: rawRam
    Behavior on ramUsage { enabled: root.visible && root.animate; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    property real rawRamGb: isNaN(root.sysData.ramGb) ? 0.0 : root.sysData.ramGb
    property real ramUsedGb: rawRamGb
    Behavior on ramUsedGb { enabled: root.visible && root.animate; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    SystemUsageCard {
        anchors.fill: parent
        theme: root.theme
        value: root.ramUsage
        colorBase: root.theme.surface0
        colorFill: Qt.lighter(root.theme.mauve, 1.15)
        icon: "\uF538"
        title: i18n("RAM")
        valueText: root.ramUsedGb.toFixed(1) + "G"
        wavePhase: root.wavePhase
        isLive: root.visible
        compact: root.compactMode
    }
}
