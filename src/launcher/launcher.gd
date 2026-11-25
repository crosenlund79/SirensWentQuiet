extends Control
## Visual Experiments: the Experiment 001 version selection screen, reached
## from the main menu. Owner: U. Esc or Back returns to the main menu; each
## demo's Esc still returns here.

const VERSIONS := [
	{"key": "A", "title": "True 3D Voxels", "blurb": "Volumetric walls you can chew holes through, voxel by voxel.", "scene": "res://src/voxel/voxel_demo.tscn"},
	{"key": "B", "title": "Modular 3D", "blurb": "A reusable kit of wall, door and window pieces with damage states.", "scene": "res://src/modular/modular_demo.tscn"},
	{"key": "C", "title": "Illustrated 2D", "blurb": "Hand-inked top-down rooms that crack, splinter and give way.", "scene": "res://src/illustrated/illustrated_demo.tscn"},
]

const BG_SHADER := """
shader_type canvas_item;
uniform float t_offset = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
// Skyline of a quiet suburb: gabled roofs, dead trees, power lines and a silent siren.
float skyline(float x) {
	float h = 0.065;
	float sc = x * 8.0;
	float cell = floor(sc);
	float fx = fract(sc);
	float r = hash(vec2(cell, 3.0));
	if (r > 0.22) {
		float w = 0.5 + 0.38 * hash(vec2(cell, 7.0));
		float wall = 0.095 + 0.035 * hash(vec2(cell, 11.0));
		float off = (hash(vec2(cell, 13.0)) - 0.5) * (1.0 - w);
		float d = abs(fx - 0.5 - off);
		if (d < w * 0.5) { h = max(h, wall + (w * 0.5 - d) * 0.13); }
		// chimney on some roofs
		if (hash(vec2(cell, 17.0)) > 0.6 && abs(fx - 0.5 - off - w * 0.2) < 0.03) { h = max(h, wall + w * 0.08); }
	}
	// bare trees between houses
	float tc = floor(x * 23.0 + 0.4);
	float tf = fract(x * 23.0 + 0.4);
	float tr = hash(vec2(tc, 5.0));
	if (tr > 0.72) {
		float th = 0.11 + 0.08 * tr;
		h = max(h, th * smoothstep(0.5, 0.0, abs(tf - 0.5)) * (0.75 + 0.25 * noise(vec2(x * 900.0, 1.0))));
		if (abs(tf - 0.5) < 0.03) { h = max(h, th); }
	}
	// utility poles
	float pf = fract(x * 4.0 + 0.12);
	if (abs(pf - 0.5) < 0.0035) { h = max(h, 0.24); }
	// the siren mast
	if (abs(x - 0.865) < 0.0022) { h = max(h, 0.37); }
	return h;
}
float wires(vec2 q) {
	// sagging cables between poles (q.y measured up from the bottom)
	float pf = fract(q.x * 4.0 + 0.12);
	float sag = 0.225 - 0.035 * sin(3.14159 * fract(pf + 0.5));
	return smoothstep(0.0016, 0.0, abs(q.y - sag)) + smoothstep(0.0013, 0.0, abs(q.y - (sag - 0.012)));
}
void fragment() {
	vec2 uv = UV;
	float t = TIME + t_offset;
	vec3 top = vec3(0.02, 0.025, 0.04);
	vec3 low = vec3(0.09, 0.075, 0.085);
	vec3 col = mix(low, top, smoothstep(0.0, 0.85, 1.0 - uv.y));
	// faint dying red glow on the horizon, pulsing slower and slower
	float pulse = 0.5 + 0.5 * sin(t * 0.7);
	float glow = exp(-pow((1.0 - uv.y - 0.2) * 5.0, 2.0)) * (0.25 + 0.2 * pulse);
	col += vec3(0.32, 0.05, 0.05) * glow * smoothstep(0.0, 0.6, abs(sin(uv.x * 2.4 + 0.7)));
	// drifting haze
	float f = fbm(vec2(uv.x * 3.0 + t * 0.015, uv.y * 5.0 - t * 0.01));
	col += vec3(0.05, 0.05, 0.06) * smoothstep(0.35, 0.9, f) * (1.0 - uv.y * 0.5);
	// skyline silhouette, cables, siren horn
	float up = 1.0 - uv.y;
	float sky_h = skyline(uv.x);
	vec3 ink = vec3(0.012, 0.012, 0.016) + vec3(0.02, 0.0, 0.0) * glow;
	col = mix(col, ink, clamp(wires(vec2(uv.x, up)), 0.0, 1.0) * 0.9);
	vec2 horn = vec2(uv.x - 0.865, up - 0.36);
	bool siren = (abs(horn.x) < 0.015 && abs(horn.y) < 0.0035 + 0.0075 * abs(horn.x) / 0.015) || (abs(horn.x) < 0.003 && abs(horn.y + 0.004) < 0.008);
	if (up < sky_h || siren) { col = ink; }
	// one window still lit in the distance
	vec2 w = vec2(0.31, 0.085);
	if (abs(uv.x - w.x) < 0.0032 && abs(up - w.y) < 0.0055 && up < sky_h) { col = vec3(0.55, 0.38, 0.18) * (0.8 + 0.2 * sin(t * 9.0) * sin(t * 23.0)); }
	// grain + vignette
	col += (hash(uv * 900.0 + fract(t)) - 0.5) * 0.025;
	float v = smoothstep(1.15, 0.35, length((uv - 0.5) * vec2(1.25, 1.0)));
	COLOR = vec4(col * v, 1.0);
}
"""

