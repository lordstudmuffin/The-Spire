// Soft unlit cloud puffs: top is bright, underside a lavender shadow.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 top_color : source_color = vec4(1.0, 0.99, 0.97, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.72, 0.76, 0.92, 1.0);

varying float ny;
varying vec3 tint;

void vertex() {
	ny = normalize((MODEL_NORMAL_MATRIX * NORMAL)).y;
	tint = COLOR.rgb;
}

void fragment() {
	float t = smoothstep(-0.6, 0.7, ny);
	ALBEDO = mix(bottom_color.rgb, top_color.rgb, t) * tint;
}
