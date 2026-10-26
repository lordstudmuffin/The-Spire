// Holographic backdrop for the full floor map: a deep blue disc with a fine
// hex lattice, a slow radar sweep and a bright rim, so the map reads like a
// projected system window rather than a printed chart. Original art.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.03, 0.07, 0.14, 0.94);
uniform vec4 grid_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float hex_size = 0.035;   // cell size as a fraction of the disc diameter
uniform float sweep_speed = 0.35; // radians per second

float hex_dist(vec2 p) {
	// Distance to the nearest edge of a pointy hex cell lattice.
	const vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(s)), g.x);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	if (disc <= 0.0) {
		discard;
	}
	// Brighter toward the centre, like light from the projector.
	vec3 col = base_color.rgb * (1.25 - 0.45 * r);
	// Hex lattice, fading toward the rim.
	float hd = hex_dist(p / hex_size);
	float line = 1.0 - smoothstep(0.0, 0.06 + fwidth(hd) * 1.2, hd);
	col += grid_color.rgb * line * 0.09 * (1.0 - 0.5 * r);
	// Radar sweep: a soft wedge trailing behind a bright leading edge.
	float ang = atan(p.y, p.x);
	float lead = mod(TIME * sweep_speed, 6.2831853);
	float behind = mod(lead - ang + 6.2831853, 6.2831853);
	float wedge = exp(-behind * 2.2) * 0.12;
	col += grid_color.rgb * wedge * smoothstep(0.0, 0.2, r);
	// Horizontal scan lines, very faint.
	col *= 0.96 + 0.04 * sin(UV.y * 900.0);
	// Rim: inner glow plus a crisp edge.
	float rim = smoothstep(0.86, 1.0, r);
	col += grid_color.rgb * rim * rim * 0.35;
	COLOR = vec4(col, base_color.a * disc);
}
