extends Control
## Main menu, the project's main scene (SPEC §2). Owner: U.
## New Game · Continue · Settings · Visual Experiments · Quit over a silent
## suburban street in drifting fog, with an abandoned siren mast.
## New Game asks for the difficulty (DifficultyDialog; Experiment 003) and
## hands it over in GameLaunch.difficulty.
## Keyboard (arrows, Enter, Esc) and mouse. Shows GameLaunch.notice once.

const BG_SHADER := """
shader_type canvas_item;
// A silent suburban street in dense, drifting fog; an abandoned siren mast.
uniform float aspect = 1.7778;
uniform float t_offset = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; } return v; }

// Gabled houses with chimneys along one row; x in cells, returns height above the row's ground.
float houses(float x, float seed, float wall, float roof) {
	float cell = floor(x);
	float fx = fract(x);
	float h = 0.0;
	if (hash(vec2(cell, seed)) > 0.2) {
		float w = 0.55 + 0.3 * hash(vec2(cell, seed + 7.0));
		float off = (hash(vec2(cell, seed + 13.0)) - 0.5) * (1.0 - w);
		float d = abs(fx - 0.5 - off);
		float wh = wall * (0.8 + 0.4 * hash(vec2(cell, seed + 11.0)));
		if (d < w * 0.5) { h = wh + (w * 0.5 - d) * roof; }
		if (hash(vec2(cell, seed + 17.0)) > 0.5 && abs(fx - 0.5 - off - w * 0.22) < 0.03) { h = max(h, wh + w * 0.42 * roof); }
	}
	return h;
}
// Bare trees: a trunk and a scraggly crown.
float trees(vec2 p, float seed, float scale, float base) {
	float x = p.x * scale;
	float cell = floor(x);
	float fx = fract(x) - 0.5;
	float r = hash(vec2(cell, seed));
	if (r < 0.55) { return 0.0; }
	float th = base + 0.07 * hash(vec2(cell, seed + 3.0));
	float trunk = step(abs(fx), 0.018) * step(p.y, th * 0.7);
	vec2 q = vec2(fx / scale, p.y - th * 0.72);
	float crown = length(q * vec2(1.0, 1.25)) - th * 0.36 * (0.55 + 0.7 * fbm(vec2(x * 7.0, p.y * 40.0)));
	float twigs = step(0.56, fbm(vec2(x * 31.0, p.y * 140.0)) + 0.1 * smoothstep(0.0, -0.02, crown));
	float limbs = step(abs(fx + (p.y - th * 0.55) * 1.6 * sign(fx + 0.001)), 0.012) * step(th * 0.45, p.y) * step(p.y, th * 0.95);
	return max(max(trunk, limbs), step(crown, 0.0) * twigs);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + t_offset;
	vec2 p = vec2(uv.x * aspect, 1.0 - uv.y);
	vec3 fog = vec3(0.27, 0.28, 0.3);
	vec3 ink = vec3(0.022, 0.024, 0.03);
	// sky: dark above, thick grey haze toward the street
	vec3 col = mix(fog * 1.05, vec3(0.03, 0.035, 0.05), smoothstep(0.18, 0.95, p.y));
	// a moon lost somewhere behind the fog
	col += vec3(0.07, 0.075, 0.085) * exp(-pow(length((p - vec2(aspect * 0.7, 0.78)) * vec2(1.0, 1.4)) * 2.6, 2.0));
	// high drifting cloud
	col += vec3(0.03) * smoothstep(0.45, 0.85, fbm(vec2(p.x * 1.6 + t * 0.006, p.y * 4.0))) * smoothstep(0.35, 0.9, p.y);

	// far row of houses, almost swallowed
	float far = 0.3 + houses(p.x * 7.0 + 3.0, 1.0, 0.045, 0.1);
	if (p.y < far) { col = mix(ink, fog, 0.87); }
	col = mix(col, fog * 1.02, smoothstep(0.45, 0.9, fbm(vec2(p.x * 2.0 - t * 0.008, p.y * 6.0))) * smoothstep(0.42, 0.22, p.y) * 0.6);

	// middle row: houses and bare trees, one window still lit
	float mid = 0.19 + houses(p.x * 4.2 + 11.0, 5.0, 0.07, 0.14);
	float tr = trees(vec2(p.x, p.y - 0.19), 9.0, 9.0, 0.14);
	if (p.y < mid || tr > 0.5) { col = mix(ink, fog, 0.62); }
	vec2 w = vec2(aspect * 0.44, 0.215);
	if (abs(p.x - w.x) < 0.0045 && abs(p.y - w.y) < 0.007 && p.y < mid) {
		col = mix(vec3(0.7, 0.46, 0.2), fog * 0.6, 0.3) * (0.85 + 0.15 * sin(t * 7.0) * sin(t * 2.3));
	}
	col = mix(col, fog, smoothstep(0.4, 0.85, fbm(vec2(p.x * 2.6 + t * 0.014, p.y * 7.0 + 3.0))) * smoothstep(0.34, 0.1, p.y) * 0.65);
	// fog banks drifting across the rooftops
	float bank = fbm(vec2(p.x * 1.3 + t * 0.022, p.y * 3.2 - t * 0.005) + vec2(fbm(p * 2.0 + t * 0.01), 0.0) * 0.6);
	col = mix(col, fog * 1.12, smoothstep(0.42, 0.8, bank) * smoothstep(0.6, 0.16, p.y) * 0.7);

	// near: kerb, fence, poles and wires, the siren mast
	float near_ground = 0.11;
	float fence = step(p.y, near_ground + 0.045) * step(0.42, fract(p.x * 42.0)) * step(p.y, near_ground + 0.045 - 0.006 * step(0.7, fract(p.x * 42.0)));
	fence = max(fence, step(abs(p.y - near_ground - 0.03), 0.0025));
	float pole_f = fract(p.x * 1.15 + 0.35);
	float pole = step(abs(pole_f - 0.5), 0.0038) * step(p.y, 0.6);
	pole = max(pole, step(abs(pole_f - 0.5), 0.03) * step(abs(p.y - 0.57), 0.003));
	float sag = 0.555 - 0.05 * sin(3.14159 * fract(p.x * 1.15 + 0.85));
	float wires = smoothstep(0.0022, 0.0, abs(p.y - sag)) + smoothstep(0.0018, 0.0, abs(p.y - sag + 0.018));
	// the mast
	float mx = aspect * 0.76;
	float hy = 0.8;
	float dx = p.x - mx;
	float mast = step(abs(dx), 0.006 + 0.004 * (1.0 - p.y / hy)) * step(p.y, hy);
	float housing = step(abs(dx), 0.02) * step(abs(p.y - hy - 0.004), 0.022);
	float cap = step(abs(dx), 0.008) * step(abs(p.y - hy - 0.034), 0.008);
	float horn_l = step(-0.085, dx) * step(dx, -0.018) * step(abs(p.y - hy), 0.009 + (-dx - 0.018) * 0.28);
	float horn_r = step(0.018, dx) * step(dx, 0.085) * step(abs(p.y - hy), 0.009 + (dx - 0.018) * 0.28);
	float platform = step(abs(dx), 0.05) * step(abs(p.y - hy + 0.06), 0.003);
	float rail = step(abs(abs(dx) - 0.048), 0.0018) * step(abs(p.y - hy + 0.045), 0.015);
	float arm = step(abs(p.y - (hy - 0.16) + dx * 0.05), 0.0025) * step(0.0, dx) * step(dx, 0.07);
	float cable = smoothstep(0.0022, 0.0, abs(dx - 0.07 - 0.01 * sin(t * 0.6) * (hy - 0.16 - p.y) * 3.0)) * step(hy - 0.34, p.y) * step(p.y, hy - 0.16);
	float siren = max(max(max(mast, housing), max(cap, max(horn_l, horn_r))), max(max(platform, rail), max(arm, cable)));
	float near_ink = max(max(fence, pole), siren);
	col = mix(col, mix(ink, fog, 0.1), clamp(wires, 0.0, 1.0) * 0.85);
	if (near_ink > 0.5) { col = mix(ink, fog, 0.14 + 0.2 * smoothstep(0.5, 0.95, p.y)); }
	// street
	if (p.y < near_ground) {
		col = mix(vec3(0.05, 0.052, 0.058), fog * 0.75, smoothstep(0.0, near_ground, p.y) * 0.6);
		col += vec3(0.012) * step(abs(p.y - near_ground * 0.45), 0.002) * step(0.5, fract(p.x * 3.0));
	}
	// thick ground fog rolling slowly across the street
	float gf = fbm(vec2(p.x * 1.8 + t * 0.025, p.y * 5.0 - t * 0.004));
	float gf2 = fbm(vec2(p.x * 3.5 - t * 0.017, p.y * 9.0 + 7.0));
	float dens = smoothstep(0.58, 0.02, p.y) * (0.38 + 0.62 * gf) + smoothstep(0.3, 0.0, p.y) * 0.3 * gf2;
	col = mix(col, fog * (0.92 + 0.28 * gf2), clamp(dens, 0.0, 0.9));
	// darker on the left, where the menu sits; vignette; grain
	col *= mix(0.4, 1.0, smoothstep(0.05, 0.62, uv.x));
	col *= smoothstep(1.25, 0.35, length((uv - vec2(0.55, 0.5)) * vec2(1.1, 1.3)));
	col += (hash(uv * 911.0 + fract(t * 0.7)) - 0.5) * 0.022;
	COLOR = vec4(col, 1.0);
}
"""

