// Exp 012 (V): the fog of war as one full-screen pass (FogOfWar). Every
// pixel's world position comes from the depth buffer; its plan XZ picks the
// coarse cells of FowGrid:
//   visible                  untouched (light, night and shadows as rendered)
//   discovered, not visible  mixed toward a dark, cold grey: remembered,
//                            darkened and drained of colour
//   undiscovered             a dense drifting fog, nearly opaque
// The visible layer blends from the previous update to the current one
// (`blend`), so the edge moves smoothly between the ~10 Hz updates.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D disc_tex : filter_linear, repeat_disable;
uniform sampler2D vis_tex : filter_linear, repeat_disable;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 area = vec4(-11.25, -10.25, 37.0, 30.0);   // FowGrid.AREA: x, z, width, depth
uniform float blend = 1.0;
uniform vec3 memory_color = vec3(0.03, 0.035, 0.05);
uniform float memory_alpha = 0.62;
uniform vec3 fog_color = vec3(0.02, 0.025, 0.045);
uniform float fog_alpha = 0.94;
uniform float near_floor = -100.0;   // pixels below this height are left alone (nothing)
uniform float time_scale = 1.0;
uniform int debug_mode = 0;          // 1: show (discovered, visible, depth) as colours

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 wp = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	if (depth <= 0.00001) {
		// the sky / clear colour: use where the view ray meets the ground
		vec3 o = INV_VIEW_MATRIX[3].xyz;
		vec3 d = normalize(wp - o);
		wp = o + d * (d.y < -0.001 ? -o.y / d.y : 200.0);
	}
	vec2 uv = (wp.xz - area.xy) / area.zw;
	bool inside = uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0;
	float disc = inside ? texture(disc_tex, uv).r : 0.0;
	float vis = inside ? mix(texture(prev_tex, uv).r, texture(vis_tex, uv).r, blend) : 0.0;
	disc = smoothstep(0.15, 0.85, disc);
	vis = smoothstep(0.2, 0.8, vis);
	float t = TIME * time_scale;
	float n = texture(noise_tex, wp.xz * 0.045 + vec2(t * 0.011, t * 0.007)).r;
	float n2 = texture(noise_tex, wp.xz * 0.11 - vec2(t * 0.017, -t * 0.009)).r;
	float wisps = clamp(n * 0.7 + n2 * 0.5, 0.0, 1.0);
	vec3 fog = fog_color * (0.75 + 0.6 * wisps);
	float a_fog = clamp(fog_alpha - 0.08 + 0.12 * wisps, 0.0, 1.0);
	float undisc = 1.0 - disc;
	ALBEDO = mix(memory_color, fog, undisc);
	ALPHA = (1.0 - vis) * mix(memory_alpha, a_fog, undisc);
	if (wp.y < near_floor) {
		ALPHA = 0.0;
	}
	if (debug_mode == 1) {
		ALBEDO = vec3(disc, vis, fract(wp.x * 0.25));
		ALPHA = 1.0;
	}
}
