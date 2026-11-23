class_name IntroOverlay
extends CanvasLayer
## A few lines over black at the start of a new run (SPEC §7.8). Owner: U.
## About 9 s; any key or click skips. Emits `done` exactly once, after the
## black has faded away (or after the short skip fade).

signal done

const LINES := [
	"On the ninth day, the sirens went quiet.",
	"Nobody has answered since.",
	"Then the fog came in, and it stayed.",
	"You still have the house.",
]
const LINE_IN := 0.6
const LINE_HOLD := 1.0
const LINE_OUT := 0.5
const REVEAL := 0.8
const SKIP_FADE := 0.35

var is_playing := false
var _finished := false
var _black: ColorRect
var _line: Label
var _hint: Control
var _tween: Tween


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## Total length when not skipped (seconds).
static func duration() -> float:
	return LINES.size() * (LINE_IN + LINE_HOLD + LINE_OUT) + REVEAL


func play() -> void:
	_finished = false
	is_playing = true
	visible = true
	_build()
	if not is_inside_tree():
		_finish()
		return
	_tween = create_tween()
	for i in LINES.size():
		_tween.tween_callback(_set_line.bind(i))
		_tween.tween_property(_line, "modulate:a", 1.0, LINE_IN).set_trans(Tween.TRANS_SINE)
		_tween.tween_interval(LINE_HOLD)
		_tween.tween_property(_line, "modulate:a", 0.0, LINE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_hint, "modulate:a", 0.0, 0.2)
	_tween.tween_property(_black, "modulate:a", 0.0, REVEAL).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_finish)


## Skips to the end with a short fade (any key or click does this).
func skip() -> void:
	if not is_playing or _finished:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_line, "modulate:a", 0.0, SKIP_FADE * 0.6)
	_tween.tween_property(_hint, "modulate:a", 0.0, SKIP_FADE * 0.6)
	_tween.tween_property(_black, "modulate:a", 0.0, SKIP_FADE)
	_tween.chain().tween_callback(_finish)


func _set_line(i: int) -> void:
	_line.text = LINES[i]
	_line.modulate.a = 0.0
	var last := i == LINES.size() - 1
	_line.add_theme_color_override("font_color", UiTheme.ACCENT if last else UiTheme.TEXT)
	_line.add_theme_font_size_override("font_size", 28 if last else 24)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	is_playing = false
	visible = false
	done.emit()


func _input(event: InputEvent) -> void:
	if not is_playing:
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var click: bool = event is InputEventMouseButton and event.pressed
	if key or click:
		get_viewport().set_input_as_handled()
		skip()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiTheme.theme()
	add_child(root)
	_black = ColorRect.new()
	_black.color = Color(0.008, 0.009, 0.012)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)
	_line = UiTheme.make_label("", 24)
	_line.add_theme_font_override("font", UiTheme.tracked_font(1))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line.modulate.a = 0.0
	_black.add_child(_line)
	var hint := UiTheme.make_key_hint("Any key", "Skip", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -28
	hint.offset_bottom = -24
	hint.modulate.a = 0.7
	root.add_child(hint)
	_hint = hint
