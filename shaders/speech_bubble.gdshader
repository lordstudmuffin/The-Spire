// Speech bubble behind an NPC's bark line: a billboarded rounded panel with
// a thin bright rim and a small tail pointing down at the speaker. The quad
// is sized by NpcBark to fit its Label3D; `size` is that size in metres.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 size = vec2(2.0, 0.5);
uniform vec4 fill : source_color = vec4(0.06, 0.08, 0.14, 0.82);
uniform vec4 rim : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform float fade = 1.0;
const float TAIL = 0.12;   // tail height in metres, below the panel

void vertex() {
	// Billboard, keeping the mesh's own scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	// Quad spans the panel plus the tail strip under it.
	vec2 full = vec2(size.x, size.y + TAIL);
	vec2 p = (UV - 0.5) * full;
	p.y = -p.y;
	vec2 c = vec2(0.0, TAIL * 0.5);  // panel centre sits above the tail
	float d = rbox(p - c, size * 0.5, min(0.12, size.y * 0.45));
	// Tail: a small triangle under the panel's centre.
	vec2 t = p - vec2(0.0, -full.y * 0.5);
	float tri = max(abs(t.x) * 1.4 - (t.y), t.y - TAIL - 0.01);
	d = min(d, tri);
	float aa = fwidth(d) * 1.2;
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = 1.0 - smoothstep(0.0, aa * 1.5, abs(d + 0.012));
	vec3 col = mix(fill.rgb, rim.rgb, edge * rim.a);
	ALBEDO = col;
	ALPHA = max(inside * fill.a, edge * rim.a) * fade;
}
