shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;

uniform float outline_width : hint_range(0.0, 0.5) = 0.07;
uniform vec4 outline_color : source_color = vec4(0.10, 0.08, 0.20, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
