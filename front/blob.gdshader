shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 blob_color : source_color = vec4(0.09, 0.13, 0.1, 0.5);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float soft = 1.0 - smoothstep(0.2, 1.0, length(p));
	ALBEDO = blob_color.rgb;
	ALPHA = soft * blob_color.a;
}