const BUTTONS := [["NewGame", "New Game"], ["Continue", "Continue"], ["Settings", "Settings"], ["Experiments", "Visual Experiments"], ["Quit", "Quit"]]

## Tests replace this to observe scene changes: func(path: String).
var scene_changer: Callable
var transition_time := 0.4
var save_info := {}

var _buttons := {}
var _status: Label
var _confirm: ConfirmDialog
var _difficulty: DifficultyDialog
var _settings: SettingsPanel
var _bg: ColorRect
var _fader: ColorRect
var _leaving := false


func _init() -> void:
	scene_changer = func(path: String) -> void: get_tree().change_scene_to_file(path)


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_custom_mouse_cursor(null)
	GameSettings.apply()
	Sfx.attach(self)
	_build()
	refresh_save_info()
	Sfx.music("music/menu")
	_focus_first()
	_fader.color.a = 1.0
	create_tween().tween_property(_fader, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	if GameLaunch.notice != "":
		var n := GameLaunch.notice
		GameLaunch.notice = ""
		_confirm.inform(n, "OK", "Notice")
	resized.connect(_on_resized)
	_on_resized()


func button(id: String) -> Button:
	return _buttons.get(id)


## Re-reads SaveGame.info() and updates Continue (enabled only for a valid save).
func refresh_save_info() -> void:
	save_info = SaveGame.info()
	var b: Button = _buttons["Continue"]
	var valid := bool(save_info.get("valid", false))
	b.disabled = not valid
	_status.text = ""
	_status.visible = false
	if valid:
		var sm = save_info.get("summary", {})
		UiTheme.set_caption(b, UiTheme.save_summary_text(sm if typeof(sm) == TYPE_DICTIONARY else {}))
	elif not save_info.get("exists", false):
		UiTheme.set_caption(b, "No saved game")
	else:
		UiTheme.set_caption(b, "Can't be loaded")
		_status.text = str(save_info.get("error", "The save file can't be read."))
		_status.visible = true


func new_game() -> void:
	if _leaving or _confirm.is_open or _difficulty.is_open:
		return
	if SaveGame.info().get("exists", false):
		_confirm.ask("This will overwrite your current survival run.", "Start a new run", "Cancel", "New game")
		var yes: bool = await _confirm.answered
		if not yes:
			_focus(_buttons["NewGame"])
			return
	_difficulty.ask(GameLaunch.difficulty)
	var level: String = await _difficulty.answered
	if level == "":
		_focus(_buttons["NewGame"])
		return
	GameLaunch.difficulty = Difficulty.valid(level)
	GameLaunch.mode = "new"
	_leave(GameLaunch.GAME_SCENE)


func continue_game() -> void:
	if _leaving or (_buttons["Continue"] as Button).disabled:
		return
	GameLaunch.mode = "continue"
	_leave(GameLaunch.GAME_SCENE)


func open_settings() -> void:
	if _leaving:
		return
	_settings.open()


func open_experiments() -> void:
	_leave(GameLaunch.EXPERIMENTS_SCENE)


func quit_game() -> void:
	Sfx.music("")
	get_tree().quit()


func _leave(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.music("")
	for id in _buttons:
		(_buttons[id] as Button).focus_mode = Control.FOCUS_NONE
	if transition_time <= 0.0:
		scene_changer.call(path)
		return
	var tw := create_tween()
	tw.tween_property(_fader, "color:a", 1.0, transition_time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): scene_changer.call(path))


func _focus_first() -> void:
	for id in ["Continue", "NewGame"]:
		var b: Button = _buttons[id]
		if not b.disabled:
			_focus(b)
			return


func _focus(c: Control) -> void:
	UiTheme.focus_quietly(c)


func _on_resized() -> void:
	if _bg != null and size.y > 0.0:
		(_bg.material as ShaderMaterial).set_shader_parameter("aspect", size.x / size.y)


func _build() -> void:
	theme = UiTheme.theme()
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	mat.shader = sh
	mat.set_shader_parameter("t_offset", 40.0)
	_bg.material = mat
	add_child(_bg)

	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.anchor_top = 0.0
	menu.anchor_bottom = 1.0
	menu.offset_left = 128
	menu.offset_right = 128 + 520
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 10)
	add_child(menu)

	var title := UiTheme.make_label("SIRENS WENT QUIET", 50, UiTheme.TEXT)
	title.name = "Title"
	title.add_theme_font_override("font", UiTheme.tracked_font(7))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	menu.add_child(title)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(64, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.add_child(rule)
	var sub := UiTheme.make_label("The grid is gone. The fog stays. You still have the house.", UiTheme.FONT_BODY, UiTheme.TEXT_DIM)
	sub.name = "Subtitle"
	menu.add_child(sub)
	menu.add_child(UiTheme.make_spacer(34))

	var actions := {"NewGame": new_game, "Continue": continue_game, "Settings": open_settings, "Experiments": open_experiments, "Quit": quit_game}
	for it in BUTTONS:
		var b := UiTheme.make_button(it[1])
		b.name = it[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(420, 46)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(actions[it[0]])
		menu.add_child(b)
		_buttons[it[0]] = b
	_status = UiTheme.make_caption("", 420, UiTheme.WARN)
	_status.name = "SaveStatus"
	menu.add_child(_status)

	var foot := UiTheme.make_label("Experiment 003 · Foundations of Survival · %s" % str(ProjectSettings.get_setting("application/config/version", "")), 12, UiTheme.TEXT_FAINT)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 128
	foot.offset_bottom = -26
	foot.offset_top = -26
	add_child(foot)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 18)
	keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.offset_right = -32
	keys.offset_left = -32
	keys.offset_bottom = -24
	keys.offset_top = -24
	keys.add_child(UiTheme.make_key_hint("Up / Down", "Select", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	keys.add_child(UiTheme.make_key_hint("Enter", "Confirm", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	add_child(keys)

	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)
	_difficulty = DifficultyDialog.new()
	_difficulty.name = "Difficulty"
	add_child(_difficulty)
	_settings = SettingsPanel.new()
	_settings.name = "Settings"
	add_child(_settings)
	_settings.closed.connect(func(): _focus(_buttons["Settings"]))

	_fader = ColorRect.new()
	_fader.name = "Fader"
	_fader.color = Color(0, 0, 0, 0)
	_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fader)


func settings_panel() -> SettingsPanel:
	return _settings


func confirm_dialog() -> ConfirmDialog:
	return _confirm


func difficulty_dialog() -> DifficultyDialog:
	return _difficulty
