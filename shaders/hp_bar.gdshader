// World-space mob HP bar (MobPlate): a slanted glass frame with the fill
// banded green / yellow / red by remaining HP and a white "chip" that trails
// the fill after a hit. Billboarded, unshaded, always drawn over the world.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform float hp : hint_range(0.0, 1.0) = 1.0;
uniform float chip : hint_range(0.0, 1.0) = 1.0;
uniform float slant = 0.18;          // parallelogram lean, in bar heights
uniform vec4 frame_color : source_color = vec4(0.05, 0.06, 0.1, 0.78);
uniform vec4 rim_color : source_color = vec4(0.85, 0.9, 1.0, 0.9);
uniform vec4 good : source_color = vec4(0.36, 0.92, 0.42, 1.0);
uniform vec4 warn : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform vec4 bad : source_color = vec4(1.0, 0.26, 0.24, 1.0);
uniform float aspect = 10.0;         // quad width / height

void vertex() {
	// Billboard keeping the quad's own scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y;
	// Lean the bar: shift x by height so edges become parallelograms.
	float x = uv.x + (uv.y - 0.5) * slant * 2.0 / aspect;
	float edge_x = min(x, 1.0 - x) * aspect;   // distance to the side, in bar heights
	float edge_y = min(uv.y, 1.0 - uv.y);
	if (x < 0.0 || x > 1.0) {
		discard;
	}
	float border = 0.16;
	float inner = step(border, edge_y) * step(border, edge_x);
	// Inner coordinate 0..1 across the fill area.
	float fx = (x * aspect - border) / (aspect - 2.0 * border);
	vec3 fill = hp > 0.5 ? good.rgb : (hp > 0.2 ? warn.rgb : bad.rgb);
	// Glassy vertical shading on the fill.
	float shade = 0.82 + 0.35 * smoothstep(0.2, 0.85, uv.y);
	vec4 col = frame_color;
	if (inner > 0.5) {
		if (fx <= hp) {
			col = vec4(fill * shade, 1.0);
			// Thin bright line along the top of the fill.
			col.rgb += vec3(0.35) * smoothstep(0.7, 0.78, uv.y) * (1.0 - smoothstep(0.78, 0.84, uv.y));
		} else if (fx <= chip) {
			col = vec4(vec3(1.0, 0.96, 0.9) * 0.95, 0.95);
		} else {
			col = vec4(frame_color.rgb * 1.4, frame_color.a);
		}
	} else {
		// Frame rim: brighter on the outermost pixels.
		float r = 1.0 - smoothstep(0.0, border * 0.6, min(edge_y, edge_x));
		col = mix(frame_color, rim_color, r * 0.7);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
