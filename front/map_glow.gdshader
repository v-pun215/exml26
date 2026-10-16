shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.58, 0.46, 0.96, 1.0);
uniform float plane_size = 400.0;
uniform float arena_half = 100.0;
uniform float falloff : hint_range(2.0, 120.0) = 26.0;
uniform float intensity : hint_range(0.0, 3.0) = 0.9;
uniform float corner_round : hint_range(0.0, 1.0) = 0.38;

float sd_rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * plane_size;

	float r = arena_half * corner_round;
	float d = sd_rounded_box(p, vec2(arena_half), r);

	float band = exp(-abs(d) / falloff);
	float breathe = 0.86 + 0.14 * sin(TIME * 0.45);

	ALBEDO = glow_color.rgb;
	ALPHA = clamp(band * intensity * breathe, 0.0, 1.0);
}
