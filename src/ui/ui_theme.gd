class_name UiTheme
extends RefCounted
## One visual language for every menu and panel (SPEC §8). Owner: U.
## Dark translucent panels, warm off-white text, one amber accent (the siren).

const BG := Color(0.035, 0.037, 0.045, 0.86)
const BG_SOLID := Color(0.03, 0.032, 0.04, 1.0)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color(0.92, 0.89, 0.83)
const TEXT_DIM := Color(0.66, 0.64, 0.6)
const ACCENT := Color(0.95, 0.62, 0.22)
const GOOD := Color(0.56, 0.82, 0.55)
const WARN := Color(0.98, 0.78, 0.36)
const BAD := Color(0.94, 0.38, 0.32)

static var _theme: Theme


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 3)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(1, 1, 1, 0.05), "hover": Color(0.95, 0.62, 0.22, 0.18), "pressed": Color(0.95, 0.62, 0.22, 0.3), "disabled": Color(1, 1, 1, 0.02), "focus": Color(0, 0, 0, 0)}[state]
		sb.border_color = ACCENT if state in ["hover", "focus"] else LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.88))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.49, 0.47))
	_theme = t
	return t


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(18)
	return sb


static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	return p


static func make_title(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func make_label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	return b
