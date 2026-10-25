// Painterly cel-shaded ground for Floor 2 "Mirewood": leaf litter and moss
// instead of meadow, mud tracks instead of sand roads, a flagstone waygate
// circle, the hunters' village dirt, the lake bed, the barrow and the tower
// apron. Layout mirrors Floor2Art.ground_kind() in GDScript. Same uniforms
// as ground.gdshader so WorldArt.bind_ground_detail feeds it (forest_floor,
// brown_mud_leaves_01, cobblestone_floor_08).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 grass_a : source_color = vec4(0.47, 0.40, 0.22, 1.0);   // leaf litter, olive brown
uniform vec4 grass_b : source_color = vec4(0.70, 0.52, 0.26, 1.0);   // amber drifts
uniform vec4 moss : source_color = vec4(0.33, 0.45, 0.22, 1.0);
uniform vec4 sand : source_color = vec4(0.36, 0.29, 0.21, 1.0);      // mud tracks
uniform vec4 stone : source_color = vec4(0.49, 0.52, 0.48, 1.0);
uniform vec4 dirt : source_color = vec4(0.42, 0.33, 0.25, 1.0);
uniform vec4 lakebed : source_color = vec4(0.30, 0.33, 0.24, 1.0);
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform float mid_level : hint_range(0.0, 1.0) = 0.82;

// Detail maps (world-space XZ tiling, repeats per metre). Default white /
// flat so the shader renders the plain painted look when none are bound.
uniform sampler2D grass_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_tiling = 0.18;
uniform float path_tiling = 0.28;
uniform float cobble_tiling = 0.42;
// Mean luminance of each diffuse map, so detail only modulates around 1.0.
uniform float grass_mean = 0.5;
uniform float path_mean = 0.5;
uniform float cobble_mean = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform float detail_tint : hint_range(0.0, 1.0) = 0.25;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.45;

