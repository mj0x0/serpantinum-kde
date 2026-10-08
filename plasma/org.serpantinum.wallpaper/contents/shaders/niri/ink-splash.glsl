
            // Ported from skwd-wall ink-splash transition

            float is_hash(vec2 p) {
                return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
            }

            float is_noise(vec2 p) {
                vec2 i = floor(p);
                vec2 f = fract(p);
                f = f * f * (3.0 - 2.0 * f);
                return mix(mix(is_hash(i), is_hash(i + vec2(1.0, 0.0)), f.x),
                           mix(is_hash(i + vec2(0.0, 1.0)), is_hash(i + vec2(1.0, 1.0)), f.x), f.y);
            }

            float is_fbm(vec2 p) {
                float v = 0.0;
                float amp = 0.5;
                for (int i = 0; i < 4; i++) {
                    v += amp * is_noise(p);
                    p *= 2.1;
                    amp *= 0.5;
                }
                return v;
            }

            vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                float p = 1.0 - niri_clamped_progress;
                vec2 uv = coords_geo.xy;
                vec3 tc = niri_geo_to_tex * vec3(uv, 1.0);
                vec4 win = texture2D(niri_tex, tc.st);

                float blob = is_fbm(uv * 3.5);
                float fingers = is_fbm(uv * 14.0);
                float distortion = (blob - 0.5) * 0.5 + (fingers - 0.5) * 0.18;
                vec2 c = uv - vec2(0.5);
                c.x *= size_geo.x / max(size_geo.y, 0.0001);
                float d = length(c);
                float splash_d = d + distortion;
                float boundary = p * 1.7 - 0.15;
                float diff = splash_d - boundary;
                float reveal = smoothstep(0.04, -0.04, diff);

                return win * reveal;
            }
