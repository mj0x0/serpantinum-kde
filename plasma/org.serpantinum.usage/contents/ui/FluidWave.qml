import QtQuick

ShaderEffect {
    id: root

    required property QtObject theme

    property real radius: 0.0
    property real fillLevel: 0.0
    property real waveAmp: 0.0
    property vector2d itemSize: Qt.vector2d(width, height)
    property real phase: 0.0
    property real vertical: 1.0
    property color color1: root.theme.blue
    property color color2: color1
    property vector4d params: Qt.vector4d(1.0, 0.0, 0.0, 0.0)

    fragmentShader: Qt.resolvedUrl("../assets/shaders/fluid/fluid_wave.frag.qsb")
}
