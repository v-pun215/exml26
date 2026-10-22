shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 streak_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float along = pow(clamp(UV.x, 0.0, 1.0), 1.6);
	float across = abs(UV.y - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.15, 1.0, across);
	ALBEDO = streak_color.rgb;
	ALPHA = along * edge * strength * streak_color.a;
}
