
            // Ported from skwd-wall wave-warp transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;

                float smoothness = 0.5;
                vec2 dir = vec2(1.0, 0.0);
                vec2 v = normalize(dir);
                v /= abs(v.x) + abs(v.y);
                float d = v.x * 0.5 + v.y * 0.5;
                float m = 1.0 - smoothstep(-smoothness, 0.0, v.x * uv.x + v.y * uv.y - (d - 0.5 + p * (1.0 + smoothness)));

                vec2 warped = clamp((uv - 0.5) * m + 0.5, vec2(0.0), vec2(1.0));
                vec3 tc = niri_geo_to_tex * vec3(warped, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                float in_bounds = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
                return win * m * in_bounds;
            }
