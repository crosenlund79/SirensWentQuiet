class_name UiToggle
extends Button
## On/off button in the house style: label on the left, a small pill switch on
## the right (amber when on). Owner: U. Create with UiTheme.make_toggle().

const PILL := Vector2(30, 14)


func _init() -> void:
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = UiTheme.BUTTON_HEIGHT
	toggled.connect(func(_on): queue_redraw())


func _ready() -> void:
	# room for the pill on the right
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := UiTheme.button_style(state)
		if state == "pressed" or state == "hover_pressed":
			sb = UiTheme.button_style("hover" if state == "hover_pressed" else "normal")
		sb.content_margin_right = 16 + PILL.x + 10
		add_theme_stylebox_override(state, sb)
	add_theme_color_override("font_pressed_color", UiTheme.TEXT)


func _draw() -> void:
	var r := Rect2(Vector2(size.x - 16 - PILL.x, (size.y - PILL.y) * 0.5), PILL)
	var on := button_pressed
	var track := StyleBoxFlat.new()
	track.set_corner_radius_all(int(PILL.y * 0.5))
	track.bg_color = Color(UiTheme.ACCENT, 0.5) if on else Color(1, 1, 1, 0.1)
	track.border_color = Color(UiTheme.ACCENT, 0.9) if on else Color(1, 1, 1, 0.2)
	track.set_border_width_all(1)
	if disabled:
		track.bg_color.a *= 0.4
		track.border_color.a *= 0.4
	draw_style_box(track, r)
	var kx := r.end.x - PILL.y * 0.5 if on else r.position.x + PILL.y * 0.5
	var knob := Color(1, 0.92, 0.8) if on else UiTheme.TEXT_DIM
	if disabled:
		knob = UiTheme.TEXT_FAINT
	draw_circle(Vector2(kx, r.get_center().y), PILL.y * 0.5 - 2.0, knob)
