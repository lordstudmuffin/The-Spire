// Ground danger zone for boss telegraphs (VFX.boss_*_warning). Drawn on a
// flat plane: shape 0 = circle (slam), 1 = sector toward local -Z (sweep,
// half-angle `arc`), 2 = lane along local -Z (charge). A faint red field,
// a hard bright rim, and a fill that sweeps outward with `progress` (0..1
// over the wind-up) so the moment of impact can be read from the ground.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform int shape = 0;
uniform float arc = 1.3;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color : source_color = vec4(1.0, 0.16, 0.1, 1.0);
uniform float rim_px = 0.035;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float inside = 0.0;
	float t = 0.0;
	float rim = 0.0;
	if (shape == 2) {
		t = (1.0 - p.y) * 0.5;               // 0 at the start, 1 at the end
		inside = 1.0;
		rim = max(smoothstep(1.0 - rim_px * 2.0, 1.0, abs(p.x)), smoothstep(1.0 - rim_px, 1.0, abs(p.y)));
		// Chevrons pointing along the lane.
		float chev = fract((t - abs(p.x) * 0.12) * 7.0 - TIME * 1.6);
		float fill = step(t, progress);
		float a = 0.16 + 0.22 * fill + 0.14 * smoothstep(0.55, 0.6, chev) * (1.0 - smoothstep(0.6, 0.75, chev));
		a = max(a, rim * 0.9);
		ALBEDO = mix(color.rgb, vec3(1.0, 0.8, 0.7), rim * 0.5);
		ALPHA = a * fade;
	} else {
		float r = length(p);
		inside = 1.0 - smoothstep(0.995, 1.0, r);
		t = r;
		rim = smoothstep(1.0 - rim_px, 1.0, r) * inside;
		if (shape == 1) {
			float ang = abs(atan(p.x, -p.y));
			inside *= 1.0 - smoothstep(arc - 0.01, arc, ang);
			float side = smoothstep(arc - rim_px * 1.6 / max(r, 0.05), arc, ang);
			rim = max(rim * inside, side * inside);
		}
		float fill = step(t, progress);
		float front = smoothstep(progress - 0.06, progress, t) * (1.0 - step(progress, t)) * step(0.02, progress);
		// Concentric pulses running outward.
		float rings = smoothstep(0.85, 1.0, fract(t * 4.0 - TIME * 1.5)) * 0.12;
		float a = (0.15 + 0.22 * fill + rings) * inside;
		a = max(a, max(rim, front) * 0.9 * inside);
		ALBEDO = mix(color.rgb, vec3(1.0, 0.85, 0.75), max(rim, front) * 0.5);
		ALPHA = a * fade;
	}
}
