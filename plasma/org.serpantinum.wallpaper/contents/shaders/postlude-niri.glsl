
void main() {
    vec4 c = close_color(vec3(qt_TexCoord0, 0.0), vec3(size, 1.0));
    fragColor = (c + (1.0 - c.a) * texture(to, qt_TexCoord0)) * qt_Opacity;
}
