// Volumetric fog bank around the lot (Forward+ FogVolume). Owner: E.
// Density follows the signed distance to the lot and a rising height profile,
// broken up by drifting value noise. Lit by the sun/moon and ambient light
// (Environment.volumetric_fog_*); a faint emission makes it glow at night.
shader_type fog;

uniform vec4 lot_rect = vec4(-4.5, -3.5, 18.5, 12.5);
uniform float density = 0.32;
uniform vec3 albedo_day : source_color = vec3(0.86, 0.88, 0.92);
uniform vec3 albedo_night : source_color = vec3(0.62, 0.7, 0.9);
uniform vec3 emission_day : source_color = vec3(0.0);
uniform vec3 emission_night : source_color = vec3(0.016, 0.022, 0.045);
uniform float night = 0.0;
uniform vec4 lane_a = vec4(0.0);
uniform vec4 lane_b = vec4(0.0);
uniform float lane_push = 1.7;

float sd_rect(vec2 p, vec4 r) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 h = (r.zw - r.xy) * 0.5;
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float lane(vec2 p, vec4 r) {
	if (r.z <= r.x) {
		return 0.0;
	}
	return 1.0 - smoothstep(-0.2, 0.6, sd_rect(p, r));
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fog() {
	vec3 p = WORLD_POSITION;
	float t = TIME;
	float n = vnoise(p * vec3(0.11, 0.2, 0.11) + vec3(t * 0.035, 0.0, t * 0.014)) * 0.65
			+ vnoise(p * 0.29 - vec3(t * 0.02, t * 0.01, -t * 0.05)) * 0.35;
	float lanes = max(lane(p.xz, lane_a), lane(p.xz, lane_b));
	float d = sd_rect(p.xz, lot_rect) - lanes * lane_push;
	float top = mix(2.0, 8.0, smoothstep(0.0, 15.0, d)) + (n - 0.5) * 2.5;
	float h = (1.0 - smoothstep(top * 0.45, top, p.y)) * step(-0.3, p.y);
	float edge = smoothstep(-0.4, 4.5, d);
	DENSITY = density * edge * h * mix(0.5, 1.35, n);
	ALBEDO = mix(albedo_day, albedo_night, night);
	EMISSION = mix(emission_day, emission_night, night) * (0.6 + n * 0.8);
}
