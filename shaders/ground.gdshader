// Painterly cel-shaded ground for Floor 1. Colour comes from world XZ so one
// flat disc reads as meadow, sand roads, a cobbled plaza, village dirt and a
// rocky rim. The road/plaza layout mirrors WorldArt.ground_kind() in GDScript.
// Poly Haven diffuse/normal maps (grass, gravel, cobblestone) add surface
// detail per zone; the painted palette and the cel ramp in light() stay.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 grass_a : source_color = vec4(0.373, 0.682, 0.290, 1.0);
uniform vec4 grass_b : source_color = vec4(0.561, 0.827, 0.420, 1.0);
uniform vec4 sand : source_color = vec4(0.851, 0.765, 0.604, 1.0);
uniform vec4 stone : source_color = vec4(0.604, 0.604, 0.651, 1.0);
uniform vec4 dirt : source_color = vec4(0.60, 0.47, 0.34, 1.0);
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
	// Broad meadow patches: sun-dried gold and deep lush green, on the same
	// pattern as the grass blades (grass.gdshader) so tufts match the soil.
	float pa = sin(p.x * 0.11 + sin(p.y * 0.07) * 2.0) * sin(p.y * 0.12 + sin(p.x * 0.06) * 1.7);
	g *= mix(vec3(1.0), pa > 0.0 ? vec3(1.12, 1.04, 0.70) : vec3(0.80, 0.90, 0.82), smoothstep(0.1, 0.7, abs(pa)) * 0.6);

	// Roads (segments) -> sand with a noisy edge.
	float road = seg(p, vec2(0.0, -7.0), vec2(0.0, -57.0));
	road = min(road, seg(p, vec2(-20.0, 24.0), vec2(-46.0, 36.0)));
	road = min(road, seg(p, vec2(-5.0, -6.0), vec2(-14.0, -41.0)));
	road = min(road, seg(p, vec2(0.0, 37.0), vec2(0.0, 62.0)));
	road = min(road, seg(p, vec2(22.0, 13.0), vec2(48.0, -10.0)));
	float en = (fbm(p * 0.33) - 0.5) * 1.8;
	float sand_m = 1.0 - smoothstep(2.2 + en, 3.4 + en, road);

	float dplaza = length(p - vec2(0.0, 15.0));
	float plaza_m = 1.0 - smoothstep(21.6, 22.2, dplaza);
	float hb = 1.0 - smoothstep(11.0 + en, 13.5 + en, length(p - vec2(-48.0, 38.0)));
	float tv = 1.0 - smoothstep(8.0 + en, 10.0 + en, length(p - vec2(-14.0, -44.0)));
	float pond = length(p - vec2(54.0, -14.0));
	float pond_m = 1.0 - smoothstep(8.5 + en * 0.5, 10.5 + en * 0.5, pond);
	float rim = smoothstep(84.0 + en * 2.0, 88.5, length(p));
	float tower = 1.0 - smoothstep(13.0, 16.0 + en, length(p - vec2(0.0, -70.0)));
	// Inside the town wall (r 36 round the plaza) the roads are stone-paved,
	// as in Aincrad's first town; they turn to sand at the gates.
	float townroad = sand_m * (1.0 - smoothstep(34.0, 36.5, dplaza));

	// Cobbles: a soft per-stone shade and the plaza's concentric ring; the
	// stone pattern itself comes from the cobblestone detail map.
	// Voronoi set stones: F2 - F1 gives the mortar joint between rounded,
	// irregular cobbles (only evaluated where the plaza or tower apron is).
	float cob = 1.0;
	float cshade = 1.0;
	if (plaza_m > 0.001 || tower > 0.001 || townroad > 0.001) {
		vec2 cp = p * 2.2;
		vec2 ci = floor(cp);
		vec2 cf = fract(cp);
		float f1 = 8.0;
		float f2 = 8.0;
		vec2 id = vec2(0.0);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 g2 = vec2(float(i), float(j));
				vec2 o = vec2(hash12(ci + g2), hash12(ci + g2 + 19.19)) * 0.8 + 0.1;
				float dd = length(g2 + o - cf);
				if (dd < f1) {
					f2 = f1;
					f1 = dd;
					id = ci + g2;
				} else if (dd < f2) {
					f2 = dd;
				}
			}
		}
		float joint = f2 - f1;
		cob = smoothstep(0.04, 0.16, joint);
		// Domed stones: lighter toward each stone's middle.
		cob *= 0.88 + 0.12 * smoothstep(0.6, 0.0, f1);
		// Per-stone tone: value and a slight warm/cool shift, so the plaza
		// reads as laid stones rather than one pale sheet.
		cshade = 0.74 + 0.26 * hash12(id);
	}
	float ring = smoothstep(0.1, 0.0, abs(fract(dplaza * 0.2) - 0.5) - 0.42);
	vec3 stone_base = stone.rgb * 0.82;
	float cob_amt = 1.0;
	vec3 cob_col = mix(stone_base * 0.6, stone_base * cshade, mix(1.0, cob, cob_amt));
	vec3 road_cob = cob_col;
	cob_col = mix(cob_col, vec3(0.78, 0.68, 0.55), ring * 0.45);
	cob_col = mix(cob_col, cob_col * 0.93, step(0.6, n2) * 0.5);

	vec3 col = g;
	col = mix(col, sand.rgb * (0.92 + 0.16 * n2), sand_m);
	col = mix(col, dirt.rgb * (0.9 + 0.2 * n2), max(hb, tv));
	col = mix(col, sand.rgb * 0.85, pond_m);
	col = mix(col, mix(dirt.rgb, stone.rgb, 0.5) * (0.85 + 0.3 * n2), rim);
	col = mix(col, stone.rgb * (0.8 + 0.2 * cob), tower);
	col = mix(col, road_cob, townroad);
	col = mix(col, cob_col, plaza_m);

	// Detail layer: zone weights pick grass / gravel / cobble maps, their
	// luminance modulates the painted colour and a touch of their hue bleeds in.
	// Uniform branch: with detail_strength 0 (no maps bound, or the Low preset
	// via RenderProfile) none of the six texture fetches are issued.
	if (detail_strength > 0.0005) {
		float w_cob = max(max(plaza_m, tower), townroad);
		float w_path = max(max(sand_m, max(hb, tv)), max(pond_m, rim)) * (1.0 - w_cob);
		float w_grass = clamp(1.0 - w_path - w_cob, 0.0, 1.0);
		vec3 gd = texture(grass_tex, p * grass_tiling).rgb;
		vec3 pd = texture(path_tex, p * path_tiling).rgb;
		vec3 cd = texture(cobble_tex, p * cobble_tiling).rgb;
		vec3 detail = gd * w_grass + pd * w_path + cd * w_cob;
		float dmean = grass_mean * w_grass + path_mean * w_path + cobble_mean * w_cob;
		vec3 d_rel = detail / max(dmean, 0.05);          // ~1.0 on average
		float rel = clamp(lum(d_rel), 0.6, 1.3);         // luminance variation (kept narrow: painted, not photographic)
		vec3 d_hue = d_rel / max(lum(d_rel), 0.05);      // hue only
		// On the plaza the painted stone pattern leads: the photo cobbles are a
		// different size and turn the joints to mush at full strength.
		float ds = detail_strength * (1.0 - 0.75 * w_cob);
		col *= mix(vec3(1.0), vec3(rel), ds) * mix(vec3(1.0), d_hue, detail_tint * ds);

		// The disc is flat, so the tangent frame is world XZ: perturb the normal
		// here instead of relying on mesh tangents (u = +x, v = +z, GL convention).
		vec3 nm = texture(grass_nor, p * grass_tiling).rgb * w_grass
			+ texture(path_nor, p * path_tiling).rgb * w_path
			+ texture(cobble_nor, p * cobble_tiling).rgb * w_cob;
		float depth = normal_strength * detail_strength * mix(0.6, 0.3, w_cob);
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
