// Version A muzzle flash: procedural additive star, always facing the camera.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float seed = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + seed * 6.2831;
	float rays = pow(abs(cos(a * 2.5)), 8.0) * (1.0 - r) * 1.4;
	float core = smoothstep(0.55, 0.0, r);
	float v = clamp(core + rays, 0.0, 1.0);
	ALBEDO = vec3(1.0, 0.78, 0.42) * v * 3.0;
}
