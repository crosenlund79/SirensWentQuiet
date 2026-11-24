// Enemy x-ray silhouette (second pass of the archetype material): the voxel
// x-ray shader (src/voxel/shaders/voxel_xray.gdshader) with the self-occlusion
// depth as a uniform, so a scaled rig (the brute) doesn't light up its own
// body where its arms and club are in front of the torso.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.52, 0.35);
uniform float self_depth = 0.55;      // m: only occluders farther in front count
instance uniform float flash = 0.0;   // same instance uniforms, same order as the main pass
instance uniform float fade = 1.0;

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	if (scene_z > -VERTEX.z - self_depth) {
		discard;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.4 + 0.6 * rim) * fade;
}
