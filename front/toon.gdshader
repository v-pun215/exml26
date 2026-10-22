shader_type spatial;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.72;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.16;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.55;
uniform bool use_vertex_color = false;

void fragment() {
	vec3 col = base_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	RIM = rim_strength;
	RIM_TINT = rim_tint;
	EMISSION = emission_color.rgb * emission_strength;
}
