// Cel-shaded ancient stonework for the Labyrinth tower, cliffs and walls.
// World-space triplanar detail (Poly Haven brick / rock maps) modulates a
// painted two-tone palette; optional brick courses, pulsing rune bands and a
// height fade into the clouds. Instance COLOR tints (MultiMesh variation).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(0.6, 0.58, 0.68, 1.0);
uniform vec4 albedo_b : source_color = vec4(0.5, 0.48, 0.6, 1.0);
uniform float shadow_level : hint_range(0.0, 1.0) = 0.5;
uniform float mid_level : hint_range(0.0, 1.0) = 0.78;

// Detail map: world-space triplanar, repeats per metre. Default white = off.
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_tiling = 0.2;
uniform float detail_mean = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform float detail_tint : hint_range(0.0, 1.0) = 0.2;

// Brick courses: band_period metres per course (0 = off), mortar lines
// darkened by band_dark. Joints run along the tangent, or around `center`
// (polar) for round towers.
uniform float band_period = 0.0;
uniform float band_width = 0.1;
uniform float band_dark : hint_range(0.0, 1.0) = 0.72;
uniform float brick_length = 2.4;
uniform float polar = 0.0;
uniform vec2 center = vec2(0.0);
uniform float polar_radius = 12.0;

// Flagstones on up-facing surfaces: floor_period metres per stone (0 = off).
// Staggered rows, or rings of stones around `center` when polar is set.
uniform float floor_period = 0.0;

// Planks (0 = off): boards plank_period wide and brick_length long, with
// staggered ends and a per-board shade. Floors and ceilings lay the boards
// along world x (plank_axis 0) or z (1); walls get vertical boards.
uniform float plank_period = 0.0;
uniform float plank_axis = 0.0;

// Up to three glowing rune bands at these world heights.
uniform vec3 rune_heights = vec3(-10000.0);
uniform float rune_width = 1.0;
uniform vec4 rune_color : source_color = vec4(0.55, 0.4, 1.0, 1.0);
uniform float rune_strength = 0.0;
uniform float pulse_speed = 1.2;

// Height fade: blends to fade_color (unlit) between fade_start and fade_end.
uniform float fade_start = 100000.0;
uniform float fade_end = 100001.0;
uniform vec4 fade_color : source_color = vec4(0.86, 0.89, 0.97, 1.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 tint;

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

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	tint = COLOR.rgb;
}

