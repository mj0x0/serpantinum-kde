
            // Ported from skwd-wall inkwell-drop transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;

                vec2 impact = vec2(0.35, 0.4);
                vec2 c = uv - impact;
                c.x *= size_geo.x / max(size_geo.y, 0.0001);
                float d = length(c);
                float front = p * 1.5;
                float ring1 = sin((d - front) * 80.0) * exp(-abs(d - front) * 6.0);
                float ring2 = sin((d - front + 0.08) * 80.0) * exp(-abs(d - front + 0.08) * 8.0) * 0.6;
                float ring3 = sin((d - front + 0.16) * 80.0) * exp(-abs(d - front + 0.16) * 10.0) * 0.4;
                float ripple = (ring1 + ring2 + ring3) * 0.05 * (1.0 - p * 0.5);
                vec2 dir = (d > 0.001) ? normalize(c) : vec2(0.0);
                vec2 distorted = clamp(uv + dir * ripple, vec2(0.0), vec2(1.0));

                vec3 tc = niri_geo_to_tex * vec3(distorted, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                float reveal = smoothstep(0.05, -0.02, d - front);
                vec4 mixed = win * reveal;

                float in_bounds = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
                return mixed * in_bounds;
            }
