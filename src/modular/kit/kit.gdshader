// One shared surface shader for every static piece of the modular kit
// (walls, posts, floors, roof, furniture, props, rubble).
// The material "layer" is stored per vertex in UV2.x, the wall side (A/B) in
// UV2.y and a per-vertex tint in COLOR (sRGB). Textures are sampled in world
// space, so neighbouring modules line up seamlessly on the 1 m grid.
// Texture alpha = height, turned into a gentle bump.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D t_siding : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_plaster : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_wood : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_wood_light : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_tile : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_kitchen : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_roof : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_fabric : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 cap_color : source_color = vec4(0.17, 0.17, 0.18, 1.0);
uniform vec4 trim_color : source_color = vec4(0.93, 0.92, 0.89, 1.0);
uniform float bump = 1.0;

// Per instance: room paint on side A (+z) / B (-z), cutaway height, fade.
instance uniform vec4 tint_a : source_color = vec4(1.0);
instance uniform vec4 tint_b : source_color = vec4(1.0);
instance uniform float cut_height = 100.0;
instance uniform float fade = 0.0;
instance uniform float lit = 0.0;

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying flat float v_layer;
varying flat float v_side;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

vec3 srgb(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_layer = UV2.x;
	v_side = UV2.y;
}

void fragment() {
	if (!IN_SHADOW_PASS) {
		// Cutaway: the module is lowered to cut_height (with a ragged, painted cut edge).
		float jag = (vnoise(v_wpos.xz * 9.0 + v_wpos.y) - 0.5) * 0.03;
		if (v_wpos.y > cut_height + jag) {
			discard;
		}
		if (fade > 0.0 && fade > bayer4(FRAGCOORD.xy) * 0.999) {
			discard;
		}
	}
	int L = int(v_layer + 0.5);
	vec3 wn = normalize(v_wnrm);
	vec3 vcol = srgb(COLOR.rgb);

	if (!FRONT_FACING && L != 26) {
		// Looking into a cut wall: draw the solid section ("poche") cap.
		ALBEDO = cap_color.rgb;
		ROUGHNESS = 0.95;
		SPECULAR = 0.2;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	} else {
		// World-space projection by dominant axis.
		vec3 an = abs(wn);
		vec2 uv;
		vec3 tu;
		vec3 tv;
		if (an.y > 0.6) {
			uv = v_wpos.xz;
			tu = vec3(1.0, 0.0, 0.0);
			tv = vec3(0.0, 0.0, 1.0);
		} else if (an.x > an.z) {
			uv = vec2(v_wpos.z, -v_wpos.y);
			tu = vec3(0.0, 0.0, 1.0);
			tv = vec3(0.0, -1.0, 0.0);
		} else {
			uv = vec2(v_wpos.x, -v_wpos.y);
			tu = vec3(1.0, 0.0, 0.0);
			tv = vec3(0.0, -1.0, 0.0);
		}
		vec3 col = vec3(0.5);
		float rough = 0.85;
		float metal = 0.0;
		float spec = 0.4;
		vec3 emit = vec3(0.0);
		vec4 tx = vec4(0.0);
		float tile = 1.0;
		bool textured = true;
		float paint_noise = vnoise(v_wpos.xz * 0.9 + v_wpos.y * 0.7) - 0.5;

		if (L == 0) {            // exterior siding (concrete plinth band at the bottom)
			tile = 2.0;
			tx = texture(t_siding, uv / tile);
			col = tx.rgb * vcol;
			// rain-splash grime near the ground
			float g = smoothstep(0.55, 0.0, v_wpos.y) * (0.55 + 0.45 * vnoise(uv * vec2(6.0, 1.5)));
			col = mix(col, col * vec3(0.62, 0.58, 0.52), g * 0.6);
			if (v_wpos.y < 0.2) {
				vec4 c2 = texture(t_concrete, uv / 2.5);
				col = c2.rgb * 0.82;
				tx.a = c2.a;
			}
			rough = 0.8;
		} else if (L == 1) {     // interior paint, tinted per room side, baseboard at the bottom
			tile = 2.0;
			tx = texture(t_plaster, uv / tile);
			vec3 t = v_side > 0.5 ? tint_b.rgb : tint_a.rgb;
			col = tx.rgb * t * vcol;
			if (v_wpos.y < 0.09) {
				col = trim_color.rgb * (v_wpos.y > 0.075 ? 1.08 : 0.94);
			}
			rough = 0.9;
		} else if (L == 2) {     // painted trim (vertex colour)
			col = vcol * (1.0 + paint_noise * 0.06);
			rough = 0.6;
			textured = false;
		} else if (L == 3) {     // wall top / section cap
			col = cap_color.rgb * vcol * (1.0 + paint_noise * 0.1);
			rough = 0.95;
			textured = false;
		} else if (L == 4) {     // raw timber (studs, splinters, sheathing)
			float along = an.y > 0.6 ? v_wpos.x + v_wpos.z : v_wpos.y;
			float across = an.x > an.z ? v_wpos.z : v_wpos.x;
			float gr = vnoise(vec2(across * 60.0, along * 3.0));
			col = vcol * (0.86 + gr * 0.26);
			rough = 0.9;
			textured = false;
		} else if (L == 5) {     // fibreglass insulation
			float n = vnoise(uv * 22.0) * 0.6 + vnoise(uv * 70.0) * 0.4;
			col = vcol * (0.72 + n * 0.5);
			rough = 1.0;
			spec = 0.1;
			textured = false;
		} else if (L == 6) {     // raw gypsum / plaster rubble
			float n = vnoise(uv * 40.0);
			col = vcol * (0.88 + n * 0.16);
			rough = 1.0;
			textured = false;
		} else if (L == 7) {     // metal
			col = vcol;
			rough = 0.38;
			metal = 0.65;
			textured = false;
		} else if (L == 8) {     // oak floor
			tile = 2.0;
			tx = texture(t_wood, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.55;
			spec = 0.5;
		} else if (L == 9) {     // light ash floor
			tile = 2.0;
			tx = texture(t_wood_light, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.6;
			spec = 0.5;
		} else if (L == 10) {    // bathroom tile
			tile = 1.0;
			tx = texture(t_tile, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.25;
			spec = 0.6;
		} else if (L == 11) {    // kitchen terracotta hex
			tile = 1.4;
			tx = texture(t_kitchen, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.5;
		} else if (L == 12) {    // concrete
			tile = 2.5;
			tx = texture(t_concrete, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.9;
		} else if (L == 13) {    // standing-seam roof (seams run down the slope)
			tile = 2.0;
			tx = texture(t_roof, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.5;
			metal = 0.35;
		} else if (L == 14) {    // dead lawn
			tile = 4.0;
			tx = texture(t_grass, uv / tile);
			// second, rotated sample at another scale hides the tiling
			vec4 tx2 = texture(t_grass, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv / 9.3 + 0.37);
			tx = mix(tx, tx2, smoothstep(0.25, 0.75, vnoise(v_wpos.xz * 0.19)));
			float big = vnoise(v_wpos.xz * 0.07) * 0.6 + vnoise(v_wpos.xz * 0.27) * 0.4;
			col = tx.rgb * vcol * (0.8 + big * 0.34);
			rough = 1.0;
			spec = 0.2;
		} else if (L == 15) {    // asphalt
			tile = 4.0;
			tx = texture(t_asphalt, uv / tile);
			col = tx.rgb * vcol;
			rough = 0.92;
		} else if (L == 16) {    // fabric
			tile = 0.5;
			tx = texture(t_fabric, uv / tile);
			col = tx.rgb * vcol;
			rough = 1.0;
			spec = 0.25;
		} else if (L == 17) {    // furniture wood
			tile = 1.0;
			vec2 guv = an.y > 0.6 ? uv : (an.x > an.z ? vec2(v_wpos.y, v_wpos.z) : vec2(v_wpos.x, v_wpos.y));
			tx = texture(t_grain, guv / tile);
			col = tx.rgb * vcol;
			rough = 0.55;
			spec = 0.45;
		} else if (L == 18) {    // plain matte
			col = vcol * (1.0 + paint_noise * 0.08);
			rough = 0.8;
			textured = false;
		} else if (L == 19) {    // glossy (ceramic, plastic, enamel)
			col = vcol;
			rough = 0.18;
			spec = 0.6;
			textured = false;
		} else if (L == 20) {    // lamp shade / bulb: glows when lit
			col = vcol;
			rough = 0.7;
			emit = vcol * lit * 3.0;
			textured = false;
		} else if (L == 21) {    // screen / dark glass
			col = vcol;
			rough = 0.08;
			spec = 0.7;
			textured = false;
		} else if (L == 22) {    // soil / dust rubble
			float n = vnoise(uv * 8.0) * 0.6 + vnoise(uv * 31.0) * 0.4;
			col = vcol * (0.75 + n * 0.45);
			rough = 1.0;
			spec = 0.15;
			textured = false;
		} else if (L == 23) {    // concrete, vertex-tinted, no texture bump (curbs, steps)
			tx = texture(t_concrete, uv / 2.5);
			col = tx.rgb * vcol;
			rough = 0.9;
			textured = false;
		} else if (L == 24) {    // bark
			float n = vnoise(vec2((an.x > an.z ? v_wpos.z : v_wpos.x) * 40.0, v_wpos.y * 6.0));
			col = vcol * (0.7 + n * 0.5);
			rough = 1.0;
			textured = false;
		} else if (L == 25) {    // road paint (faded)
			float n = vnoise(uv * 5.0);
			col = vcol * (0.6 + n * 0.5);
			rough = 0.9;
			textured = false;
		} else if (L == 26) {    // mirror-ish / glass, double sided
			col = vcol;
			rough = 0.05;
			spec = 0.9;
			metal = 0.3;
			textured = false;
		}

		// hand-painted variation across big surfaces
		col *= 1.0 + paint_noise * 0.08;

		vec3 n = wn;
		if (textured && bump > 0.0) {
			float e = 1.0 / 512.0;
			vec2 u0 = uv / tile;
			float h0 = tx.a;
			float hu = h0;
			float hv = h0;
			if (L == 0) { hu = texture(t_siding, u0 + vec2(e, 0.0)).a; hv = texture(t_siding, u0 + vec2(0.0, e)).a; }
			else if (L == 1) { hu = texture(t_plaster, u0 + vec2(e, 0.0)).a; hv = texture(t_plaster, u0 + vec2(0.0, e)).a; }
			else if (L == 8) { hu = texture(t_wood, u0 + vec2(e, 0.0)).a; hv = texture(t_wood, u0 + vec2(0.0, e)).a; }
			else if (L == 9) { hu = texture(t_wood_light, u0 + vec2(e, 0.0)).a; hv = texture(t_wood_light, u0 + vec2(0.0, e)).a; }
			else if (L == 10) { hu = texture(t_tile, u0 + vec2(e, 0.0)).a; hv = texture(t_tile, u0 + vec2(0.0, e)).a; }
			else if (L == 11) { hu = texture(t_kitchen, u0 + vec2(e, 0.0)).a; hv = texture(t_kitchen, u0 + vec2(0.0, e)).a; }
			else if (L == 12) { hu = texture(t_concrete, u0 + vec2(e, 0.0)).a; hv = texture(t_concrete, u0 + vec2(0.0, e)).a; }
			else if (L == 13) { hu = texture(t_roof, u0 + vec2(e, 0.0)).a; hv = texture(t_roof, u0 + vec2(0.0, e)).a; }
			else if (L == 14) { hu = texture(t_grass, u0 + vec2(e, 0.0)).a; hv = texture(t_grass, u0 + vec2(0.0, e)).a; }
			else if (L == 15) { hu = texture(t_asphalt, u0 + vec2(e, 0.0)).a; hv = texture(t_asphalt, u0 + vec2(0.0, e)).a; }
			else if (L == 16) { hu = texture(t_fabric, u0 + vec2(e, 0.0)).a; hv = texture(t_fabric, u0 + vec2(0.0, e)).a; }
			float k = bump * 1.5;
			n = normalize(wn - k * ((hu - h0) * tu + (hv - h0) * tv));
		}
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
	}
}
