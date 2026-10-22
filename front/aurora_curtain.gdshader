shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color_a : source_color = vec4(0.96, 0.72, 0.86, 1.0);
uniform vec4 color_b : source_color = vec4(0.62, 0.88, 0.98, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.12;
uniform float density : hint_range(0.5, 8.0) = 2.5;
uniform float intensity : hint_range(0.0, 3.0) = 0.55;
uniform float seed : hint_range(0.0, 100.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float t = TIME * speed + seed;
	vec2 uv = UV;

	float warp = value_noise(vec2(uv.x * density + seed, t)) * 2.0 - 1.0;
	float ribbons = sin(uv.x * density * 6.2831 + t * 2.0 + warp * 3.0) * 0.5 + 0.5;
	ribbons *= sin(uv.x * density * 3.1 - t * 1.3 + warp * 2.0) * 0.5 + 0.5;

	float v = clamp(uv.y, 0.0, 1.0);
	float bottom_fade = smoothstep(0.0, 0.5, v);
	float top_fade = smoothstep(1.0, 0.55, v);
	float vertical_fade = bottom_fade * top_fade;
	float horizontal_fade = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	float glow = ribbons * vertical_fade * horizontal_fade;

	vec3 col = mix(color_a.rgb, color_b.rgb, value_noise(vec2(uv.x * 3.0 + seed, t * 0.5)));

	ALBEDO = col;
	ALPHA = clamp(glow * intensity, 0.0, 1.0);
}
