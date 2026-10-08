#version 440
// gl-transitions interface: a body defines vec4 transition(vec2 uv), uv y-up as upstream expects.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float ratio;
};
layout(binding = 1) uniform sampler2D from;
layout(binding = 2) uniform sampler2D to;

vec4 getFromColor(vec2 uv) { return texture(from, vec2(uv.x, 1.0 - uv.y)); }
vec4 getToColor(vec2 uv) { return texture(to, vec2(uv.x, 1.0 - uv.y)); }
