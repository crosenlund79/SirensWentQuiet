// One horizontal slice of the lot-edge fog bank (FogBoundary). Owner: E.
// Several slices stacked at rising heights read as a soft volume from the
// angled game camera, and still render under software Vulkan. Density comes
// from the signed distance to the lot (thicker with distance), the bank's
// height profile and two drifting noise octaves. Soft where it meets geometry.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 lot_rect = vec4(-4.5, -3.5, 18.5, 12.5);   // x0, z0, x1, z1
uniform float layer_y = 0.0;          // world height of this slice
uniform float layer_t = 0.0;          // 0 bottom .. 1 top
uniform float layer_alpha = 0.3;      // opacity at full density
uniform float floor_alpha = 0.0;      // >0 on the lowest slice: opaque far floor
uniform float seed_offset = 0.0;
uniform vec2 wind = vec2(0.32, 0.12);
uniform vec3 day_low : source_color = vec3(0.55, 0.58, 0.62);
uniform vec3 day_high : source_color = vec3(0.80, 0.82, 0.85);
uniform vec3 night_low : source_color = vec3(0.05, 0.065, 0.11);
uniform vec3 night_high : source_color = vec3(0.17, 0.21, 0.31);
uniform float night = 0.0;
uniform vec3 invite_pos = vec3(0.0, -100.0, 0.0);   // the player, while near the edge
uniform float invite = 0.0;
uniform vec4 lane_a = vec4(0.0);      // x0, z0, x1, z1: paths that run on into the fog
uniform vec4 lane_b = vec4(0.0);
uniform float lane_push = 1.7;

varying vec3 wpos;

float sd_rect(vec2 p, vec4 r) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 h = (r.zw - r.xy) * 0.5;
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float lane(vec2 p, vec4 r) {
	if (r.z <= r.x) {
		return 0.0;
	}
	return 1.0 - smoothstep(-0.2, 0.6, sd_rect(p, r));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz;
	float t = TIME;
	float n1 = texture(noise_tex, q * 0.043 + wind * t * 0.018 + vec2(seed_offset, seed_offset * 0.37)).r;
	float n2 = texture(noise_tex, q * 0.105 - wind.yx * t * 0.034 + vec2(seed_offset * 1.9, 0.21)).r;
	float n3 = texture(noise_tex, q * 0.021 + vec2(t * 0.004, -t * 0.003) + 0.5).r;
	float n = clamp(n1 * 0.55 + n2 * 0.3 + n3 * 0.35 - 0.1, 0.0, 1.0);

	float lanes = max(lane(q, lane_a), lane(q, lane_b));
	float d = sd_rect(q, lot_rect) - lanes * lane_push;   // metres beyond the lot edge
	// The bank rises away from the lot; ragged, slowly breathing top.
	float top = mix(1.7, 7.4, smoothstep(0.0, 14.0, d)) + (n - 0.45) * 3.0;
	float in_bank = 1.0 - smoothstep(top - 1.4, top + 0.3, layer_y);
	float edge = smoothstep(-0.8 + (n2 - 0.5) * 1.8, 3.4, d);
	float dens = edge * in_bank * mix(0.55, 1.35, n);
	float a = clamp(dens * layer_alpha, 0.0, 1.0);
	a = max(a, floor_alpha * smoothstep(4.0, 10.0, d));

	// Keep the player readable at the edge.
	float pd = length(q - invite_pos.xz);
	a *= 1.0 - invite * 0.55 * exp(-pd * pd / 3.0) * (1.0 - layer_t);

	// Soft where the slice cuts through geometry (car, trees, the house, enemies);
	// the softening distance scales with the slice height so the low slices
	// (and the opaque far floor) are not eaten by the ground just below them.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -view.z / view.w;
	a *= clamp((scene_z + VERTEX.z) / clamp(layer_y * 0.5, 0.03, 0.7), 0.0, 1.0);

	vec3 lo = mix(day_low, night_low, night);
	vec3 hi = mix(day_high, night_high, night);
	// Lit tops, shadowed hollows: higher and denser reads brighter.
	float lit = clamp(layer_t * 0.75 + (n - 0.35) * 0.7, 0.0, 1.0);
	vec3 col = mix(lo, hi, lit);
	col *= mix(1.0, 1.12, lanes * (1.0 - night * 0.5));
	col += invite * exp(-pd * pd / 8.0) * mix(vec3(0.06, 0.055, 0.045), vec3(0.05, 0.06, 0.09), night);
	ALBEDO = col;
	ALPHA = a;
}
