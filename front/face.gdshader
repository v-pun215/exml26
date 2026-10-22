shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 dot_color : source_color = vec4(0.06, 0.05, 0.12, 1.0);
uniform vec4 lash_color : source_color = vec4(0.13, 0.08, 0.15, 1.0);
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
uniform float lash_amount : hint_range(0.0, 2.0) = 1.0;
uniform float brow_amount : hint_range(0.0, 2.0) = 1.0;
uniform float brow_raise = 0.0;
uniform float brow_tilt = 0.0;

float cover(float d) {
	return 1.0 - smoothstep(-0.009, 0.009, d);
}

float sd_tapered_segment(vec2 p, vec2 a, vec2 b, float wa, float wb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	float w = mix(wa, wb, h);
	return length(pa - ba * h) - w;
}

float eye_dot(vec2 e, float r, float squash_y) {
	return length(vec2(e.x, e.y / max(squash_y, 0.02))) - r;
}

float eye_arc(vec2 e) {
	float d = abs(length(e - vec2(0.0, -0.14)) - 0.22) - 0.030;
	return max(d, -(e.y + 0.14));
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

float lid_lash(vec2 eq, float r, float side) {
	float dl = length(eq) - r;
	float outer = clamp(side * eq.x / max(r, 0.001), 0.0, 1.0);
	float band = 1.0 - smoothstep(0.004, 0.024, abs(dl - 0.024));
	float top = smoothstep(0.06 * r, 0.40 * r, eq.y);
	return band * top * outer;
}

float flick_lash(vec2 eq, float r, float side) {
	vec2 corner = vec2(side * 0.66 * r, 0.60 * r);
	vec2 tip_a = corner + vec2(side * 0.24 * r, 0.34 * r);
	vec2 tip_b = corner + vec2(side * 0.40 * r, 0.12 * r);
	float a = 1.0 - smoothstep(0.0, 0.020, sd_segment(eq, corner, tip_a));
	float b = 1.0 - smoothstep(0.0, 0.016, sd_segment(eq, corner, tip_b));
	return max(a, b);
}

float brow_stroke(vec2 e, float r, float side) {
	float y = r * (1.66 + brow_raise);
	vec2 outer_p = vec2(side * 1.0 * r, y + brow_tilt * 1.0 * r);
	vec2 inner_p = vec2(-side * 1.0 * r, y - brow_tilt * 1.0 * r);
	return sd_tapered_segment(e, inner_p, outer_p, 0.16 * r, 0.24 * r);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;

	float r = 0.215 * (1.0 + wide * 0.42);
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

	vec2 e0 = p - vec2(-0.40, 0.26) - off;
	vec2 e1 = p - vec2(0.40, 0.26) - off;
	vec2 bp0 = p - vec2(-0.40, 0.26);
	vec2 bp1 = p - vec2(0.40, 0.26);

	float d0 = mix(eye_dot(e0, r, sy0), eye_arc(e0), happy);
	float d1 = mix(eye_dot(e1, r, sy1), eye_arc(e1), happy);
	float d_eye = min(d0, d1);

	vec2 eq0 = vec2(e0.x, e0.y / max(sy0, 0.02));
	vec2 eq1 = vec2(e1.x, e1.y / max(sy1, 0.02));
	float lash = max(lid_lash(eq0, r, -1.0), lid_lash(eq1, r, 1.0));
	float flick = max(flick_lash(eq0, r, -1.0), flick_lash(eq1, r, 1.0));
	float brow = max(cover(brow_stroke(bp0, r, -1.0)), cover(brow_stroke(bp1, r, 1.0)));

	vec2 m = p - vec2(0.0, -0.30);
	float curve = m.y - (smile * 1.9 * m.x * m.x);
	float d_mouth = abs(curve) - 0.034;
	d_mouth = max(d_mouth, abs(m.x) - 0.34);
	float d_o = length(m / vec2(0.16, 0.20)) - 1.0;
	d_mouth = mix(d_mouth, d_o * 0.15, mouth_open);

	vec3 col = vec3(0.0);
	float alpha = 0.0;

	float lash_a = max(lash, flick) * lash_amount * lash_color.a;
	col = mix(col, lash_color.rgb, lash_a);
	alpha = max(alpha, lash_a);

	float brow_a = brow * brow_amount * lash_color.a;
	col = mix(col, lash_color.rgb, brow_a);
	alpha = max(alpha, brow_a);

	float eye_a = cover(d_eye) * dot_color.a;
	col = mix(col, dot_color.rgb, eye_a);
	alpha = max(alpha, eye_a);

	vec2 g0 = e0 - vec2(-0.048, 0.052);
	vec2 g1 = e1 - vec2(-0.048, 0.052);
	float g_a = cover(min(length(g0), length(g1)) - 0.021)
		* (1.0 - happy) * (1.0 - b0) * (1.0 - b1) * glint_amount * glint_color.a;
	col = mix(col, glint_color.rgb, g_a);
	alpha = max(alpha, g_a);

	float mouth_a = cover(d_mouth) * dot_color.a;
	col = mix(col, dot_color.rgb, mouth_a);
	alpha = max(alpha, mouth_a);

	ALBEDO = col;
	ALPHA = alpha;
}
