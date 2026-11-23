// Version A yard: one texel per 0.1 m voxel cell (nearest), generated from
// the plan; beyond it the lawn swatch repeats and darkens into the distance.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D ground_tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D lawn_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec2 img_origin;
uniform vec2 img_size;
uniform vec2 lawn_cells = vec2(128.0, 128.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - img_origin) / img_size;
	vec3 c;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	if (inside > 0.5) {
		c = texture(ground_tex, uv).rgb;
	} else {
		c = texture(lawn_tex, wpos.xz / 0.1 / lawn_cells).rgb;
		vec2 d = max(max(img_origin - wpos.xz, wpos.xz - (img_origin + img_size)), vec2(0.0));
		c *= mix(1.0, 0.55, clamp(length(d) / 12.0, 0.0, 1.0));
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
