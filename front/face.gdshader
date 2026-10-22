shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 dot_color : source_color = vec4(0.06, 0.05, 0.12, 1.0);
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 look_offset = vec2(0.0);
uniform float blink = 0.0;
uniform float wink = 0.0;
uniform float wink_side = -1.0;
uniform float happy = 0.0;
uniform float wide = 0.0;
uniform float squint = 0.0;
uniform float smile = 0.0;
uniform float mouth_open = 0.0;
uniform float glint_amount = 1.0;

float cover(float d) {
	return 1.0 - smoothstep(-0.009, 0.009, d);
}

float eye_dot(vec2 e, float r, float squash_y) {
	return length(vec2(e.x, e.y / max(squash_y, 0.02))) - r;
}

float eye_arc(vec2 e) {
	float d = abs(length(e - vec2(0.0, -0.14)) - 0.22) - 0.030;
	return max(d, -(e.y + 0.14));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;

	float r = 0.17 * (1.0 + wide * 0.42);
	vec2 off = look_offset * 0.09;

	float b0 = blink;
	float b1 = blink;
	if (wink_side >= 0.0) {
		if (wink_side < 0.5) {
			b0 = max(b0, wink);
		} else {
			b1 = max(b1, wink);
		}
	}
	float sy0 = 1.0 - squint * 0.55 - b0 * 0.93;
	float sy1 = 1.0 - squint * 0.55 - b1 * 0.93;

	vec2 e0 = p - vec2(-0.42, 0.30) - off;
	vec2 e1 = p - vec2(0.42, 0.30) - off;

	float d0 = mix(eye_dot(e0, r, sy0), eye_arc(e0), happy);
	float d1 = mix(eye_dot(e1, r, sy1), eye_arc(e1), happy);
	float d_eye = min(d0, d1);

	vec2 m = p - vec2(0.0, -0.26);
	float curve = m.y - (smile * 1.6 * m.x * m.x);
	float d_mouth = abs(curve) - 0.024;
	d_mouth = max(d_mouth, abs(m.x) - 0.30);
	float d_o = length(m / vec2(0.15, 0.19)) - 1.0;
	d_mouth = mix(d_mouth, d_o * 0.15, mouth_open);

	vec3 col = vec3(0.0);
	float alpha = 0.0;

	float eye_a = cover(d_eye) * dot_color.a;
	col = mix(col, dot_color.rgb, eye_a);
	alpha = max(alpha, eye_a);

	vec2 g0 = e0 - vec2(-0.052, 0.058);
	vec2 g1 = e1 - vec2(-0.052, 0.058);
	float g_a = cover(min(length(g0), length(g1)) - 0.029)
		* (1.0 - happy) * (1.0 - b0) * (1.0 - b1) * glint_amount * glint_color.a;
	col = mix(col, glint_color.rgb, g_a);
	alpha = max(alpha, g_a);

	float mouth_a = cover(d_mouth) * dot_color.a;
	col = mix(col, dot_color.rgb, mouth_a);
	alpha = max(alpha, mouth_a);

	ALBEDO = col;
	ALPHA = alpha;
}
