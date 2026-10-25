// Opaque twin of toon.gdshader for merged rigs (MeshMerge). The base toon
// shader writes ALPHA, which puts every part in the transparent queue, where
// surfaces of one mesh draw in surface order without depth writes; a merged
// belly would paint over the body. This variant never writes ALPHA, so the
// merged surfaces depth-test against each other like the separate parts did.
// Anime cel-shaded (toon) surface shader. Godot 4.3+.
// Lighting is replaced by a banded ramp (2 or 3 bands) computed per light in
// light(), a cool-tinted shadow band, a small hard specular dot and a soft
// view-dependent rim highlight on the lit side.
shader_type spatial;
// Ambient is disabled on purpose: the shadow band *is* the ambient-lit colour,
// so pale albedos (skin) keep their hue instead of washing out to white.
render_mode cull_back, depth_draw_opaque, ambient_light_disabled;

// Base colour (flat; no texture needed for the primitive prototype models).
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Optional glow (eyes, magic). Multiplied by emission_strength; 0 = off.
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 16.0, 0.05) = 0.0;

// Cel ramp. bands = 2 -> shadow/lit, bands = 3 -> shadow/mid/lit.
uniform int bands : hint_range(2, 3) = 3;
uniform float shadow_level : hint_range(0.0, 1.0, 0.01) = 0.58; // brightness of the shadow band
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.74, 0.92, 1.0); // cool anime shadow colour
uniform float mid_level : hint_range(0.0, 1.0, 0.01) = 0.8;    // brightness of the middle band (3 bands only)
uniform float lit_level : hint_range(0.0, 1.5, 0.01) = 0.95;   // brightness of the fully lit band (keeps pale colours from blowing out)
uniform float lit_threshold : hint_range(-1.0, 1.0, 0.01) = 0.08; // N.L where shadow ends
uniform float mid_threshold : hint_range(-1.0, 1.0, 0.01) = 0.55; // N.L where the brightest band starts
uniform float band_softness : hint_range(0.0, 0.3, 0.005) = 0.025; // anti-aliased band edge width

// Toon specular dot (small hard highlight).
uniform float specular_size : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.18;

// Rim light: soft bright edge on the silhouette, only where the light reaches.
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0, 0.05) = 0.4;
uniform float rim_width : hint_range(0.01, 1.0, 0.01) = 0.32;
uniform float rim_softness : hint_range(0.0, 0.5, 0.01) = 0.18;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb * emission_strength;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);

	// Banded diffuse ramp. ATTENUATION already contains shadow-map occlusion,
	// so push it through the same step so shadows get a hard cel edge too.
	float lit_t = n_dot_l * ATTENUATION;
	// Point/spot lights: no ambient shadow band (a lantern does not brighten
	// the far side of a wall) and a smooth fade-out with distance, otherwise
	// every light in range adds a full-strength band and the scene washes out.
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 : clamp(ATTENUATION * 2.0, 0.0, 1.0);
	float lit = smoothstep(lit_threshold - band_softness, lit_threshold + band_softness, lit_t);
	vec3 shadow_col = shadow_tint.rgb * shadow_level;
	vec3 ramp;
	if (bands >= 3) {
		float bright = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, lit_t);
		ramp = mix(shadow_col, mix(vec3(mid_level), vec3(lit_level), bright), lit);
	} else {
		ramp = mix(shadow_col, vec3(lit_level), lit);
	}
	// LIGHT_COLOR is pre-multiplied by PI; divide so the lit band matches the
	// brightness of a StandardMaterial3D under the same light. Albedo is
	// applied by the engine after light() runs.
	if (!LIGHT_IS_DIRECTIONAL) {
		ramp = mix(vec3(0.0), ramp, lit) * reach;
	}
	DIFFUSE_LIGHT += ramp * LIGHT_COLOR / PI;

	// Hard toon specular dot (Blinn-Phong half vector, stepped).
	vec3 half_vec = normalize(LIGHT + VIEW);
	float n_dot_h = max(dot(NORMAL, half_vec), 0.0);
	float spec_edge = 1.0 - specular_size;
	float spec = smoothstep(spec_edge - band_softness, spec_edge + band_softness, n_dot_h);
	spec *= lit * specular_strength;

	// Rim: fresnel-like term, gated to the lit hemisphere so the dark side
	// stays flat (classic anime back-light look). Softened so it reads as a
	// glow rather than a second outline.
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_t = 1.0 - n_dot_v;
	float rim_edge = 1.0 - rim_width;
	float rim = smoothstep(rim_edge - rim_softness, rim_edge + rim_softness, rim_t);
	rim *= lit * rim_strength;

	SPECULAR_LIGHT += (spec + rim * rim_color.rgb) * reach * LIGHT_COLOR / PI;
}
