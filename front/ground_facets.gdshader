shader_type spatial;
render_mode cull_disabled;

uniform float flash_period : hint_range(1.0, 30.0) = 7.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.28;
uniform vec4 flash_tint : source_color = vec4(0.72, 0.92, 0.6, 1.0);

void fragment() {
	float phase = UV.x;
	float rate = mix(0.55, 1.75, UV.y);

	float cycle = fract(TIME / flash_period * rate + phase);
	float pulse = smoothstep(0.0, 0.10, cycle) * (1.0 - smoothstep(0.10, 0.34, cycle));

	vec3 base = COLOR.rgb;
	vec3 lit = mix(base, flash_tint.rgb, 0.55) * (1.0 + flash_amount);

	ALBEDO = mix(base, lit, pulse);
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
