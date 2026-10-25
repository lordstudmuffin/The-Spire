// Stylised animated water: two layers of drifting noise, sparkle caps and
// a soft wave bob. Works in the Compatibility renderer.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, blend_mix;

uniform vec4 shallow_color : source_color = vec4(0.45, 0.88, 0.95, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.52, 0.78, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.86;
uniform float flow_speed = 0.25;
uniform vec2 flow_dir = vec2(1.0, 0.0);
uniform float wave_height = 0.04;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.6 + wpos.x * 0.9 + wpos.z * 0.7) * wave_height;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 d = normalize(flow_dir) * TIME * flow_speed;
	float n1 = vnoise(p * 0.55 + d);
	float n2 = vnoise(p * 1.3 - d * 1.7 + 4.2);
	float n = n1 * 0.65 + n2 * 0.35;
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.3, 0.75, n));
	float caps = smoothstep(0.64, 0.70, vnoise(p * 2.2 + d * 2.5 + n * 0.8));
	col = mix(col, vec3(0.95, 1.0, 1.0), caps * 0.7);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = col * 0.08;
}
