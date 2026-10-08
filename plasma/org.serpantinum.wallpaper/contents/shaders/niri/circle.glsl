
            // Ported from gl-transitions/circleopen.glsl (MIT, gre)

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = niri_clamped_progress;
                vec2 uv = coords_geo.xy;
                float seed = niri_random_seed;

                float smoothness = 0.3;
                float SQRT_2 = 1.414213562;

                // Slightly randomized center
                vec2 center = vec2(0.5 + (seed - 0.5) * 0.15, 0.5 + (seed * 0.7 - 0.35) * 0.15);

                float dist = SQRT_2 * distance(center, uv);
                float m = smoothstep(-smoothness, 0.0, dist - (1.0 - p) * (1.0 + smoothness));
                float remain = 1.0 - m;

                vec3 tc = niri_geo_to_tex * vec3(uv, 1.0);
                vec4 color = texture2D(niri_tex, tc.st);

                return color * remain;
            }
