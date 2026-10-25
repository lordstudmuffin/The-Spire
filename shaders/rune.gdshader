// Pulsing glowing rune ring for pads, gates and terraces.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float strength = 2.2;
uniform float pulse_speed = 1.6;

void fragment() {
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + UV.x * 12.0);
	ALBEDO = color.rgb * 0.5;
	EMISSION = color.rgb * strength * pulse;
	ROUGHNESS = 0.4;
}