varying vec3 wpos;

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * 0.07);
	float n2 = vnoise(p * 0.7);
	float speck = step(0.78, vnoise(p * 2.3));
	vec3 g = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.32, 0.68, n));
	g = mix(g, g * 1.10, speck * 0.6);
	g = mix(g, g * 0.92, step(0.72, n2) * 0.5);

	// Leaf litter with moss pooling in the low noise and under the trees.
	float mossn = fbm(p * 0.11 + vec2(40.0, 9.0));
	g = mix(g, moss.rgb * (0.9 + 0.2 * n2), smoothstep(0.52, 0.7, mossn));
	// Fallen leaves: warm specks.
	float leaf = step(0.82, vnoise(p * 3.1 + vec2(3.0, 1.0)));
	g = mix(g, vec3(0.78, 0.42, 0.18), leaf * 0.5);

	// Mud tracks (segments) with a noisy edge.
	float road = seg(p, vec2(0.0, 28.0), vec2(-22.0, 18.0));
	road = min(road, seg(p, vec2(6.0, 30.0), vec2(19.0, 12.0)));
	road = min(road, seg(p, vec2(0.0, 26.0), vec2(6.0, -52.0)));
	road = min(road, seg(p, vec2(-38.0, 0.0), vec2(-40.0, -30.0)));
	road = min(road, seg(p, vec2(-22.0, 18.0), vec2(-38.0, 0.0)));
	float en = (fbm(p * 0.33) - 0.5) * 1.8;
	float sand_m = 1.0 - smoothstep(1.8 + en, 3.2 + en, road);

	float dplaza = length(p - vec2(0.0, 34.0));
	float plaza_m = 1.0 - smoothstep(8.6, 9.2, dplaza);
	float hb = 1.0 - smoothstep(13.0 + en, 16.0 + en, length(p - vec2(-34.0, 14.0)));   // village
	float tv = 1.0 - smoothstep(11.0 + en, 14.0 + en, length(p - vec2(-40.0, -42.0)));  // barrow
	float pond = length(p - vec2(38.0, 6.0));
	float pond_m = 1.0 - smoothstep(20.5 + en * 0.5, 23.0 + en * 0.5, pond);
	float isle = 1.0 - smoothstep(5.6, 6.3, length(p - vec2(42.0, 2.0)));
	float rim = smoothstep(84.0 + en * 2.0, 88.5, length(p));
	float tower = 1.0 - smoothstep(13.0, 16.0 + en, length(p - vec2(8.0, -70.0)));

	// Cobbles: a soft per-stone shade and the plaza's concentric ring; the
	// stone pattern itself comes from the cobblestone detail map.
	vec2 cp = p * 2.4;
	cp.x += step(0.5, fract(cp.y * 0.5)) * 0.5;
	vec2 ci = floor(cp);
	vec2 cf = fract(cp) - 0.5;
	float cob = smoothstep(0.5, 0.4, length(cf * vec2(1.0, 1.3)));
	float cshade = 0.86 + 0.14 * hash12(ci);
	float ring = smoothstep(0.1, 0.0, abs(fract(dplaza * 0.2) - 0.5) - 0.42);
	vec3 stone_base = stone.rgb * 0.9;
	float cob_amt = mix(1.0, 0.25, detail_strength);
	vec3 cob_col = mix(stone_base * 0.78, stone_base * cshade, mix(1.0, cob, cob_amt));
	cob_col = mix(cob_col, vec3(0.78, 0.68, 0.55), ring * 0.45);
	cob_col = mix(cob_col, cob_col * 0.93, step(0.6, n2) * 0.5);

	vec3 col = g;
	col = mix(col, sand.rgb * (0.92 + 0.16 * n2), sand_m);
	col = mix(col, dirt.rgb * (0.9 + 0.2 * n2), max(hb, tv));
	col = mix(col, lakebed.rgb * (0.85 + 0.3 * n2), pond_m);
	col = mix(col, mix(dirt.rgb, stone.rgb, 0.5) * (0.85 + 0.3 * n2), rim);
	col = mix(col, stone.rgb * (0.8 + 0.2 * cob), tower);
	col = mix(col, cob_col, max(plaza_m, isle));
	// Barrow: grey ash and old flagstones showing through the dirt.
	col = mix(col, stone.rgb * 0.75 * (0.85 + 0.3 * n2), tv * smoothstep(0.55, 0.75, n));

	// Detail layer: zone weights pick grass / gravel / cobble maps, their
	// luminance modulates the painted colour and a touch of their hue bleeds in.
	// Uniform branch: with detail_strength 0 (no maps bound, or the Low preset
	// via RenderProfile) none of the six texture fetches are issued.
	if (detail_strength > 0.0005) {
		float w_cob = max(max(plaza_m, isle), tower);
		float w_path = max(max(sand_m, max(hb, tv)), max(pond_m, rim)) * (1.0 - w_cob);
		float w_grass = clamp(1.0 - w_path - w_cob, 0.0, 1.0);
		vec3 gd = texture(grass_tex, p * grass_tiling).rgb;
		vec3 pd = texture(path_tex, p * path_tiling).rgb;
		vec3 cd = texture(cobble_tex, p * cobble_tiling).rgb;
		vec3 detail = gd * w_grass + pd * w_path + cd * w_cob;
		float dmean = grass_mean * w_grass + path_mean * w_path + cobble_mean * w_cob;
		vec3 d_rel = detail / max(dmean, 0.05);          // ~1.0 on average
		float rel = clamp(lum(d_rel), 0.45, 1.8);        // luminance variation
		vec3 d_hue = d_rel / max(lum(d_rel), 0.05);      // hue only
		col *= mix(vec3(1.0), vec3(rel), detail_strength) * mix(vec3(1.0), d_hue, detail_tint * detail_strength);

		// The disc is flat, so the tangent frame is world XZ: perturb the normal
		// here instead of relying on mesh tangents (u = +x, v = +z, GL convention).
		vec3 nm = texture(grass_nor, p * grass_tiling).rgb * w_grass
			+ texture(path_nor, p * path_tiling).rgb * w_path
			+ texture(cobble_nor, p * cobble_tiling).rgb * w_cob;
		float depth = normal_strength * detail_strength * mix(0.6, 1.3, w_cob);
		vec3 n_w = normalize(vec3((nm.r * 2.0 - 1.0) * depth, 1.0, (nm.g * 2.0 - 1.0) * depth));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float t = dot(NORMAL, LIGHT) * ATTENUATION;
	float lit = smoothstep(-0.02, 0.06, t);
	float bright = smoothstep(0.5, 0.58, t);
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float base = LIGHT_IS_DIRECTIONAL ? shadow_level : 0.0;
	float ramp = mix(base, mix(mid_level, 1.0, bright), lit) * reach;
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR / PI;
}
