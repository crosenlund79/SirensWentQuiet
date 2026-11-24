// Experiment 004: falling snow flakes (CPUParticles3D quads), camera-facing,
// soft round, never inside the house below its roof. `tint` follows the
// time of day (bright by day, dim blue at night).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 house = vec4(-0.3, -0.3, 14.3, 9.3);   // x0, z0, x1, z1
uniform float roof_y = 2.85;
uniform vec3 tint : source_color = vec3(0.92, 0.94, 0.98);
uniform float opacity = 0.8;

varying vec3 center;

void vertex() {
	center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	if (center.x > house.x && center.x < house.z && center.z > house.y && center.z < house.w && center.y < roof_y) {
		discard;
	}
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.15, d) * opacity;
	if (a < 0.01) {
		discard;
	}
	ALBEDO = tint;
	ALPHA = a;
}
