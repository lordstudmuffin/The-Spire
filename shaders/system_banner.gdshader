// Realm announcement banner (RealmBanner): a strip of thin hexagon lines
// that drifts sideways, warm red-amber, fading out at both ends. Original
// pattern; evokes a system message written across the sky.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.95, 0.3, 0.16, 1.0);
uniform float cell = 26.0;
uniform vec2 rect_size = vec2(1600.0, 120.0);
uniform float open_amount : hint_range(0.0, 1.0) = 1.0;

// Distance to the nearest hex-cell edge (0 at the edge), pointy-top grid.
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	float hexd = max(dot(g, normalize(vec2(1.0, 1.7320508))), g.x);
	return 0.5 - hexd;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = (px + vec2(TIME * 14.0, 0.0)) / cell;
	float e = hex_edge(p);
	float line = 1.0 - smoothstep(0.0, 0.06, e);
	float ends = smoothstep(0.0, 0.22, UV.x) * (1.0 - smoothstep(0.78, 1.0, UV.x));
	float centre = 1.0 - abs(UV.x - 0.5) * 2.0;
	float vert = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	// Lit only inside the opened width.
	float open_m = 1.0 - smoothstep(open_amount * 0.5 - 0.02, open_amount * 0.5, abs(UV.x - 0.5));
	float base = 0.72 * ends * vert;
	vec3 col = mix(vec3(0.07, 0.015, 0.02), tint.rgb, line * (0.25 + 0.35 * centre));
	float a = (base + line * 0.25 * ends) * open_m;
	// Bright rules along the top and bottom edges.
	float rule = (1.0 - smoothstep(0.0, 2.0, px.y)) + (1.0 - smoothstep(0.0, 2.0, rect_size.y - px.y));
	col = mix(col, tint.rgb * 1.3, clamp(rule, 0.0, 1.0));
	a = max(a, clamp(rule, 0.0, 1.0) * ends * open_m);
	COLOR = vec4(col, a * tint.a);
}
