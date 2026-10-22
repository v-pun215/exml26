shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform float ring_radius : hint_range(0.0, 1.0) = 0.0;
uniform float ring_thickness : hint_range(0.01, 0.5) = 0.09;
uniform float ring_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = abs(length(UV - 0.5) * 2.0 - ring_radius);
	float band = 1.0 - smoothstep(0.0, ring_thickness, d);
	ALBEDO = ring_color.rgb;
	ALPHA = band * ring_alpha * ring_color.a;
}
