extends CanvasLayer
## Full-screen fade to black (sleep), with an optional line of text. Runs while
## the tree is paused. Never blocks the mouse.

var _rect: ColorRect
var _label: Label


func _ready() -> void:
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_label = UiTheme.make_label("", 22, UiTheme.TEXT_DIM)
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)


func alpha() -> float:
	return _rect.color.a if _rect != null else 0.0


func set_alpha(a: float) -> void:
	if _rect != null:
		_rect.color.a = a
		_label.modulate.a = a


func set_text(text: String) -> void:
	if _label != null:
		_label.text = text


## Tweens to `a` over `seconds` (awaitable).
func fade_to(a: float, seconds: float) -> void:
	if _rect == null or seconds <= 0.0 or not is_inside_tree():
		set_alpha(a)
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(set_alpha, alpha(), a, seconds)
	await tw.finished
