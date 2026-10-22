shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

uniform float sweep_period : hint_range(1.0, 30.0) = 6.0;
uniform float sweep_amount : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	float cycle = fract(TIME / sweep_period + UV.x * 0.01 + UV.y * 0.006);
	float sweep = smoothstep(0.0, 0.05, cycle) * (1.0 - smoothstep(0.05, 0.22, cycle));

	ALBEDO = COLOR.rgb * (1.0 + sweep * sweep_amount);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
