
            // Ported from skwd-wall polar-function transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;
                vec3 tc = niri_geo_to_tex * vec3(uv, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                int segments = 5;
                float angle = atan(uv.y - 0.5, uv.x - 0.5);
                float radius = (cos(float(segments) * angle) + 4.0) / 4.0;
                float difference = length(uv - vec2(0.5, 0.5));
                float reveal = step(difference, radius * p);

                return win * reveal;
            }
