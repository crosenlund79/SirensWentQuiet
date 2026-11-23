// Soft dust / smoke puffs: camera-facing quads on a MultiMesh, lit.
// INSTANCE_CUSTOM: rgb colour (sRGB), a opacity.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec4 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float n = sin(atan(p.y, p.x) * 5.0 + v_c.r * 40.0) * 0.08;
	float a = smoothstep(1.0, 0.15, d + n) * v_c.a;
	if (a < 0.01) {
		discard;
	}
	ALBEDO = pow(v_c.rgb, vec3(2.2));
	ALPHA = a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
