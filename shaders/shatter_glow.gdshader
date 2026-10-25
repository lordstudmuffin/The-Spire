// Overlay put on every mesh of a body for the instant before it shatters:
// a hard white-cyan sheen with a faceted (flat-normal) rim, so the model
// reads as turning to glass. Applied as material_overlay, so it works on
// skinned meshes and keeps the body's own materials underneath.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Flat facet normal from screen-space derivatives: reads as polygons.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float rim = 1.0 - abs(dot(n, VIEW));
	float facet = fract(dot(n, vec3(3.1, 5.7, 2.3)) * 4.0);
	vec3 c = glow_color.rgb * (0.55 + rim * 1.6 + facet * 0.25);
	ALBEDO = c * amount;
	ALPHA = amount;
}
