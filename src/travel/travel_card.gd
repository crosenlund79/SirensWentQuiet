extends CanvasLayer
## Exp 008 (T): the short title card of a departure or an arrival (the user's
## §5: "a short fade with a title card ... nothing long").
##
##   Arrival (a new scene, from black):   "Hardware Store" / "Day 3, 10:42"
##   Departure (over the map, from dim):  "Leaving Pine Woods" /
##                                        "Day 3, 10:42 · on foot to the Medical Clinic"
##
## A full-screen scrim with a centred title and one line under it: it holds
## for `hold` seconds, then the scrim and the card fade out over `fade`
## seconds and the node frees itself. It never blocks the mouse or the game
## (nothing pauses for it). Space skips it when `skippable` (the arrival; on
## departure Space belongs to the map, which skips the trip). Above the map
## (65), below the pause menu (70).

signal finished

const LAYER := 66

var skippable := true

var _scrim: ColorRect
var _box: VBoxContainer
var _title: Label
var _sub: Label
var _tween: Tween
var _done := false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build() -> void:
	if _scrim != null:
		return
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.0, 0.006, 0.012, 1.0)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	_box = VBoxContainer.new()
	_box.name = "Card"
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_title = UiTheme.make_title("", UiTheme.FONT_BIG)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(rule)
	_sub = UiTheme.make_label("", UiTheme.FONT_LARGE, UiTheme.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_sub)


## Shows the card: the scrim starts at `dim` (1 = black), holds, then fades.
func play(title: String, sub: String, dim := 1.0, hold := 0.7, fade := 0.55) -> void:
	_build()
	_title.text = title
	_sub.text = sub
	_scrim.color.a = clampf(dim, 0.0, 1.0)
	_box.modulate.a = 1.0
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_interval(maxf(hold, 0.0))
	_tween.tween_property(_scrim, "color:a", 0.0, maxf(fade, 0.01))
	_tween.parallel().tween_property(_box, "modulate:a", 0.0, maxf(fade, 0.01))
	_tween.tween_callback(_end)


## Ends the card now (Space, or the trip it introduced is over).
func skip() -> void:
	if _done:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_inside_tree() and _scrim != null and _scrim.color.a > 0.05:
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.tween_property(_scrim, "color:a", 0.0, 0.12)
		_tween.parallel().tween_property(_box, "modulate:a", 0.0, 0.12)
		_tween.tween_callback(_end)
	else:
		_end()


func is_showing() -> bool:
	return not _done and _scrim != null


func title_text() -> String:
	return _title.text if _title != null else ""


func sub_text() -> String:
	return _sub.text if _sub != null else ""


func _end() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not skippable or _done:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		skip()
