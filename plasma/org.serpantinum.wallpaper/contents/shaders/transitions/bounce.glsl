// The incoming wallpaper drops in from the top on an ease-out-bounce curve, pushing the old one down.
float bounceOut(float t) {
    const float n1 = 7.5625;
    const float d1 = 2.75;
    if (t < 1.0 / d1) return n1 * t * t;
    if (t < 2.0 / d1) { t -= 1.5 / d1; return n1 * t * t + 0.75; }
    if (t < 2.5 / d1) { t -= 2.25 / d1; return n1 * t * t + 0.9375; }
    t -= 2.625 / d1;
    return n1 * t * t + 0.984375;
}

vec4 transition(vec2 uv) {
    float b = bounceOut(progress);
    float edge = 1.0 - b;
    if (uv.y >= edge)
        return getToColor(vec2(uv.x, uv.y - edge));
    float shade = 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.08, edge - uv.y));
    return getFromColor(vec2(uv.x, uv.y + b)) * vec4(vec3(shade), 1.0);
}
