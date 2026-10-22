shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 puff_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float soft = 1.0 - smoothstep(0.25, 1.0, length(p));
	ALBEDO = puff_color.rgb;
	ALPHA = soft * puff_color.a * alpha;
}
