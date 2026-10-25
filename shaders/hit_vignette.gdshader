// Screen-space damage vignette for the HUD (CanvasItem). `strength` is
// tweened by HUD when the local player takes damage; a low-HP pulse keeps a
// faint baseline. Red bleeds in from the corners, the centre stays clear.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.08, 0.1, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv * vec2(1.0, 1.2));
	float v = smoothstep(0.5, 1.45, r);
	COLOR = vec4(tint.rgb, v * strength * 0.9);
}
