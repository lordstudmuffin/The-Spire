// Death dissolve for mob parts (Godot 4.3+). Swapped onto the rig's
// MeshInstance3Ds by VFX.dissolve for ~0.6 s: procedural 3D value noise is
// clipped against `dissolve` (0 = intact, 1 = gone) with a hot glowing edge
// just above the cut. Unshaded on purpose: the part is already burning away.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, blend_mix, unshaded;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float edge_width : hint_range(0.01, 0.4) = 0.14;
uniform float noise_scale = 7.0;

varying vec3 wpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos * noise_scale) * 0.65 + vnoise(wpos * noise_scale * 2.9) * 0.35;
	n = clamp(n * 0.9 + 0.05, 0.0, 1.0);
	float cut = dissolve * (1.0 + edge_width);
	if (n < cut - edge_width) {
		discard;
	}
	float edge = 1.0 - smoothstep(cut - edge_width, cut, n);
	ALBEDO = albedo.rgb * texture(albedo_tex, UV).rgb * (0.9 - 0.4 * dissolve);
	EMISSION = edge_color.rgb * (edge * 5.0 + dissolve * 0.6);
	ALPHA = 1.0;
}
