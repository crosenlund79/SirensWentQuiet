// One shared surface shader for every hybrid prop (furniture, doors,
// barricades, storage, lights, yard props, vegetation). Forked from the
// Experiment 001 modular kit shader.
//
// Per vertex: material layer in UV2.x, flags in UV2.y (1 thin sheet,
// 2 vertical grain, 4 no shadow), sRGB tint in COLOR.rgb, wear in COLOR.a.
// Textures are projected along the dominant axis in OBJECT space (plus a
// per-node offset), so a swinging door leaf or a moved crate keeps its grain.
// Texture alpha = height, turned into a gentle bump.
// The cutaway uses the same uniforms and the same 0.1 m voxel quantisation
// as the voxel surface shader, so HouseWorld can drive both and the cut
// edges line up with the walls.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform sampler2D t_wood : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rough : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_fabric : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float bump = 1.0;
// Post-event dust settles on upward faces; grime follows the wear attribute.
uniform float dust = 0.32;
uniform vec3 dust_color : source_color = vec3(0.66, 0.62, 0.55);
uniform vec3 grime_color : source_color = vec3(0.23, 0.19, 0.15);
// Global warmth / desaturation so the props sit in the voxel palette.
uniform float saturation = 0.9;
uniform vec3 warm = vec3(1.02, 1.0, 0.96);

// Cutaway (names shared with voxel_surface.gdshader).
uniform vec3 grid_origin = vec3(-0.45, -0.4, -0.45);
uniform float voxel_size = 0.1;
uniform vec3 cut_origin = vec3(0.0, -100.0, 0.0);
uniform vec3 cut_dir = vec3(0.0, 0.83, 0.56);
uniform float cut_radius = 2.0;
uniform float cut_floor = 0.25;
uniform float cut_near = 0.45;
uniform vec3 section_color : source_color = vec3(0.16, 0.145, 0.13);

// Candle flames, wax and lantern diffusers: 0 = out, 1 = burning / on.
instance uniform float lit = 0.0;

varying vec3 v_mpos;
varying vec3 v_mnrm;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_h;
varying flat float v_layer;
varying flat float v_flags;
varying float v_seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 srgb(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	// Per-node offset: identical pieces do not repeat the same grain.
	vec3 np = NODE_POSITION_WORLD;
	v_seed = hash12(np.xz * 1.37 + np.y);
	v_mpos = VERTEX + vec3(v_seed * 7.1, v_seed * 3.3, v_seed * 5.7);
	v_mnrm = NORMAL;
	v_h = VERTEX.y;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_layer = UV2.x;
	v_flags = UV2.y;
}

