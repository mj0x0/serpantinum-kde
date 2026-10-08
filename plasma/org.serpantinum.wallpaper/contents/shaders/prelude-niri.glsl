#version 440
// Niri window-shader interface (liixini/shaders): a body defines premultiplied
// vec4 close_color(vec3 coords_geo, vec3 size_geo) over top-left geometry coords; it runs on the outgoing wallpaper.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float ratio;
    float seed;
    vec2 size;
};
layout(binding = 1) uniform sampler2D from;
layout(binding = 2) uniform sampler2D to;

#define texture2D texture
#define niri_tex from
#define niri_random_seed seed
// Niri feeds an eased progress; its configs for these effects use ease-out-cubic.
float niri_ease(float t) { float f = t - 1.0; return f * f * f + 1.0; }
#define niri_clamped_progress clamp(niri_ease(progress), 0.0, 1.0)
const mat3 niri_geo_to_tex = mat3(1.0);
