// Experiment 004: one northern-lights curtain. An emissive, additive ribbon
// (QuadMesh in the XY plane, folded along Z in the vertex stage) with a bright
// green lower edge fading to violet, moving vertical rays and a slow pulse.
// NorthernSky places it in the fog band at the top of the frame.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float strength = 0.0;
uniform float seed = 0.0;
uniform float fold = 2.4;
uniform vec3 col_low : source_color = vec3(0.3, 1.0, 0.6);
uniform vec3 col_high : source_color = vec3(0.6, 0.32, 1.0);

void vertex() {
	float t = TIME * 0.035 + seed;
	VERTEX.z += sin(UV.x * 9.0 + t * 2.2) * fold + sin(UV.x * 23.0 - t * 3.7) * fold * 0.35;
}

void fragment() {
	float x = UV.x;
	float y = 1.0 - UV.y;
	float t = TIME;
	float r1 = texture(noise_tex, vec2(x * 2.3 + t * 0.006 + seed, 0.37)).r;
	float r2 = texture(noise_tex, vec2(x * 7.1 - t * 0.011 + seed * 1.7, 0.71)).r;
	float rays = smoothstep(0.3, 0.75, r1 * 0.6 + r2 * 0.4);
	float yy = y - 0.03 * sin(x * 31.0 + t * 0.4 + seed * 5.0);
	float lower = smoothstep(0.0, 0.05, yy) * exp(-max(yy, 0.0) * 2.2);
	float ends = smoothstep(0.0, 0.2, x) * smoothstep(1.0, 0.8, x);
	float pulse = 0.72 + 0.28 * sin(t * 0.45 + x * 5.0 + seed * 3.0);
	vec3 c = mix(col_low, col_high, smoothstep(0.1, 0.7, yy));
	ALBEDO = c * 1.6;
	ALPHA = clamp(lower * (0.3 + 0.7 * rays) * ends * pulse * strength, 0.0, 1.0);
}