void fragment() {
	int L = int(v_layer + 0.5);
	int flags = int(v_flags + 0.5);
	bool thin = (flags & 1) != 0;
	bool grain_v = (flags & 2) != 0;
	// 13 glow (lantern diffuser), 14 flame and flag 4 parts never block their own light.
	if (IN_SHADOW_PASS && (L == 13 || L == 14 || (flags & 4) != 0)) {
		discard;
	}
	if (L == 14 && lit < 0.02) {
		discard;     // a flame only exists while the candle burns
	}
	if (!IN_SHADOW_PASS) {
		vec3 cell = floor((v_wpos - grid_origin) / voxel_size);
		vec3 wc = grid_origin + (cell + 0.5) * voxel_size;
		vec3 rel = wc - cut_origin;
		float t = dot(rel, cut_dir);
		if (t > cut_near && wc.y > cut_floor) {
			float d = length(rel - cut_dir * t);
			if (d < cut_radius - 0.15 * hash13(cell + 17.0)) {
				discard;
			}
		}
	}

	if (!FRONT_FACING && !thin) {
		// Looking into a cut piece: flat dark section fill, like the voxel walls.
		ALBEDO = section_color;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	} else {
		vec3 mn = normalize(v_mnrm);
		vec3 an = abs(mn);
		vec2 uv;
		vec3 tu;
		vec3 tv;
		if (an.y > 0.6) {
			uv = v_mpos.xz;
			tu = vec3(1.0, 0.0, 0.0);
			tv = vec3(0.0, 0.0, 1.0);
		} else if (an.x > an.z) {
			uv = vec2(v_mpos.z, -v_mpos.y);
			tu = vec3(0.0, 0.0, 1.0);
			tv = vec3(0.0, -1.0, 0.0);
		} else {
			uv = vec2(v_mpos.x, -v_mpos.y);
			tu = vec3(1.0, 0.0, 0.0);
			tv = vec3(0.0, -1.0, 0.0);
		}
		// Grain direction for wood: along the longest run of the face.
		vec2 guv = uv;
		vec3 gu = tu;
		vec3 gv = tv;
		if (grain_v && an.y <= 0.6) {
			guv = vec2(uv.y, uv.x);
			gu = tv;
			gv = tu;
		}
		vec3 vcol = srgb(COLOR.rgb);
		float wear = COLOR.a;
		vec3 col = vec3(0.5);
		float rough = 0.85;
		float metal = 0.0;
		float spec = 0.35;
		vec3 emit = vec3(0.0);
		vec4 tx = vec4(0.5);
		float tile = 1.0;
		int tex = -1;     // which texture the bump reads: 0 wood 1 rough 2 fabric 3 concrete 4 asphalt
		vec2 tuv = uv;
		float paint_noise = vnoise(v_mpos.xz * 2.1 + v_mpos.y * 1.3) - 0.5;

		if (L == 0) {            // matte paint, plastic, paper-ish surfaces
			col = vcol * (1.0 + paint_noise * 0.08);
			rough = 0.82;
		} else if (L == 1) {     // furniture wood
			tile = 1.0;
			tuv = guv;
			tx = texture(t_wood, guv / tile);
			col = tx.rgb * vcol;
			rough = 0.62;
			spec = 0.4;
			tex = 0;
			tu = gu;
			tv = gv;
		} else if (L == 2) {     // fabric
			tile = 0.5;
			tx = texture(t_fabric, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.97;
			spec = 0.22;
			tex = 2;
		} else if (L == 3) {     // metal (painted or bare)
			col = vcol * (1.0 + paint_noise * 0.05);
			rough = 0.42;
			metal = 0.55;
			spec = 0.5;
		} else if (L == 4) {     // glossy: ceramic, enamel, glossy plastic
			col = vcol;
			rough = 0.3;
			spec = 0.55;
		} else if (L == 5) {     // dark glass / screens
			col = vcol;
			rough = 0.12;
			spec = 0.65;
		} else if (L == 6) {     // mirror
			col = vcol;
			rough = 0.08;
			spec = 0.85;
			metal = 0.3;
		} else if (L == 7) {     // weathered planks (barricades, crates, plank doors)
			tile = 1.0;
			tuv = guv;
			tx = texture(t_rough, guv / tile);
			col = tx.rgb * vcol;
			rough = 0.9;
			spec = 0.25;
			tex = 1;
			tu = gu;
			tv = gv;
		} else if (L == 8) {     // concrete
			tile = 2.5;
			tx = texture(t_concrete, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.92;
			tex = 3;
		} else if (L == 9) {     // asphalt
			tile = 4.0;
			tx = texture(t_asphalt, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.93;
			tex = 4;
		} else if (L == 10) {    // bark
			float n = vnoise(vec2((an.x > an.z ? v_mpos.z : v_mpos.x) * 40.0, v_mpos.y * 6.0));
			col = vcol * (0.7 + n * 0.5);
			rough = 1.0;
			spec = 0.15;
		} else if (L == 11) {    // soil
			float n = vnoise(uv * 8.0) * 0.6 + vnoise(uv * 31.0) * 0.4;
			col = vcol * (0.75 + n * 0.45);
			rough = 1.0;
			spec = 0.12;
		} else if (L == 12) {    // dry foliage, twigs
			float n = vnoise(v_mpos.xz * 23.0 + v_mpos.y * 17.0);
			col = vcol * (0.78 + n * 0.4);
			rough = 0.95;
			spec = 0.15;
		} else if (L == 13) {    // lantern diffuser / bulb: frosted, glows while lit
			col = vcol;
			rough = 0.45;
			spec = 0.5;
			emit = vcol * lit * 3.2;
		} else if (L == 14) {    // flame: emissive only, flickers
			float f = 0.8 + 0.2 * vnoise(vec2(TIME * 9.0 + v_seed * 31.0, v_seed * 7.0));
			col = vcol * 0.2;
			rough = 1.0;
			spec = 0.0;
			emit = vcol * lit * 6.0 * f;
		} else if (L == 15) {    // paper and cardboard
			float n = vnoise(uv * 60.0);
			col = vcol * (0.92 + n * 0.12);
			rough = 0.95;
			spec = 0.2;
		} else if (L == 16) {    // rusted metal
			float n = vnoise(uv * 9.0) * 0.6 + vnoise(uv * 37.0) * 0.4;
			vec3 rust = srgb(vec3(0.45, 0.24, 0.13));
			col = mix(vcol, rust, smoothstep(0.35, 0.75, n));
			rough = mix(0.5, 0.95, n);
			metal = mix(0.5, 0.1, n);
		} else if (L == 17) {    // tarp / plastic sheet
			float n = vnoise(uv * vec2(3.0, 11.0) + v_mpos.y);
			col = vcol * (0.88 + n * 0.2);
			rough = 0.55;
			spec = 0.4;
		} else if (L == 18) {    // candle wax: warms up while lit
			col = vcol;
			rough = 0.5;
			spec = 0.35;
			emit = vcol * vec3(1.0, 0.62, 0.3) * lit * 0.35;
		} else if (L == 19) {    // faded road paint
			float n = vnoise(uv * 5.0);
			col = vcol * (0.6 + n * 0.5);
			rough = 0.9;
		}

		// Hand-painted variation across big surfaces.
		col *= 1.0 + paint_noise * 0.06;

		// Wear: grime and scuffs in noisy patches, and a darker band near the ground.
		vec3 wn = normalize(v_wnrm);
		if (wear > 0.004) {
			float g = vnoise(v_mpos.xy * 5.3 + v_mpos.zz * 3.1) * 0.65 + vnoise(v_mpos.xz * 17.0 + v_mpos.y * 11.0) * 0.35;
			float ground = smoothstep(0.45, 0.0, v_h);
			float amt = clamp(wear * (0.55 + 0.9 * g) + ground * wear * 0.6, 0.0, 1.0);
			col = mix(col, col * grime_color * 2.2, amt * 0.75);
			rough = mix(rough, 0.95, amt * 0.6);
			metal *= 1.0 - amt * 0.6;
		}
		// Dust on everything that faces up (not on glowing or flat ground layers).
		if (L != 13 && L != 14 && L != 8 && L != 9 && L != 19 && L != 11) {
			float up = smoothstep(0.55, 0.95, FRONT_FACING ? wn.y : -wn.y);
			float dn = vnoise(v_wpos.xz * 3.7) * 0.6 + vnoise(v_wpos.xz * 19.0) * 0.4;
			float da = up * dust * smoothstep(0.25, 0.8, dn);
			col = mix(col, srgb(dust_color), da);
			rough = mix(rough, 1.0, da);
			spec *= 1.0 - da * 0.6;
		}
		// Gentle contact darkening near the floor (SSAO does the rest).
		float ao = mix(0.62, 1.0, smoothstep(0.0, 0.3, v_h));
		if (wn.y > 0.7) {
			ao = 1.0;
		}

		// Harmonise with the voxel palette: a touch warmer, a touch less saturated.
		float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(luma), col, saturation) * warm;

		vec3 n = FRONT_FACING ? mn : -mn;
		if (tex >= 0 && bump > 0.0) {
			float e = 1.0 / 256.0;
			vec2 u0 = tuv / tile;
			float h0 = tx.a;
			float hu = h0;
			float hv = h0;
			if (tex == 0) { hu = texture(t_wood, u0 + vec2(e, 0.0)).a; hv = texture(t_wood, u0 + vec2(0.0, e)).a; }
			else if (tex == 1) { hu = texture(t_rough, u0 + vec2(e, 0.0)).a; hv = texture(t_rough, u0 + vec2(0.0, e)).a; }
			else if (tex == 2) { hu = texture(t_fabric, u0 + vec2(e, 0.0)).a; hv = texture(t_fabric, u0 + vec2(0.0, e)).a; }
			else if (tex == 3) { hu = texture(t_concrete, u0 + vec2(e, 0.0)).a; hv = texture(t_concrete, u0 + vec2(0.0, e)).a; }
			else if (tex == 4) { hu = texture(t_asphalt, u0 + vec2(e, 0.0)).a; hv = texture(t_asphalt, u0 + vec2(0.0, e)).a; }
			float k = bump * 1.2;
			n = normalize(n - k * ((hu - h0) * tu + (hv - h0) * tv));
		}
		vec3 wnb = normalize(mat3(MODEL_MATRIX) * n);
		NORMAL = normalize((VIEW_MATRIX * vec4(wnb, 0.0)).xyz);
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
		AO = ao;
		AO_LIGHT_AFFECT = 0.35;
	}
}
