// Debris chips, splinters and shards on a MultiMesh.
// INSTANCE_CUSTOM: rgb = colour (sRGB), a = shininess (glass/metal ~1).
shader_type spatial;
render_mode cull_disabled;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = pow(v_custom.rgb, vec3(2.2));
	ROUGHNESS = mix(0.9, 0.08, v_custom.a);
	SPECULAR = mix(0.3, 0.9, v_custom.a);
	METALLIC = v_custom.a * 0.2;
}