var _buttons: Array[Button] = []
var _back: Button


func _ready() -> void:
	get_tree().paused = false
	Input.set_custom_mouse_cursor(null)
	Sfx.attach(self)
	_build()
	if not _buttons.is_empty():
		for b in _buttons:
			if not b.disabled:
				b.grab_focus()
				break


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1, KEY_A:
				launch(0)
			KEY_2, KEY_B:
				launch(1)
			KEY_3, KEY_C:
				launch(2)
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				back_to_menu()


func back_to_menu() -> void:
	get_tree().change_scene_to_file(GameLaunch.MENU_SCENE)


func launch(index: int) -> void:
	var path: String = VERSIONS[index]["scene"]
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	mat.shader = sh
	bg.material = mat
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(720, 0)
	center.add_child(col)

	theme = UiTheme.theme()
	var eyebrow := UiTheme.make_label("SIRENS WENT QUIET", 13, UiTheme.TEXT_DIM)
	eyebrow.add_theme_font_override("font", UiTheme.tracked_font(4))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eyebrow)
	var title := UiTheme.make_label("VISUAL EXPERIMENTS · EXPERIMENT 001", 34, UiTheme.TEXT)
	title.name = "Title"
	title.add_theme_font_override("font", UiTheme.tracked_font(4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	col.add_child(title)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(64, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)

	var sub := UiTheme.make_label("Three ways to build a destructible house. The survival game grew out of version A.", UiTheme.FONT_BODY - 1, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	for i in VERSIONS.size():
		col.add_child(_version_button(i))

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap2)
	var back := UiTheme.make_button("Back")
	back.name = "Back"
	back.custom_minimum_size = Vector2(200, UiTheme.BUTTON_HEIGHT)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_menu)
	col.add_child(back)
	_back = back
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap3)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 22)
	foot.add_child(UiTheme.make_key_hint("1 / 2 / 3", "Launch", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	foot.add_child(UiTheme.make_key_hint("Esc", "In a version: back here", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	foot.add_child(UiTheme.make_key_hint("Esc", "Here: main menu", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	col.add_child(foot)


func _version_button(i: int) -> Button:
	var v: Dictionary = VERSIONS[i]
	var available := ResourceLoader.exists(v["scene"])
	var b := Button.new()
	b.custom_minimum_size = Vector2(720, 78)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not available
	b.pressed.connect(launch.bind(i))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := UiTheme.button_style(state)
		if state == "normal":
			sb.bg_color = Color(UiTheme.BG, 0.72)
		b.add_theme_stylebox_override(state, sb)
	UiTheme.wire_sounds(b)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -22
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var key := Label.new()
	key.text = v["key"]
	key.add_theme_font_size_override("font_size", UiTheme.px(38))
	key.add_theme_color_override("font_color", UiTheme.ACCENT if available else UiTheme.TEXT_FAINT)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)

	var texts := VBoxContainer.new()
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var t := Label.new()
	t.text = v["title"] + ("" if available else "   (not built)")
	t.add_theme_font_size_override("font_size", UiTheme.px(22))
	t.add_theme_color_override("font_color", UiTheme.TEXT if available else UiTheme.TEXT_FAINT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(t)
	var d := Label.new()
	d.text = v["blurb"]
	d.add_theme_font_size_override("font_size", UiTheme.px(14))
	d.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(d)
	_buttons.append(b)
	return b
