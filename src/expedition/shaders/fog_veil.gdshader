// Full-screen fog veil behind the expedition screen (ExpeditionScreen). Owner: E.
// Soft drifting fog-grey with a gentle vignette; `amount` fades it in and out.
shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 fog_dark : source_color = vec4(0.4, 0.43, 0.47, 1.0);
uniform vec4 fog_light : source_color = vec4(0.6, 0.63, 0.67, 1.0);
uniform float amount = 0.0;
uniform float aspect = 1.78;

void fragment() {
	vec2 uv = UV * vec2(aspect, 1.0);
	float t = TIME;
	float n = texture(noise_tex, uv * 0.55 + vec2(t * 0.006, t * 0.002)).r * 0.6
			+ texture(noise_tex, uv * 1.3 - vec2(t * 0.011, -t * 0.004)).r * 0.4;
	vec3 c = mix(fog_dark.rgb, fog_light.rgb, smoothstep(0.3, 0.75, n));
	float vig = 1.0 - smoothstep(0.35, 0.95, length((UV - 0.5) * vec2(1.25, 1.0)));
	c *= mix(0.78, 1.0, vig);
	COLOR = vec4(c, amount * mix(0.88, 0.97, n));
}
