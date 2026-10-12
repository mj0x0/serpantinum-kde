#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float headAngle;
    float tailAngle;
    vec4 indicatorColor;
    vec4 params;
};

const float PI = 3.141592653589793;

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 center = itemSize * 0.5;
    vec2 d = p - center;
    float distToCenter = length(d);

    float size = min(itemSize.x, itemSize.y);
    float dotRadius = params.x > 0.0 ? params.x : (size * 0.085) * 0.5;
    float r = params.y > 0.0 ? params.y : (size * 0.5) - (itemSize.y * 0.075 + dotRadius);

    if (r <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float a0 = (tailAngle - 90.0) * PI / 180.0;
    float a1 = (headAngle - 90.0) * PI / 180.0;

    // Head behind tail (a stale uniform) is a dot, never a full turn.
    float sweep = mod(a1 - a0 + PI, 2.0 * PI) - PI;
    if (sweep < 0.0) sweep = 0.0;

    vec2 cap0 = center + r * vec2(cos(a0), sin(a0));

    if (sweep < 0.001) {
        float dist = length(p - cap0) - dotRadius;
        float alpha = clamp(0.5 - dist, 0.0, 1.0) * indicatorColor.a * qt_Opacity;
        fragColor = vec4(indicatorColor.rgb * alpha, alpha);
        return;
    }

    vec2 cap1 = center + r * vec2(cos(a0 + sweep), sin(a0 + sweep));

    float angle = atan(d.y, d.x);
    float relAngle = mod(angle - a0, 2.0 * PI);

    float distToArc;
    if (relAngle <= sweep) {
        distToArc = abs(distToCenter - r) - dotRadius;
    } else {
        float dCap0 = length(p - cap0) - dotRadius;
        float dCap1 = length(p - cap1) - dotRadius;
        distToArc = min(dCap0, dCap1);
    }

    float alpha = clamp(0.5 - distToArc, 0.0, 1.0) * indicatorColor.a * qt_Opacity;
    fragColor = vec4(indicatorColor.rgb * alpha, alpha);
}
