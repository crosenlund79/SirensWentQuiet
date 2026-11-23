// Characters: vertex-coloured low-poly figures with hit flash, a soft rim
// light for readability at night and a dithered fade-out for corpses.
// UV2.x carries the kit layer id (7 metal, 19 glossy, 21 dark glass).
shader_type spatial;
render_mode cull_back;

instance uniform float flash = 0.0;
instance uniform float fade = 0.0;
instance uniform float rim = 0.0;
instance uniform vec4 rim_color : source_color = vec4(0.55, 0.65, 0.85, 1.0);

varying flat float v_layer;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	v_layer = UV2.x;
}

void fragment() {
	if (fade > 0.0 && fade > bayer4(FRAGCOORD.xy) * 0.999) {
		discard;
	}
	int L = int(v_layer + 0.5);
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.78;
	float metal = 0.0;
	if (L == 7) { rough = 0.35; metal = 0.6; }
	else if (L == 19) { rough = 0.25; }
	else if (L == 21) { rough = 0.1; }
	ALBEDO = mix(c, vec3(1.0, 0.96, 0.92), flash * 0.55);
	ROUGHNESS = rough;
	METALLIC = metal;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * f * rim + vec3(1.0, 0.92, 0.85) * flash * 1.2;
}
