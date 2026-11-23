// Version A voxel surfaces: per-voxel colour (vertex colour), baked AO in
// COLOR.a, emissive/glossy flags in UV, a voxel-quantised cutaway cylinder
// between the player and the camera, and dark "section" caps on cut walls.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 grid_origin = vec3(-0.45, -0.4, -0.45);
uniform float voxel_size = 0.1;
// Cutaway: voxels whose centre is within cut_radius of the line from
// cut_origin toward the camera (cut_dir), in front of cut_origin and above
// cut_floor, are not drawn (shadows still are).
uniform vec3 cut_origin = vec3(0.0, -100.0, 0.0);
uniform vec3 cut_dir = vec3(0.0, 0.83, 0.56);
uniform float cut_radius = 2.0;
uniform float cut_floor = 0.25;
uniform float cut_near = 0.45;
uniform vec3 section_color : source_color = vec3(0.16, 0.145, 0.13);
uniform float night = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.42);
uniform float glow_energy = 2.4;
uniform float bevel = 0.18;
uniform float fade = 1.0;          // < 1 dissolves voxel by voxel (roof)
uniform float model_space = 0.0;   // 1: quantise in model space (props)

varying vec3 v_pos;
varying vec3 v_nrm;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	if (model_space > 0.5) {
		v_pos = VERTEX;
		v_nrm = NORMAL;
	} else {
		v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
}

void fragment() {
	vec3 q = (v_pos - grid_origin) / voxel_size;
	vec3 cell = floor(q - v_nrm * 0.5);
	vec3 wc = (MODEL_MATRIX * vec4(grid_origin + (cell + 0.5) * voxel_size, 1.0)).xyz;
	if (model_space < 0.5) {
		wc = grid_origin + (cell + 0.5) * voxel_size;
	}
	float h = hash13(cell + 17.0);
	if (fade < 0.999 && h > fade) {
		discard;
	}
	if (!IN_SHADOW_PASS) {
		vec3 rel = wc - cut_origin;
		float t = dot(rel, cut_dir);
		if (t > cut_near && wc.y > cut_floor) {
			float d = length(rel - cut_dir * t);
			if (d < cut_radius - 0.15 * h) {
				discard;
			}
		}
	}
	if (!FRONT_FACING) {
		// Looking into a cut-away voxel: flat dark section fill.
		// (reads like the dark wall caps: a clean architectural cut)
		ALBEDO = section_color;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	} else {
		vec3 c = to_linear(COLOR.rgb);
		// Soft bevel on each voxel face, faded out when voxels get small on screen.
		vec3 f = fract(q);
		vec3 an = abs(v_nrm);
		vec2 uvf = an.x > 0.5 ? f.yz : (an.y > 0.5 ? f.xz : f.xy);
		vec2 e = min(uvf, 1.0 - uvf);
		float edge = min(e.x, e.y);
		float px = length(fwidth(q));
		float glossy = mod(UV.y, 2.0);
		float painted = step(1.5, UV.y);
		// Finished paint stays smooth; voxel grain shows on raw cuts, furniture, tiles.
		float show = (1.0 - smoothstep(0.12, 0.3, px)) * max(1.0 - painted, glossy);
		c *= 1.0 - bevel * show * (1.0 - smoothstep(0.0, 0.14, edge));
		ALBEDO = c;
		AO = COLOR.a;
		AO_LIGHT_AFFECT = 0.45;
		ROUGHNESS = mix(0.86, 0.42, glossy);
		SPECULAR = mix(0.32, 0.55, glossy);
		EMISSION = c * glow_color * glow_energy * UV.x * night;
	}
}
