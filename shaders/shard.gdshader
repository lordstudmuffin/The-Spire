// Crystal shard for the polygon-shatter death (VFX.shatter). Drawn through a
// MultiMesh: per-instance COLOR carries the tint and the fade (alpha), and
// INSTANCE_CUSTOM.x a 0..1 sparkle phase. The mesh is a flat triangle whose
// UV.xy are two of its barycentric coordinates, so the facet edges can glow
// white while the face stays a translucent tinted glass. Unshaded and above
// 1.0 on purpose so the shards bloom under the glow pass.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float edge_width = 0.09;
uniform float core_alpha = 0.7;
uniform float brightness = 1.35;

varying float sparkle;

void vertex() {
	sparkle = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 bary = vec3(UV.x, UV.y, 1.0 - UV.x - UV.y);
	float d = min(bary.x, min(bary.y, bary.z));
	float edge = 1.0 - smoothstep(0.0, edge_width, d);
	// Facing ratio: shards flare as they tumble toward the camera.
	float facing = abs(dot(normalize(NORMAL), VIEW));
	float glint = pow(facing, 6.0) * (0.6 + 0.4 * sin(TIME * 22.0 + sparkle * 40.0));
	vec3 tint = COLOR.rgb;
	vec3 col = mix(tint * brightness, vec3(1.0) * brightness * 1.3, clamp(edge * 0.7 + glint * 0.6, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = COLOR.a * clamp(core_alpha + edge * 0.45 + glint * 0.4, 0.0, 1.0);
}
