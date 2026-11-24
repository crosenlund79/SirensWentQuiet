// Experiment 004: a fireplace flame sheet. Additive, unshaded; a tongue-shaped
// mask eaten by noise that scrolls upward, hot yellow at the root to orange
// and red at the tips. `lit` fades it out when the fire is put out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float lit = 1.0;
uniform float seed = 0.0;

void vertex() {
	// a little sway at the tips
	float y = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 3.1 + seed * 7.0) * 0.03 * y * y;
}

void fragment() {
	float x = UV.x - 0.5;
	float y = 1.0 - UV.y;
	float t = TIME;
	float n = texture(noise_tex, vec2(UV.x * 0.9 + seed, y * 0.7 - t * 0.55)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 2.1 - seed, y * 1.4 - t * 0.9)).r;
	float width = mix(0.46, 0.02, pow(y, 0.8));
	float body = smoothstep(width, width * 0.35, abs(x + (n2 - 0.5) * 0.25 * y));
	float a = body * smoothstep(0.0, 0.08, y) * smoothstep(1.0, 0.55, y + (n - 0.5) * 0.6);
	a *= smoothstep(0.25, 0.55, n * 0.7 + n2 * 0.5 + (1.0 - y) * 0.35);
	vec3 hot = vec3(1.0, 0.85, 0.45);
	vec3 mid = vec3(1.0, 0.45, 0.1);
	vec3 tip = vec3(0.7, 0.12, 0.03);
	vec3 c = mix(hot, mid, smoothstep(0.1, 0.5, y));
	c = mix(c, tip, smoothstep(0.5, 0.95, y));
	ALBEDO = c * 2.2;
	ALPHA = clamp(a * lit, 0.0, 1.0);
}
