// Build-preview ghost for PropKit pieces (wall_ghost, or any type made with
// opts.ghost). Translucent, unshaded, with a soft rim, faint facet shading
// and slow scan lines so it reads by day and by night. The builder sets the
// colour per instance: PropKit.set_tint(node, Color) or the instance
// parameter `tint` (rgb + alpha) on the MeshInstance3D.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(0.86, 0.85, 0.8, 0.5);

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float rim = pow(1.0 - clamp(abs(dot(n, normalize(VIEW))), 0.0, 1.0), 2.0);
	// facet shading from a fixed key direction, so chamfers and edges read
	float key = 0.72 + 0.28 * max(dot(normalize(v_wnrm), normalize(vec3(-0.4, 0.8, 0.45))), 0.0);
	float scan = smoothstep(0.85, 1.0, fract(v_wpos.y * 6.0 - TIME * 0.35)) * 0.18;
	vec3 c = tint.rgb * key + vec3(rim * 0.35 + scan);
	ALBEDO = c;
	ALPHA = clamp(tint.a * (0.55 + rim * 0.6) + scan * 0.5, 0.0, 0.95);
}
