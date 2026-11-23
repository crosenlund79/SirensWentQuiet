// Bullet holes, gashes and cracks: atlas quads on a per-module MultiMesh.
// INSTANCE_CUSTOM: x = atlas cell (0..3), yzw = tint for the torn rim (sRGB).
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D t_marks : source_color, filter_linear_mipmap;
instance uniform float cut_height = 100.0;

varying vec3 v_wpos;
varying vec4 v_custom;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	if (v_wpos.y > cut_height) {
		discard;
	}
	float cell = floor(v_custom.x + 0.5);
	vec2 off = vec2(mod(cell, 2.0), floor(cell / 2.0)) * 0.5;
	vec4 m = texture(t_marks, UV * 0.5 + off);
	if (m.a < 0.02) {
		discard;
	}
	vec3 tint = pow(v_custom.yzw, vec3(2.2));
	// light pixels are torn material (tinted), dark pixels the hole itself
	float lum = dot(m.rgb, vec3(0.333));
	ALBEDO = mix(m.rgb, m.rgb * tint * 1.1, smoothstep(0.3, 0.8, lum));
	ALPHA = m.a;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
