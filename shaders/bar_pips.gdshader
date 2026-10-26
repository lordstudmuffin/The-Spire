// Boss HP bar stack (MobPlate.set_bars): one slanted pip per HP bar under
// the main bar. Bars still to come are pale glass, the one being chipped
// glows amber, spent ones are dark. Billboarded like hp_bar.gdshader.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform int bars = 4;
uniform int current = 4;          // bar being chipped now (bars..1), 0 = dead
uniform float aspect = 8.0;       // quad width / height
uniform float gap = 0.25;         // gap between pips, in pip heights
uniform vec4 full_color : source_color = vec4(0.82, 0.92, 1.0, 0.95);
uniform vec4 now_color : source_color = vec4(1.0, 0.68, 0.2, 1.0);
uniform vec4 spent_color : source_color = vec4(0.06, 0.07, 0.12, 0.7);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float n = float(max(bars, 1));
	// Pip index from the left; a slant like the main bar.
	float x = uv.x * aspect + (uv.y - 0.5) * 0.36;
	float cell = aspect / n;
	float i = floor(x / cell);
	float fx = x - i * cell;
	float w = cell - gap;
	if (i < 0.0 || i >= n || fx > w) {
		discard;
	}
	// Pip order: leftmost is the last bar (1), rightmost the first (bars).
	float bar_no = i + 1.0;
	vec4 c = spent_color;
	if (bar_no < float(current)) {
		c = full_color;
	} else if (bar_no == float(current)) {
		c = now_color;
	}
	float edge = min(min(fx, w - fx), min(uv.y, 1.0 - uv.y) * 1.0);
	float rim = 1.0 - smoothstep(0.0, 0.12, edge);
	ALBEDO = mix(c.rgb, vec3(1.0), rim * 0.35);
	ALPHA = c.a;
}