void fragment() {
	vec3 n = abs(wnrm);
	vec3 w = pow(n, vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.001);
	vec3 d = texture(detail_tex, wpos.yz * detail_tiling).rgb * w.x
		+ texture(detail_tex, wpos.xz * detail_tiling).rgb * w.y
		+ texture(detail_tex, wpos.xy * detail_tiling).rgb * w.z;
	vec3 d_rel = d / max(detail_mean, 0.05);
	float rel = clamp(lum(d_rel), 0.5, 1.7);
	vec3 d_hue = d_rel / max(lum(d_rel), 0.05);

	// Horizontal coordinate along the surface for joints.
	float u;
	if (polar > 0.5) {
		vec2 dd = wpos.xz - center;
		u = atan(dd.y, dd.x) * polar_radius;
	} else {
		vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), wnrm + vec3(0.001, 0.0, 0.0)));
		u = dot(wpos, t);
	}

	float big = vnoise(wpos.xz * 0.13 + wpos.y * 0.07);
	vec3 col = mix(albedo.rgb, albedo_b.rgb, smoothstep(0.35, 0.65, big));
	float joint = 0.0;
	if (band_period > 0.0) {
		float course = floor(wpos.y / band_period);
		float cy = fract(wpos.y / band_period) * band_period;
		float uu = u + mod(course, 2.0) * brick_length * 0.5;
		float cx = fract(uu / brick_length) * brick_length;
		float mortar_y = 1.0 - smoothstep(band_width * 0.5, band_width, min(cy, band_period - cy));
		float mortar_x = 1.0 - smoothstep(band_width * 0.5, band_width, min(cx, brick_length - cx));
		joint = max(mortar_y, mortar_x);
		// Per-stone shade so the courses read as individual blocks.
		float stone_id = hash12(vec2(course, floor(uu / brick_length)));
		col *= 0.9 + 0.2 * stone_id;
	}
	if (floor_period > 0.0) {
		float up = smoothstep(0.45, 0.75, abs(wnrm.y));
		float cx;
		float cz;
		float len_x;
		float sid;
		if (polar > 0.5) {
			vec2 dd = wpos.xz - center;
			float r = length(dd);
			float ring = floor(r / floor_period);
			cz = fract(r / floor_period) * floor_period;
			float count = max(6.0, floor(6.2832 * (ring + 0.5)));
			float ang = atan(dd.y, dd.x) / 6.2832 + 1.0;
			float cell = fract(ang * count + 0.5 * mod(ring, 2.0));
			len_x = 6.2832 * max(r, 0.5) / count;
			cx = cell * len_x;
			sid = hash12(vec2(ring, floor(ang * count + 0.5 * mod(ring, 2.0))));
		} else {
			float row = floor(wpos.z / floor_period);
			float ux = wpos.x + mod(row, 2.0) * floor_period * 0.5;
			cx = fract(ux / floor_period) * floor_period;
			cz = fract(wpos.z / floor_period) * floor_period;
			len_x = floor_period;
			sid = hash12(vec2(floor(ux / floor_period), row));
		}
		float mx = 1.0 - smoothstep(band_width * 0.5, band_width, min(cx, len_x - cx));
		float mz = 1.0 - smoothstep(band_width * 0.5, band_width, min(cz, floor_period - cz));
		joint = max(joint, max(mx, mz) * up);
		col *= mix(1.0, 0.88 + 0.24 * sid, up);
	}
	if (plank_period > 0.0) {
		float flat_face = smoothstep(0.45, 0.75, abs(wnrm.y));
		vec2 pq_flat = plank_axis > 0.5 ? vec2(wpos.z, wpos.x) : vec2(wpos.x, wpos.z);
		vec2 pq = mix(vec2(wpos.y, u), pq_flat, flat_face);
		float row = floor(pq.y / plank_period);
		float along = pq.x + mod(row, 3.0) * brick_length * 0.37;
		float cq = fract(pq.y / plank_period) * plank_period;
		float cp = fract(along / brick_length) * brick_length;
		float jq = 1.0 - smoothstep(band_width * 0.5, band_width, min(cq, plank_period - cq));
		float jp = 1.0 - smoothstep(band_width * 0.5, band_width, min(cp, brick_length - cp));
		joint = max(joint, max(jq, jp));
		float board = hash12(vec2(row, floor(along / brick_length)));
		col *= 0.86 + 0.26 * board;
		// Grain: fine streaks along the board.
		float grain = vnoise(vec2(pq.x * 1.5, pq.y * 24.0 + board * 7.0));
		col *= 0.94 + 0.12 * grain;
	}
	col = mix(col, col * rel, detail_strength);
	col = mix(col, col * d_hue, detail_strength * detail_tint);
	col = mix(col, col * band_dark, joint);
	col *= tint;

	// Rune bands: dashed glyph strip, pulsing.
	float glow = 0.0;
	for (int k = 0; k < 3; k++) {
		float h = rune_heights[k];
		float dy = abs(wpos.y - h);
		float band = 1.0 - smoothstep(rune_width * 0.5 - 0.1, rune_width * 0.5, dy);
		float glyph = step(0.35, fract(u * 0.9 + float(k) * 0.3)) * step(0.15, abs(fract(u * 0.9 + 0.5 + float(k) * 0.3) - 0.5));
		float inner = 1.0 - smoothstep(rune_width * 0.5 - 0.25, rune_width * 0.5 - 0.1, dy);
		glow = max(glow, band * mix(0.35, 1.0, glyph * inner));
	}
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + wpos.y * 0.6);
	float f = smoothstep(fade_start, fade_end, wpos.y);
	ALBEDO = mix(col, rune_color.rgb * 0.5, glow * 0.6) * (1.0 - f);
	EMISSION = rune_color.rgb * rune_strength * glow * pulse * (1.0 - f) + fade_color.rgb * f;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float t = dot(NORMAL, LIGHT) * ATTENUATION;
	float lit = smoothstep(-0.03, 0.03, t);
	float bright = smoothstep(0.52, 0.58, t);
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float base = LIGHT_IS_DIRECTIONAL ? shadow_level : 0.0;
	float ramp = mix(base, mix(mid_level, 1.0, bright), lit) * reach;
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR / PI;
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(0.62, 0.78, 1.0 - n_dot_v) * lit * 0.3 * reach;
	SPECULAR_LIGHT += rim * LIGHT_COLOR / PI;
}
