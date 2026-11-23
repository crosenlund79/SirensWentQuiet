// Version A window glass: tinted, reflective, follows the same cutaway.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

uniform vec3 cut_origin = vec3(0.0, -100.0, 0.0);
uniform vec3 cut_dir = vec3(0.0, 0.83, 0.56);
uniform float cut_radius = 2.0;
uniform float cut_floor = 0.25;
uniform float cut_near = 0.45;
uniform float night = 0.0;

varying vec3 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 rel = v_pos - cut_origin;
	float t = dot(rel, cut_dir);
	if (t > cut_near && v_pos.y > cut_floor && length(rel - cut_dir * t) < cut_radius - 0.2) {
		discard;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = COLOR.rgb * 0.55;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = clamp(0.32 + fres * 0.5, 0.0, 0.85);
	EMISSION = vec3(0.12, 0.16, 0.2) * fres * (1.0 - night * 0.7);
}
