// "You are dead" overlay (HUD.show_death, styled by UITheme.death_screen).
// The screen behind drains to a cold grey and darkens toward the edges, and a
// dark system band with red rules crosses the middle for the message. The
// strength is the ColorRect's own alpha (HUD tweens color:a 0 -> 0.62), so
// the existing fade keeps working; `full_alpha` is that end value.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float full_alpha = 0.62;
uniform vec4 rule_color : source_color = vec4(0.92, 0.2, 0.18, 1.0);
uniform float band_half = 0.075;

void fragment() {
	float k = clamp(COLOR.a / full_alpha, 0.0, 1.0);
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(g) * vec3(0.86, 0.9, 1.0) * 0.6;
	vec2 d = (UV - 0.5) * vec2(1.7, 1.0);
	grey *= 1.0 - 0.65 * smoothstep(0.3, 0.95, length(d));
	// The band: opens from the centre line as k rises.
	float bh = band_half * smoothstep(0.35, 1.0, k);
	float dy = abs(UV.y - 0.5);
	float inside = 1.0 - smoothstep(bh - 0.002, bh, dy);
	float fade_x = smoothstep(0.0, 0.3, UV.x) * (1.0 - smoothstep(0.7, 1.0, UV.x));
	grey = mix(grey, vec3(0.03, 0.02, 0.035), inside * 0.78 * fade_x);
	float rule = (1.0 - smoothstep(0.0, 0.0022, abs(dy - bh))) * step(0.001, bh) * fade_x;
	grey = mix(grey, rule_color.rgb, rule);
	COLOR = vec4(grey, k);
}
