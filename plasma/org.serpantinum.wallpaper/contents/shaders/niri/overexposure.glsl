
            // Ported from skwd-wall overexposure transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;
                float strength = 0.6;
                float PI = 3.141592653589793;

                vec3 tc = niri_geo_to_tex * vec3(uv, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                float to_m = p + sin(PI * p) * strength;
                vec4 mixed = vec4(
                    win.r * win.a * to_m,
                    win.g * win.a * to_m,
                    win.b * win.a * to_m,
                    win.a * p
                );

                return mixed;
            }
