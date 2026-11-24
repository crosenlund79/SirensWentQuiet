// Region map water: the bay, the river and the mountain tarn.
// COLOR.r = depth (0 shallow .. 1 deep), COLOR.g = shore (foam), COLOR.b = 1
// for the sea; UV.y = 1 on falls (the river stepping down a level).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://src/map/shaders/map_common.gdshaderinc"

uniform vec3 shallow : source_color = vec3(0.4, 0.52, 0.52);
uniform vec3 deep : source_color = vec3(0.17, 0.27, 0.34);
uniform vec3 river : source_color = vec3(0.3, 0.42, 0.44);
uniform vec3 foam : source_color = vec3(0.86, 0.88, 0.86);
uniform float night = 0.0;
uniform float shimmer = 0.7;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float t = TIME;
	float depth = COLOR.r;
	float shore = COLOR.g;
	float sea = COLOR.b;
	vec3 c = mix(mix(shallow, river, 1.0 - sea), deep, smoothstep(0.05, 1.0, depth));
	float n1 = texture(cloud_tex, p / 7.0 + vec2(t * 0.011, t * 0.007)).r;
	float n2 = texture(cloud_tex, p / 4.3 - vec2(t * 0.009, -t * 0.012)).r;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.16, 1.0, (n2 - 0.5) * 0.16));
	float f = shore * mix(0.25, 1.0, sea) * smoothstep(0.42, 0.72, n1 * 0.7 + n2 * 0.3 + 0.18 * sin(t * 1.1 + p.x * 0.9 + p.y * 0.6));
	if (UV.y > 0.5) {
		// falls: white streaks running down
		float s = texture(cloud_tex, vec2(p.x * 0.7 + p.y * 0.7, v_world.y * 0.9 + t * 0.9) * 0.35).r;
		f = 0.45 + 0.55 * smoothstep(0.35, 0.6, s);
		nrm = vec3(0.0, 1.0, 0.0);
	}
	c = mix(c, foam, clamp(f, 0.0, 1.0) * 0.75);
	c *= 1.0 - cloud_shadow_at(v_world);
	c *= mix(1.0, 0.75, night);
	// shimmer: small glints that come and go
	float g = texture(cloud_tex, p / 2.1 + vec2(t * 0.031, -t * 0.019)).r * texture(cloud_tex, p / 3.3 - vec2(t * 0.023, t * 0.027)).r;
	float glint = smoothstep(0.47, 0.53, g) * shimmer * (1.0 - shore * 0.6) * (1.0 - night * 0.7);
	float fk = edge_fog_at(v_world);
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	ALBEDO = c * (1.0 - fk);
	ROUGHNESS = 0.3;
	SPECULAR = 0.55;
	EMISSION = mix(vec3(0.85, 0.88, 0.9) * glint * 0.6, fog_color, fk);
}
