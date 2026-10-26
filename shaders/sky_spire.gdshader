// Floor sky for the Spire: painterly gradient, sun disc and halo, stars and
// a moon after dusk, and the underside of the floor above (the "lid": every
// floor of the Spire is roofed by the base of the next one, which is open to
// the sky only beyond the rim). DayNight drives the colours, `night` and
// `energy`; `lid` 0 hides the floor above (title screens, other floors).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.24, 0.55, 0.88);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.85, 0.72);
uniform vec3 ground_color : source_color = vec3(0.62, 0.7, 0.85);
uniform float energy = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_dir = vec3(-0.35, 0.55, -0.75);
uniform float lid : hint_range(0.0, 1.0) = 1.0;
// Elevation (sin of the angle) where the floor above begins; its edge is
// ragged with rock and hanging structures.
uniform float lid_start = 0.42;
uniform vec3 lid_color : source_color = vec3(0.47, 0.44, 0.45);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// One star per cell of a 3D grid around the eye; returns its brightness.
float stars(vec3 d, float scale, float t) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h < 0.965) {
		return 0.0;
	}
	vec3 jitter = vec3(hash13(c + 7.1), hash13(c + 13.7), hash13(c + 29.3));
	vec3 sd = normalize(c + 0.2 + 0.6 * jitter);
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0)) * scale;
	float size = mix(0.035, 0.11, pow(hash13(c + 3.3), 4.0));
	float twinkle = 0.75 + 0.25 * sin(t * (1.5 + 3.0 * jitter.x) + jitter.y * 40.0);
	return smoothstep(size, 0.0, ang) * twinkle * (h - 0.965) / 0.035;
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, pow(y, 0.8)));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -y));
	}
	col *= energy;

	// Sun: disc and two-lobe halo from the first directional light.
	if (LIGHT0_ENABLED) {
		float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		vec3 sc = LIGHT0_COLOR * LIGHT0_ENERGY;
		col += sc * (smoothstep(0.9993, 0.9996, sd) * 6.0 + pow(sd, 90.0) * 0.6 + pow(sd, 8.0) * 0.12);
	}

	if (!AT_CUBEMAP_PASS && night > 0.01 && y > -0.05) {
		float s = stars(d, 160.0, TIME) + 0.6 * stars(d, 320.0, TIME);
		float hor_fade = smoothstep(-0.02, 0.25, y);
		col += vec3(0.85, 0.9, 1.0) * s * night * hor_fade * 1.6;
		// Faint milky band across the sky.
		float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.2, 1.0))) * 3.2, 2.0));
		col += vec3(0.22, 0.24, 0.4) * band * fbm(d.xz * 6.0 + d.y * 3.0) * night * hor_fade * 0.6;
	}

	// Moon: pale disc with soft maria, plus a cold halo.
	if (night > 0.01) {
		vec3 md = normalize(moon_dir);
		float mdot = dot(d, md);
		float disc = smoothstep(0.99935, 0.9996, mdot);
		vec3 tangent = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec2 mp = vec2(dot(d - md, tangent), dot(d - md, cross(tangent, md))) * 60.0;
		float maria = 0.82 + 0.18 * fbm(mp * 3.0);
		col = mix(col, vec3(0.92, 0.95, 1.0) * maria * 1.6, disc * night);
		col += vec3(0.35, 0.45, 0.7) * pow(max(mdot, 0.0), 220.0) * night * 0.8;
		col += vec3(0.15, 0.2, 0.35) * pow(max(mdot, 0.0), 12.0) * night * 0.25;
	}

	// The floor above: a vast rock-and-stone plate with a ragged rim. Seen
	// from below, so it is lit by the land (horizon colour) and darkest at
	// the zenith; at night a few lamps of the town above twinkle on it.
	if (lid > 0.001 && y > 0.0) {
		float az = atan(d.z, d.x);
		// A broad, slow wobble in the rim and a few blunt crags: it should read
		// as one solid stone plate, not drips.
		float rag = (fbm(vec2(az * 2.0, 0.0)) - 0.5) * 0.07 + (vnoise(vec2(az * 11.0, 3.0)) - 0.5) * 0.018;
		float teeth = smoothstep(0.72, 0.95, vnoise(vec2(az * 19.0, 7.0))) * 0.03;
		float edge = lid_start + rag - teeth;
		float m = smoothstep(edge - 0.004, edge + 0.004, y);
		if (m > 0.0) {
			vec2 p = d.xz / max(y, 0.05);
			float rock = fbm(p * 1.6);
			// Concentric strata of the plate's underside, read in perspective.
			float rr = length(p);
			float strata = smoothstep(0.35, 0.5, abs(fract(rr * 0.9 + fbm(p * 0.5) * 0.8) - 0.5));
			float zen = smoothstep(edge, 1.0, y);
			vec3 under = lid_color * (0.55 + 0.6 * rock) * (1.0 - 0.22 * strata);
			// Bounce light from the land below, warm by day, cold by night;
			// darkest toward the zenith, the middle of the plate.
			under *= mix(horizon_color, vec3(0.85, 0.88, 0.95), 0.55) * (1.0 - 0.45 * zen);
			// Aerial perspective: lighter near the rim (farther off), firm overhead.
			float haze = 0.18 + 0.32 * (1.0 - smoothstep(edge, edge + 0.22, y));
			under = mix(under, mix(horizon_color, top_color, 0.6), haze);
			// Daylight catches the rim from outside: a thin bright lip.
			float lip = smoothstep(edge + 0.012, edge, y) * m;
			under = mix(under, horizon_color * 1.15, lip * 0.55 * (1.0 - night));
			if (!AT_CUBEMAP_PASS) {
				vec2 cell = floor(p * 9.0);
				float lamp = step(0.992, hash12(cell)) * smoothstep(0.35, 0.0, length(fract(p * 9.0) - 0.5));
				under += vec3(1.0, 0.75, 0.4) * lamp * night * 1.2;
			}
			col = mix(col, under * energy, m * lid);
		}
	}

	COLOR = col;
}
