
            // Ported from skwd-wall pixelfade-wave transition

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;

                float wave_x = (uv.x + uv.y) * 0.5;
                float wave_p = smoothstep(0.0, 1.0, p * 1.6 - wave_x * 0.6);
                float bump = sin(wave_p * 3.14159);
                float blocks = mix(800.0, 8.0, bump);
                vec2 q = floor(uv * blocks) / blocks + 0.5 / blocks;

                vec3 tc = niri_geo_to_tex * vec3(q, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                float reveal = smoothstep(0.0, 1.0, wave_p);
                return win * reveal;
            }
