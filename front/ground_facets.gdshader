shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

uniform vec4 turf_color : source_color = vec4(0.44, 0.74, 0.24, 1.0);
uniform vec4 turf_color_alt : source_color = vec4(0.37, 0.67, 0.22, 1.0);
uniform vec4 line_color : source_color = vec4(0.99, 0.9, 0.62, 1.0);
uniform float stripe_width : hint_range(2.0, 60.0) = 18.0;
uniform float ring_radius : hint_range(0.0, 200.0) = 54.0;
uniform float ring_width : hint_range(0.5, 12.0) = 1.8;
uniform float sweep_period : hint_range(1.0, 30.0) = 6.0;
uniform float sweep_amount : hint_range(0.0, 0.5) = 0.10;

void fragment() {
	float stripe = step(0.0, sin(UV.x * PI / stripe_width));
	vec3 base = mix(turf_color_alt.rgb, turf_color.rgb, stripe);

	float d = abs(length(UV) - ring_radius);
	float ring = 1.0 - smoothstep(ring_width, ring_width + 1.5, d);
	base = mix(base, line_color.rgb, ring * 0.65);

	float cycle = fract(TIME / sweep_period + (UV.x + UV.y) * 0.008);
	float sweep = smoothstep(0.0, 0.05, cycle) * (1.0 - smoothstep(0.05, 0.22, cycle));

	ALBEDO = base * (1.0 + sweep * sweep_amount);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
