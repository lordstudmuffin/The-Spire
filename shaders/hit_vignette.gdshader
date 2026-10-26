// Screen-space damage vignette for the HUD (CanvasItem). `strength` is
// tweened by HUD when the local player takes damage; a low-HP pulse keeps a
// faint baseline. Crimson stays on the screen border (the centre and the
// fight stay readable), with faint scanlines and flicker so it reads as
// the game system warning you rather than a paint wash.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.06, 0.1, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Rounded-rectangle distance: hugs all four edges, not just the corners.
	vec2 q = abs(uv) - vec2(0.62, 0.5);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	float v = smoothstep(0.12, 0.55, d);
	// Fine scanlines inside the red band.
	float lattice = (0.5 + 0.5 * sin(UV.y / SCREEN_PIXEL_SIZE.y * 1.6)) * 0.3;
	float flicker = 0.9 + 0.1 * sin(TIME * 38.0);
	float a = clamp(v * (0.85 + lattice) * strength * flicker, 0.0, 0.75);
	COLOR = vec4(mix(tint.rgb, vec3(1.0, 0.35, 0.35), lattice * v), a);
}
