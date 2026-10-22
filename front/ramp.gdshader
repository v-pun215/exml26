shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 0.88, 0.48, 1.0);
uniform vec4 rung_color : source_color = vec4(0.84, 0.65, 0.33, 1.0);
uniform float rung_spacing : hint_range(0.5, 8.0) = 1.8;
uniform float rung_depth : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float f = fract(UV.x / rung_spacing);
	float edge = min(f, 1.0 - f);
	float line = 1.0 - smoothstep(0.0, 0.10, edge);
	vec3 col = mix(base_color.rgb, rung_color.rgb, line * rung_depth);
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
