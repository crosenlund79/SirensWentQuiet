// Version A yard: one texel per 0.1 m voxel cell (nearest), generated from
// the plan; beyond it the lawn swatch repeats and darkens into the distance.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D ground_tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D lawn_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec2 img_origin;
uniform vec2 img_size;
uniform vec2 lawn_cells = vec2(128.0, 128.0);
// Experiment 004: beyond the image the lawn swatch turns to snow (1 = snowy).
uniform float snow = 0.0;
uniform vec3 snow_color : source_color = vec3(0.89, 0.91, 0.93);
// Exp 006 (D): dug trench cells are cut out of the ground (src/defense/
// defense_grid.gd: one texel per 1 m cell over hole_rect = origin, size).
uniform float holes = 0.0;
uniform sampler2D hole_tex : filter_nearest, repeat_disable;
uniform vec4 hole_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (holes > 0.5) {
		vec2 huv = (wpos.xz - hole_rect.xy) / hole_rect.zw;
		if (huv.x >= 0.0 && huv.y >= 0.0 && huv.x < 1.0 && huv.y < 1.0 && texture(hole_tex, huv).r > 0.5) {
			discard;
		}
	}
	vec2 uv = (wpos.xz - img_origin) / img_size;
	vec3 c;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	if (inside > 0.5) {
		c = texture(ground_tex, uv).rgb;
	} else {
		c = texture(lawn_tex, wpos.xz / 0.1 / lawn_cells).rgb;
		float l = dot(c, vec3(0.3, 0.55, 0.15));
		c = mix(c, snow_color * (0.86 + 0.5 * l), snow);
		vec2 d = max(max(img_origin - wpos.xz, wpos.xz - (img_origin + img_size)), vec2(0.0));
		c *= mix(1.0, 0.55, clamp(length(d) / 12.0, 0.0, 1.0));
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
