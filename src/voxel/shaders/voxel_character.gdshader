// Version A characters: voxel-sculpted figures with baked AO, a cool rim
// light for readability (stronger at night), white hit flash and a dithered
// fade for corpses.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

instance uniform float flash = 0.0;
instance uniform float fade = 1.0;
uniform float night = 0.0;
uniform vec3 rim_day : source_color = vec3(0.55, 0.6, 0.68);
uniform vec3 rim_night : source_color = vec3(0.45, 0.6, 1.0);

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) {
		discard;
	}
	vec3 c = mix(to_linear(COLOR.rgb), vec3(1.0, 0.95, 0.9), flash * 0.75);
	ALBEDO = c;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = mix(rim_day * 0.12, rim_night * 0.35, night) * rim + vec3(1.0, 0.85, 0.7) * flash * 0.35;
}
