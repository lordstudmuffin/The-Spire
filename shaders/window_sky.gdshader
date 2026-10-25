// What you see through a cottage window: a soft sky gradient with a few
// drifting clouds, unshaded, blended between a day and a night palette by
// `night` (DayNight drives it through WorldArt.set_night_tint).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 day_top : source_color = vec4(0.30, 0.56, 0.92, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.70, 0.84, 0.98, 1.0);
uniform vec4 night_top : source_color = vec4(0.06, 0.08, 0.22, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.16, 0.2, 0.4, 1.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 0.12;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);  // PlaneMesh UV.y runs top to bottom
	vec3 top = mix(day_top.rgb, night_top.rgb, night);
	vec3 hor = mix(day_horizon.rgb, night_horizon.rgb, night);
	vec3 col = mix(hor, top, smoothstep(0.1, 0.9, uv.y));
	// Clouds drift across by day; stars prick through by night.
	float c = vnoise(uv * vec2(3.0, 2.0) + vec2(TIME * 0.02, 0.0));
	c = smoothstep(0.55, 0.75, c + 0.2 * vnoise(uv * 7.0 + TIME * 0.03));
	col = mix(col, vec3(0.97, 0.96, 0.95), c * 0.8 * (1.0 - night));
	float star = step(0.995, hash12(floor(uv * 90.0))) * night;
	col += vec3(0.9, 0.95, 1.0) * star;
	// Distant hills along the sill.
	float hill = smoothstep(0.0, 0.02, uv.y - (0.18 + 0.08 * vnoise(uv.xx * 4.0)));
	col = mix(mix(vec3(0.46, 0.68, 0.4), vec3(0.08, 0.1, 0.2), night), col, hill);
	ALBEDO = col;
	EMISSION = col * mix(glow, 0.1, night);
}
