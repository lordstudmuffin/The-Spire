// Summoning circle for the Guardian's summit: concentric rings, a dashed
// glyph band, radial spokes and a slowly turning double triangle, drawn as
// additive emission over the flagstones (PlaneMesh, UV 0..1).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.7, 0.42, 1.0, 1.0);
uniform float strength = 2.4;
uniform float pulse_speed = 1.1;
uniform float line = 0.016;

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(w, w * 1.8, abs(r - at));
}

// Polar distance to the edge of an equilateral triangle of circumradius R
// with one vertex at angle a0.
float tri(float r, float a, float R, float a0, float w) {
	float seg = mod(a - a0 + 3.14159 / 3.0, 2.09440) - 3.14159 / 3.0;
	float rb = (R * 0.5) / max(cos(seg), 0.05);
	return (1.0 - smoothstep(w, w * 1.8, abs(r - rb))) * step(r, R * 1.02);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME;
	float g = 0.0;
	g = max(g, ring(r, 0.985, line));
	g = max(g, ring(r, 0.90, line * 0.8));
	// Dashed glyph band between the outer rings, turning slowly.
	float band = step(0.905, r) * step(r, 0.98);
	float ga = a + t * 0.08;
	float dash = step(0.3, fract(ga * 7.6394)) * step(0.12, abs(fract(ga * 15.2788) - 0.5));
	float glyph = step(0.25, abs(fract(ga * 22.9183) - 0.5)) * step(0.915, r) * step(r, 0.97);
	g = max(g, band * dash * glyph * 0.9);
	g = max(g, ring(r, 0.62, line));
	g = max(g, ring(r, 0.575, line * 0.7));
	// Twelve spokes between the middle rings.
	float sa = a - t * 0.05;
	float spoke = 1.0 - smoothstep(line, line * 1.8, abs(fract(sa * 1.90986 + 0.5) - 0.5) * r * 0.5236);
	g = max(g, spoke * step(0.3, r) * step(r, 0.575));
	g = max(g, ring(r, 0.30, line));
	// Counter-turning double triangle in the heart.
	float ta = a + t * 0.12;
	g = max(g, tri(r, ta, 0.56, 1.5708, line));
	g = max(g, tri(r, ta, 0.56, -1.5708, line));
	g = max(g, ring(r, 0.12, line * 0.8));
	// Soft fill so the whole circle breathes a little.
	float fill = 0.06 * smoothstep(1.0, 0.55, r) + 0.1 * smoothstep(0.14, 0.0, r);
	float pulse = 0.78 + 0.22 * sin(t * pulse_speed - r * 6.0);
	float v = clamp(g + fill, 0.0, 1.0) * pulse * step(r, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = color.rgb * strength * v;
	ALPHA = v;
}
