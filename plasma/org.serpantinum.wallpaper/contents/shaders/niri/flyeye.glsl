
            // Ported from skwd-wall flyeye transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;

                float sz = 0.04;
                float zoom = 50.0;
                float inv = 1.0 - p;
                vec2 disp = sz * vec2(cos(zoom * uv.x), sin(zoom * uv.y));
                vec2 sample_uv = uv + inv * disp;

                vec3 tc = niri_geo_to_tex * vec3(sample_uv, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                return win * p;
            }
