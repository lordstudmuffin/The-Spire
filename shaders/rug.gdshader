// Woven cottage rug (PlaneMesh, UV 0..1): a wide border with a running
// diamond motif, a lozenge field, a medallion and a fringe at the short
// ends. Cel-lit like the rest of the world; `weave` adds thread texture.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 base : source_color = vec4(0.66, 0.2, 0.18, 1.0);
uniform vec4 accent : source_color = vec4(0.85, 0.64, 0.25, 1.0);
uniform vec4 dark : source_color = vec4(0.2, 0.12, 0.16, 1.0);
uniform vec4 pale : source_color = vec4(0.95, 0.88, 0.74, 1.0);
uniform float weave = 0.08;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform float mid_level : hint_range(0.0, 1.0) = 0.8;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float stripe(float x, float at, float w) {
	return 1.0 - smoothstep(w * 0.8, w, abs(x - at));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // -1..1
	vec2 a = abs(p);
	float edge = max(a.x, a.y);
	// Fringe on the short ends (UV.x), outside the woven field.
	float fringe = step(0.94, a.x) * step(a.y, 0.9) * step(0.5, fract(p.y * 22.0));
	vec3 col = base.rgb;
	// Border bands.
	float band = stripe(edge, 0.9, 0.025) + stripe(edge, 0.78, 0.02);
	col = mix(col, accent.rgb, clamp(band, 0.0, 1.0));
	col = mix(col, dark.rgb, stripe(edge, 0.84, 0.015));
	// Running diamonds inside the border.
	float inb = step(0.80, edge) * step(edge, 0.88);
	vec2 q = (a.x > a.y) ? vec2(p.y, edge) : vec2(p.x, edge);
	float dia = 1.0 - smoothstep(0.028, 0.04, abs(fract(q.x * 6.0) - 0.5) * 0.14 + abs(q.y - 0.84) - 0.03);
	col = mix(col, pale.rgb, inb * dia);
	// Field lozenges.
	float field = step(edge, 0.76);
	vec2 g = fract(p * vec2(4.0, 3.0)) - 0.5;
	float loz = 1.0 - smoothstep(0.30, 0.34, abs(g.x) + abs(g.y));
	float loz_in = 1.0 - smoothstep(0.17, 0.21, abs(g.x) + abs(g.y));
	col = mix(col, dark.rgb, field * loz * 0.55);
	col = mix(col, accent.rgb, field * loz_in);
	// Central medallion.
	float r = length(p * vec2(1.0, 1.4));
	float med = 1.0 - smoothstep(0.30, 0.33, r);
	float ring = stripe(r, 0.27, 0.02) + stripe(r, 0.18, 0.015);
	col = mix(col, pale.rgb, med);
	col = mix(col, base.rgb, med * clamp(ring, 0.0, 1.0));
	float star = 1.0 - smoothstep(0.08, 0.1, abs(p.x) * 1.0 + abs(p.y) * 1.4 - 0.02);
	col = mix(col, accent.rgb, med * star);
	// Thread texture.
	float w = hash12(floor(UV * vec2(220.0, 150.0)));
	col *= 1.0 - weave + weave * 2.0 * w;
	col = mix(col, pale.rgb * 0.9, fringe);
	ALBEDO = col;
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float t = dot(NORMAL, LIGHT) * ATTENUATION;
	float lit = smoothstep(-0.03, 0.03, t);
	float bright = smoothstep(0.52, 0.58, t);
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float base_l = LIGHT_IS_DIRECTIONAL ? shadow_level : 0.0;
	float ramp = mix(base_l, mix(mid_level, 1.0, bright), lit) * reach;
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR / PI;
}
