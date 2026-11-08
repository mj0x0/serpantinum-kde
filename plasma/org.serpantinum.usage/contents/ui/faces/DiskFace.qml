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

    property real rawDisk: isNaN(root.sysData.diskPercent) ? 0.0 : root.sysData.diskPercent / 100.0
    property real diskUsagePercent: rawDisk
    Behavior on diskUsagePercent { enabled: root.visible && root.animate; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    property string diskUsedText: root.sysData.diskGb > 0 ? (root.sysData.diskGb.toFixed(1) + "G") : "..."
    property string diskTotalText: root.sysData.diskTotalGb > 0 ? (root.sysData.diskTotalGb.toFixed(1) + "G") : ""

    SystemUsageCard {
        anchors.fill: parent
        theme: root.theme
        value: root.diskUsagePercent
        colorBase: root.theme.surface0
        colorFill: Qt.darker(root.theme.mauve, 1.15)
        icon: "\uF0A0"
        title: root.diskTotalText
        subText: root.diskUsedText
        valueText: Math.round(root.diskUsagePercent * 100) + "%"
        wavePhase: root.wavePhase
        isLive: root.visible
        compact: root.compactMode
    }
}
