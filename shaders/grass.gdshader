// Wind-swayed grass blades for a MultiMesh. UV.y runs 0 at the root to 1 at
// the tip; instance COLOR tints each tuft.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.17, 0.40, 0.14, 1.0);
uniform vec4 tip_color : source_color = vec4(0.44, 0.74, 0.30, 1.0);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.22;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.3;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.6;
// Wind gusts: broad bands that roll across the meadow, bending the blades
// further and catching the light on the tips (the sheen of wind over a
// field). Patches: slow world-space variation toward warm, sun-dried grass
// and toward deep, lush grass, so a field never reads as one flat colour.
uniform float gust_strength : hint_range(0.0, 1.0) = 0.5;
uniform vec2 gust_dir = vec2(0.8, 0.6);
uniform vec3 dry_tint : source_color = vec3(1.18, 1.08, 0.66);
uniform vec3 lush_tint : source_color = vec3(0.78, 0.92, 0.82);

varying float h;
varying vec3 tint;
varying float gust;
varying vec2 wxz;

float wave(vec2 p, float t) {
	float d = dot(p, normalize(gust_dir));
	float a = sin(d * 0.07 - t * 1.1) * 0.5 + 0.5;
	float b = sin(d * 0.13 + p.y * 0.03 - t * 1.7) * 0.5 + 0.5;
	return smoothstep(0.55, 1.0, a * 0.7 + b * 0.3);
}

void vertex() {
	h = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed;
	float sway = sin(t + wp.x * 0.35 + wp.z * 0.22) * 0.65 + sin(t * 1.9 + wp.z * 0.9 + wp.x * 0.3) * 0.35;
	gust = wave(wp.xz, TIME) * gust_strength;
	float k = h * h * wind_strength;
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.45 * k;
	// The gust leans blades downwind (in object space; tufts are only spun
	// about Y, so this stays close enough to the world direction).
	vec2 gd = normalize(gust_dir) * gust * h * h * 0.35;
	VERTEX.x += gd.x;
	VERTEX.z += gd.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
	tint = COLOR.rgb;
	wxz = wp.xz;
}

void fragment() {
	vec3 c = mix(base_color.rgb, tip_color.rgb, h) * tint;
	float pa = sin(wxz.x * 0.11 + sin(wxz.y * 0.07) * 2.0) * sin(wxz.y * 0.12 + sin(wxz.x * 0.06) * 1.7);
	c *= mix(vec3(1.0), pa > 0.0 ? dry_tint : lush_tint, smoothstep(0.15, 0.75, abs(pa)) * 0.6);
	c += vec3(0.16, 0.17, 0.1) * gust * h * h;
	ALBEDO = c;
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
