// The drifting cloud layer above the region map: the same cloud field as the
// shadows on the ground, thin, with gaps; it clears around the cursor and the
// selected place, fades out when the camera dives below it, and fades at the
// region edge.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/map/shaders/map_common.gdshaderinc"

uniform float opacity = 0.72;
uniform float layer_shift = 0.0;            // second layer: slightly different field
uniform vec3 light_col : source_color = vec3(0.97, 0.96, 0.94);
uniform vec3 shade_col : source_color = vec3(0.6, 0.64, 0.7);
uniform vec2 clear_a = vec2(-999.0);        // cursor (cloud-plane xz)
uniform vec2 clear_b = vec2(-999.0);        // selected place (cloud-plane xz)
uniform float clear_radius = 11.0;
uniform float night = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz + vec2(layer_shift * 23.0, layer_shift * 9.0);
	float raw = cloud_raw(p);
	float d = smoothstep(cloud_cover - cloud_softness + layer_shift * 0.05, cloud_cover + cloud_softness, raw);
	float thick = smoothstep(cloud_cover, cloud_cover + 0.3, raw);
	// self-shading: darker where the field is denser toward the sun
	float toward = cloud_raw(p - normalize(sun_shift) * 3.0);
	float self_shade = clamp((toward - raw) * 3.0 + thick * 0.35, 0.0, 1.0);
	vec3 col = mix(light_col, shade_col, self_shade * 0.75);
	col = mix(col, col * vec3(0.28, 0.32, 0.45), night);
	float clear = smoothstep(clear_radius * 0.35, clear_radius, distance(v_world.xz, clear_a));
	clear *= smoothstep(clear_radius * 0.35, clear_radius, distance(v_world.xz, clear_b));
	vec2 q = v_world.xz;
	float inside = min(min(q.x + 18.0, q.y + 18.0), min(region_size.x + 18.0 - q.x, region_size.y + 18.0 - q.y));
	float a = d * opacity * mix(0.55, 1.0, thick) * clear * smoothstep(0.0, 14.0, inside);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
