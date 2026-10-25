// Inverted-hull outline pass. Godot 4.3+.
// Use as next_pass on the toon material (or on a duplicate MeshInstance3D):
// the mesh is redrawn with front faces culled and every vertex pushed out,
// so only a thin shell shows around the silhouette.
// The push uses CUSTOM0.xyz when the mesh carries it: normals averaged over
// every vertex sharing a position (AssetLib.with_outline_normals), so the
// shell stays closed on flat-shaded low-poly props instead of splitting into
// dashes at every hard edge. The offset is applied in view space, so the
// line is `outline_width` metres at `reference_distance` whatever the
// object's scale (a 6x building no longer gets a 6x line).
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.07, 0.05, 0.1, 1.0);
// Thickness in metres at `reference_distance` metres from the camera. It
// grows with distance (clamped) so far characters keep a visible ink line
// and close ones do not turn into blobs.
uniform float outline_width : hint_range(0.0, 0.2, 0.001) = 0.02;
uniform float reference_distance : hint_range(0.5, 30.0, 0.1) = 4.0;
uniform float min_scale : hint_range(0.1, 2.0, 0.05) = 0.55;
uniform float max_scale : hint_range(1.0, 6.0, 0.05) = 1.8;

void vertex() {
	vec3 n = CUSTOM0.xyz;
	if (dot(n, n) < 0.01) {
		n = NORMAL;
	}
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 nv = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
	float dist = -view.z;
	float k = clamp(dist / reference_distance, min_scale, max_scale);
	view.xyz += nv * outline_width * k;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
