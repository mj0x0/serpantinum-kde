
void main() {
    fragColor = transition(vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y)) * qt_Opacity;
}
