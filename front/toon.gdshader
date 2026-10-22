shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.5;
uniform float cap_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vertex_color = false;

varying float v_cap;

void vertex() {
	v_cap = smoothstep(0.34, 0.46, normalize(VERTEX).y);
}

void fragment() {
	vec3 col = base_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	if (cap_amount > 0.001) {
		col = mix(col, col * 0.5 + vec3(0.02, 0.02, 0.06), v_cap * cap_amount);
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	RIM = rim_strength;
	RIM_TINT = rim_tint;
	EMISSION = emission_color.rgb * emission_strength;
}
