// Wind-swayed grass blades for a MultiMesh. UV.y runs 0 at the root to 1 at
// the tip; instance COLOR tints each tuft.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.17, 0.40, 0.14, 1.0);
uniform vec4 tip_color : source_color = vec4(0.44, 0.74, 0.30, 1.0);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.22;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.3;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.6;

varying float h;
varying vec3 tint;

void vertex() {
	h = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed;
	float sway = sin(t + wp.x * 0.35 + wp.z * 0.22) * 0.65 + sin(t * 1.9 + wp.z * 0.9 + wp.x * 0.3) * 0.35;
	float k = h * h * wind_strength;
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.45 * k;
	NORMAL = vec3(0.0, 1.0, 0.0);
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = mix(base_color.rgb, tip_color.rgb, h) * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float t = dot(NORMAL, LIGHT) * ATTENUATION;
	float lit = smoothstep(-0.02, 0.06, t);
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float base = LIGHT_IS_DIRECTIONAL ? shadow_level : 0.0;
	DIFFUSE_LIGHT += mix(base, 1.0, lit) * reach * LIGHT_COLOR / PI;
}
