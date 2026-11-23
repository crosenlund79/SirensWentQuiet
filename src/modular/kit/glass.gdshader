// Window glass: tinted, fresnel-reflective, with an impact web after the first hit.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform sampler2D t_marks : source_color, filter_linear_mipmap;
instance uniform float cut_height = 100.0;
instance uniform vec4 crack = vec4(0.0);   // xyz world impact point, w size (0 = none)

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	if (v_wpos.y > cut_height) {
		discard;
	}
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	vec3 col = vec3(0.07, 0.1, 0.11);
	float a = 0.32 + fres * 0.55;
	// faint dirt streaks
	float streak = fract(sin(floor(v_wpos.x * 40.0 + v_wpos.z * 40.0) * 12.9898) * 43758.5453);
	a += streak * 0.04;
	if (crack.w > 0.0) {
		vec3 d = v_wpos - crack.xyz;
		vec3 an = abs(v_wnrm);
		vec2 p = an.x > an.z ? vec2(d.z, -d.y) : vec2(d.x, -d.y);
		vec2 uv = p / crack.w + 0.5;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			vec4 m = texture(t_marks, uv * 0.5 + vec2(0.5, 0.5));
			col = mix(col, vec3(0.85, 0.9, 0.92), m.a);
			a = max(a, m.a * 0.85);
		}
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.95);
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	METALLIC = 0.1;
}
