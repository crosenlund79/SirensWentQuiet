// Version A dust puffs: lit soft billboards (MultiMesh, per-instance colour).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sx, INV_VIEW_MATRIX[2] * sx, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = COLOR.rgb;
	ALPHA = t.a * COLOR.a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
