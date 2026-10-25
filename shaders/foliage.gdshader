// Cel-shaded foliage/prop shader for MultiMeshes: instance COLOR tints the
// albedo and the top of the mesh sways gently in the wind.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float wind : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.42;
uniform float mid_level : hint_range(0.0, 1.0) = 0.74;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;

varying vec3 tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.1 + wp.x * 0.18 + wp.z * 0.27) + 0.5 * sin(TIME * 2.3 + wp.z * 0.5);
	float k = max(VERTEX.y, 0.0) * 0.06 * wind;
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.5 * k;
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = albedo.rgb * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	EMISSION = emission_color.rgb * emission_strength * tint;
}

void light() {
	float t = dot(NORMAL, LIGHT) * ATTENUATION;
	float lit = smoothstep(-0.03, 0.03, t);
	float bright = smoothstep(0.52, 0.58, t);
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float base = LIGHT_IS_DIRECTIONAL ? shadow_level : 0.0;
	float ramp = mix(base, mix(mid_level, 1.0, bright), lit) * reach;
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR / PI;
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(0.62, 0.78, 1.0 - n_dot_v) * lit * 0.35 * reach;
	SPECULAR_LIGHT += rim * LIGHT_COLOR / PI;
}
