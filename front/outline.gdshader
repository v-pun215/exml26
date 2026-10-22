shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.10, 0.08, 0.20, 1.0);

void fragment() {
	ALBEDO = outline_color.rgb;
}
