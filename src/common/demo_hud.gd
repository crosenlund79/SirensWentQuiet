class_name DemoHud
extends CanvasLayer
## Minimal shared shell for every version: title, controls reference, a tiny
## stats line, day/night state, reset and return-to-launcher.
##
## Usage (in a version's root _ready):
##   hud = DemoHud.new()
##   hud.title = "A - True 3D Voxels"
##   add_child(hud)
##   hud.night_changed.connect(_on_night_changed)   # also read hud.is_night
##
## Command-line user args (after `--`), handy for screenshots and checks:
##   --night               start in the night state
##   --hide-help           start with the controls panel hidden
##   --capture=PATH        save a PNG of the screen after --capture-at seconds, then quit
##   --capture-at=SECONDS  default 4.0
##   --no-quit             keep running after the capture

signal night_changed(night: bool)

const LAUNCHER_SCENE := "res://src/launcher/launcher.tscn"
const CONTROLS := "WASD  move     Mouse  aim     LMB  shoot     Wheel  zoom\nN  day / night     R  reset     Esc  launcher     H  help     F3  stats"

var title := "Version"
var subtitle := ""
var is_night := false
var stats_text := ""   ## optional version-specific line shown under the FPS

var _help: PanelContainer
var _stats: Label
var _mode: Label
var _show_stats := true
var _capture_path := ""
var _capture_at := 4.0
var _quit_after_capture := true
var _elapsed := 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_install_crosshair()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--night":
			is_night = true
		elif a == "--hide-help":
			_help.visible = false
		elif a.begins_with("--capture="):
			_capture_path = a.trim_prefix("--capture=")
		elif a.begins_with("--capture-at="):
			_capture_at = float(a.trim_prefix("--capture-at="))
		elif a == "--no-quit":
			_quit_after_capture = false
	_refresh_mode()
	# Children are ready before their parent: tell the version after its _ready.
	_emit_initial.call_deferred()


func _emit_initial() -> void:
	night_changed.emit(is_night)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


func set_night(night: bool) -> void:
	if night == is_night:
		return
	is_night = night
	_refresh_mode()
	night_changed.emit(is_night)


func toggle_night() -> void:
	set_night(not is_night)


func reset_level() -> void:
	get_tree().reload_current_scene()


func back_to_launcher() -> void:
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_day_night"):
		toggle_night()
	elif event.is_action_pressed("reset_level"):
		get_viewport().set_input_as_handled()   # before the scene (and this node) goes away
		reset_level()
		return
	elif event.is_action_pressed("back_to_launcher"):
		get_viewport().set_input_as_handled()
		back_to_launcher()
		return
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_stats"):
		_show_stats = not _show_stats
		_stats.visible = _show_stats
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta
	if _show_stats:
		var t := "%d fps" % Engine.get_frames_per_second()
		t += "   %d draw calls" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		if stats_text != "":
			t += "\n" + stats_text
		_stats.text = t
	if _capture_path != "" and _elapsed >= _capture_at:
		var path := _capture_path
		_capture_path = ""
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("DemoHud: captured ", path)
		if _quit_after_capture:
			get_tree().quit()


func _refresh_mode() -> void:
	if _mode != null:
		_mode.text = "NIGHT" if is_night else "DAY"
		_mode.add_theme_color_override("font_color", Color(0.62, 0.7, 1.0) if is_night else Color(1.0, 0.86, 0.6))


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var head := VBoxContainer.new()
	head.position = Vector2(22, 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)
	row.add_child(_label(title, 22, Color(0.93, 0.9, 0.84)))
	_mode = _label("DAY", 15, Color(1, 0.86, 0.6))
	_mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_mode)
	if subtitle != "":
		head.add_child(_label(subtitle, 14, Color(0.7, 0.68, 0.64)))

	_stats = _label("", 13, Color(0.75, 0.78, 0.75))
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.offset_left = -760
	_stats.offset_right = -20
	_stats.offset_top = 16
	root.add_child(_stats)

	_help = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.62)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	_help.add_theme_stylebox_override("panel", sb)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 20
	_help.offset_bottom = -18
	_help.offset_top = -78
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(_label(CONTROLS, 14, Color(0.86, 0.85, 0.82)))
	root.add_child(_help)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _install_crosshair() -> void:
	# User-replaceable via custom/graphics/common/crosshair.png
	var tex := AssetResolver.get_texture("common/crosshair")
	if tex != null:
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, tex.get_size() * 0.5)
