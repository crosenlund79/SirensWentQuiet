// Additive glow for sparks and tracers. INSTANCE_CUSTOM: rgb colour, a intensity.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

varying vec4 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = v_c.rgb * 2.5;
	ALPHA = clamp(v_c.a, 0.0, 1.0);
}
