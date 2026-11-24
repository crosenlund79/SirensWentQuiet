// Region map surfaces: terrain columns, building masses and trees.
// Vertex colour (sRGB) is the albedo, COLOR.a baked ambient occlusion,
// UV.x = emissive (warm windows), UV.y = 1 draws faint voxel edges (terrain).
// Cloud shadows drift over everything; the region edge dissolves into fog.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://src/map/shaders/map_common.gdshaderinc"

uniform float bevel = 0.16;
uniform float roughness = 0.92;
uniform float night = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.42);
uniform float glow_energy = 3.0;
uniform vec3 sel_pos = vec3(-1000.0, 0.0, -1000.0);
uniform float sel_radius = 3.0;
uniform vec3 sel_color : source_color = vec3(0.95, 0.62, 0.22);

varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	if (UV.y > 0.5) {
		// faint edges between terrain columns and height steps
		vec3 q = v_world / vec3(1.0, 0.5, 1.0);
		vec3 f = fract(q);
		vec3 an = abs(v_nrm);
		vec2 uvf = an.x > 0.5 ? f.yz : (an.y > 0.5 ? f.xz : f.xy);
		vec2 e = min(uvf, 1.0 - uvf);
		float edge = min(e.x, e.y);
		float px = length(fwidth(q));
		float show = 1.0 - smoothstep(0.1, 0.45, px);
		c *= 1.0 - bevel * show * (1.0 - smoothstep(0.0, 0.09, edge));
	}
	if (UV.y > 0.5 && abs(v_nrm.y) < 0.5) {
		// rock strata: each height step a slightly different shade
		float layer = floor(v_world.y / 0.5 + 0.001);
		c *= 0.93 + 0.12 * fract(sin(layer * 12.9898 + floor(v_world.x * 0.25) * 3.1) * 43758.5453);
	}
	c *= 1.0 - cloud_shadow_at(v_world);
	c *= mix(1.0, 0.82, night);
	vec3 em = c * glow_color * glow_energy * UV.x * mix(0.45, 1.6, night);
	// the selected place: a soft amber ring on the ground
	float d = length(v_world.xz - sel_pos.xz);
	float ring = smoothstep(sel_radius - 0.7, sel_radius - 0.1, d) * (1.0 - smoothstep(sel_radius - 0.1, sel_radius + 0.3, d));
	em += sel_color * ring * 0.55 * step(v_nrm.y, 2.0);
	float fk = edge_fog_at(v_world);
	ALBEDO = c * (1.0 - fk);
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.55;
	ROUGHNESS = roughness;
	SPECULAR = 0.22;
	EMISSION = mix(em, fog_color, fk);
}
