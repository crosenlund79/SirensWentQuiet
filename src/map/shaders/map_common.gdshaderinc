// Shared by the region map's surface, water and cloud shaders (src/map).
// One drifting cloud field: the cloud layer draws it, the ground darkens
// under it (cloud shadows, shifted along the sun direction), and the map
// dissolves into fog at the region edge.

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_offset = vec2(0.0);      // world units; RegionMapView drifts it
uniform float cloud_scale = 74.0;           // world units per noise tile
uniform float cloud_cover = 0.6;           // higher = fewer clouds
uniform float cloud_softness = 0.09;
uniform float cloud_y = 24.0;               // height of the cloud layer
uniform vec2 sun_shift = vec2(0.35, 0.55);  // xz shift per unit of height (shadows)
uniform float cloud_shadow = 0.3;           // darkening under a cloud (0..1)
uniform vec2 region_size = vec2(160.0, 120.0);
uniform float edge_width = 9.0;
uniform vec3 fog_color : source_color = vec3(0.55, 0.58, 0.6);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float cloud_raw(vec2 p) {
	float a = texture(cloud_tex, (p + cloud_offset) / cloud_scale).r;
	float b = texture(cloud_tex, (p + cloud_offset * 1.35 + vec2(37.0, 11.0)) / (cloud_scale * 0.42)).r;
	return a * 0.72 + b * 0.28;
}

float cloud_density(vec2 p) {
	return smoothstep(cloud_cover - cloud_softness, cloud_cover + cloud_softness, cloud_raw(p));
}

// 0..cloud_shadow: how much a point on the ground is shaded by the clouds.
float cloud_shadow_at(vec3 w) {
	return cloud_density(w.xz + sun_shift * (cloud_y - w.y)) * cloud_shadow;
}

// 0 inside the region, 1 in the fog beyond its edge (ragged, static).
float edge_fog_at(vec3 w) {
	vec2 p = w.xz;
	float d = min(min(p.x, p.y), min(region_size.x - p.x, region_size.y - p.y));
	float n = texture(cloud_tex, p / 41.0 + vec2(0.31, 0.77)).r - 0.5;
	return 1.0 - smoothstep(0.0, edge_width, d + n * 7.0 - 1.0);
}
