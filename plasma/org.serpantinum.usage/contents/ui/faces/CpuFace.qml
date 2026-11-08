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

    property real rawCpu: isNaN(root.sysData.cpu) ? 0.0 : root.sysData.cpu / 100.0
    property real cpuUsage: rawCpu
    Behavior on cpuUsage { enabled: root.visible && root.animate; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    SystemUsageCard {
        anchors.fill: parent
        theme: root.theme
        value: root.cpuUsage
        colorBase: root.theme.surface0
        colorFill: Qt.lighter(root.theme.mauve, 1.35)
        icon: "\uF2DB"
        title: i18n("CPU")
        valueText: Math.round(root.cpuUsage * 100) + "%"
        wavePhase: root.wavePhase
        isLive: root.visible
        compact: root.compactMode
    }
}
