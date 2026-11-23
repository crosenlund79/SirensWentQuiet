class_name UiTheme
extends RefCounted
## One visual language for every menu, panel and HUD element (SPEC §8). Owner: U.
##
## Dark translucent panels, warm off-white text, one amber accent (the siren),
## small-caps headings (upper case at a reduced size with wide tracking), the
## same button everywhere and the same short fades. Other modules (the build
## palette, the expedition screens) use these helpers instead of styling their
## own controls; see docs/experiment-002/ui.md for the rules and examples.
##
##   var panel := UiTheme.make_panel()                 # themed PanelContainer
##   box.add_child(UiTheme.make_title("Into the fog")) # panel heading (accent)
##   box.add_child(UiTheme.make_section("Supplies"))   # small-caps rule
##   box.add_child(UiTheme.make_button("Go", "2 h"))   # button + right caption
##   box.add_child(UiTheme.make_key_hint("E", "Search"))
##
## A whole modal screen with scrim, fade and Esc handling: extend UiModal.

# --- palette ------------------------------------------------------------------
const BG := Color(0.035, 0.037, 0.045, 0.86)        ## panels
const BG_SOLID := Color(0.03, 0.032, 0.04, 1.0)     ## full-screen backgrounds
const BG_SOFT := Color(0.03, 0.032, 0.04, 0.58)     ## HUD cards (lighter, over the game)
const SCRIM := Color(0.0, 0.0, 0.0, 0.5)            ## behind modal panels
const LINE := Color(1, 1, 1, 0.09)                  ## hairlines and borders
const LINE_STRONG := Color(1, 1, 1, 0.18)
const TEXT := Color(0.92, 0.89, 0.83)               ## warm off-white
const TEXT_DIM := Color(0.66, 0.64, 0.6)
const TEXT_FAINT := Color(0.46, 0.45, 0.43)
const ACCENT := Color(0.95, 0.62, 0.22)             ## the siren amber (the one accent)
const ACCENT_SOFT := Color(0.95, 0.62, 0.22, 0.16)
const GOOD := Color(0.56, 0.82, 0.55)
const WARN := Color(0.98, 0.74, 0.32)
const BAD := Color(0.94, 0.38, 0.32)
const INFO := TEXT
const KIND_COLORS := {"info": TEXT, "good": GOOD, "warn": WARN, "bad": BAD}

# --- metrics ------------------------------------------------------------------
const FONT_SMALL := 13
const FONT_BODY := 16
const FONT_LARGE := 19
const FONT_TITLE := 22
const PAD := 18          ## panel content margin
const GAP := 10          ## vertical rhythm between rows
const RADIUS := 4
const BUTTON_HEIGHT := 38
const FADE_IN := 0.16    ## seconds; every panel uses the same fades
const FADE_OUT := 0.12

static var _theme: Theme
static var _fonts := {}
static var _quiet_until := 0


# --- theme --------------------------------------------------------------------

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)
	# panels
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	# buttons: one style everywhere; hover/focus draw the amber siren stripe
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(state, "Button", button_style(state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.96, 0.9))
	t.set_color("font_pressed_color", "Button", Color(1, 0.86, 0.68))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.86, 0.68))
	t.set_color("font_focus_color", "Button", Color(1, 0.96, 0.9))
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_constant("h_separation", "Button", 8)
	# separators
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 9)
	var vsep := StyleBoxLine.new()
	vsep.color = LINE
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	# sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.1)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(ACCENT, 0.75)
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := track.duplicate() as StyleBoxFlat
	fill_hi.bg_color = ACCENT
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _dot_texture(14, TEXT))
	t.set_icon("grabber_highlight", "HSlider", _dot_texture(14, Color(1, 0.9, 0.75)))
	t.set_icon("grabber_disabled", "HSlider", _dot_texture(14, TEXT_FAINT))
	var slider_focus := StyleBoxFlat.new()
	slider_focus.draw_center = false
	slider_focus.border_color = Color(ACCENT, 0.6)
	slider_focus.set_border_width_all(1)
	slider_focus.set_corner_radius_all(3)
	slider_focus.set_expand_margin_all(4)
	t.set_stylebox("focus", "HSlider", slider_focus)
	# scrolling
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(1, 1, 1, 0.03)
	bar.set_corner_radius_all(3)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("scroll_focus", "VScrollBar", bar)
	for g in [["grabber", Color(1, 1, 1, 0.18)], ["grabber_highlight", Color(ACCENT, 0.55)], ["grabber_pressed", ACCENT]]:
		var gs := StyleBoxFlat.new()
		gs.bg_color = g[1]
		gs.set_corner_radius_all(3)
		t.set_stylebox(g[0], "VScrollBar", gs)
	# tooltips and rich text
	var tip := panel_style()
	tip.bg_color = BG_SOLID
	tip.shadow_size = 0
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FONT_SMALL + 1)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", FONT_SMALL + 1)
	t.set_font_size("bold_font_size", "RichTextLabel", FONT_SMALL + 1)
	# progress bars (if a module wants a plain one; UiStatBar is preferred)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.08)
	pb_bg.set_corner_radius_all(2)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := pb_bg.duplicate() as StyleBoxFlat
	pb_fill.bg_color = Color(TEXT, 0.85)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	_theme = t
	return t


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(RADIUS)
	sb.set_content_margin_all(PAD)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	return sb


## The compact card used by the HUD (lighter, smaller margins, no shadow).
static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_SOFT
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(RADIUS)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func button_style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	match state:
		"normal":
			sb.bg_color = Color(1, 1, 1, 0.045)
			sb.border_color = LINE
		"hover":
			sb.bg_color = Color(ACCENT, 0.13)
			sb.border_color = Color(ACCENT, 0.55)
			sb.border_width_left = 3
		"pressed", "hover_pressed":
			sb.bg_color = Color(ACCENT, 0.26)
			sb.border_color = Color(ACCENT, 0.8)
			sb.border_width_left = 3
		"disabled":
			sb.bg_color = Color(1, 1, 1, 0.018)
			sb.border_color = Color(1, 1, 1, 0.04)
		"focus":
			sb.draw_center = false
			sb.border_color = Color(ACCENT, 0.85)
			sb.border_width_left = 3
	return sb


## Upper case with wide tracking: the "small caps" heading face.
static func tracked_font(spacing := 2) -> Font:
	if not _fonts.has(spacing):
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.spacing_glyph = spacing
		_fonts[spacing] = f
	return _fonts[spacing]


# --- building blocks ----------------------------------------------------------

static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	return p


## Translucent HUD card (same language, lighter than a panel).
static func make_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.add_theme_stylebox_override("panel", card_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Panel heading: small caps in the accent colour.
static func make_title(text: String, size := FONT_TITLE) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", tracked_font(3 if size >= 20 else 2))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


## Section header: dim small caps followed by a hairline.
static func make_section(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", tracked_font(2))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(l)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.theme = theme()
	row.add_child(line)
	row.name = "Section"
	return row


static func make_label(text: String, size := FONT_BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Dim explanatory text. With `width` > 0 it wraps at that width.
static func make_caption(text: String, width := 0.0, color := TEXT_DIM) -> Label:
	var l := make_label(text, FONT_SMALL + 1, color)
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = width
	return l


## A label that stays legible over the bright day and the dark night scene.
static func make_hud_label(text: String, size := FONT_BODY, color := TEXT) -> Label:
	var l := make_label(text, size, color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The one button. `caption` (optional) is a dim note on the right, e.g. a
## cost, a time or the reason a button is disabled. Plays hover/click sounds.
static func make_button(text: String, caption := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = BUTTON_HEIGHT
	if caption != "":
		set_caption(b, caption)
	wire_sounds(b)
	return b


## Sets (or clears with "") the right-aligned caption of a make_button().
static func set_caption(b: Button, caption: String) -> void:
	var l: Label = b.get_node_or_null("Caption")
	if caption == "":
		if l != null:
			l.text = ""
			l.visible = false
		return
	if l == null:
		l = make_label("", FONT_SMALL, TEXT_DIM)
		l.name = "Caption"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		l.offset_left = -300
		l.offset_right = -14
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.visible = true
	l.text = caption


static func caption_of(b: Button) -> String:
	var l: Label = b.get_node_or_null("Caption")
	return l.text if l != null else ""


## Keyboard-key chip ("E", "Esc", "LMB").
static func make_key_chip(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.09)
	sb.border_color = Color(1, 1, 1, 0.28)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := make_label(key, FONT_SMALL - 1, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 10
	p.add_child(l)
	p.name = "Key"
	return p


## One or more key chips followed by a label: make_key_hint("I / Tab", "Inventory").
## Keys separated by " / " become separate chips.
static func make_key_hint(keys: String, text: String, size := FONT_SMALL + 1, color := TEXT_DIM) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := keys.split(" / ", false)
	for i in parts.size():
		if i > 0:
			row.add_child(make_label("/", FONT_SMALL, TEXT_FAINT))
		row.add_child(make_key_chip(parts[i]))
	var gap := Control.new()
	gap.custom_minimum_size.x = 3
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var l := make_label(text, size, color)
	l.name = "Text"
	row.add_child(l)
	return row


static func make_stat_bar(kind: String, label := "") -> UiStatBar:
	var s := UiStatBar.new()
	s.kind = kind
	s.label = label if label != "" else kind.capitalize()
	return s


static func make_toggle(text: String, on := false) -> UiToggle:
	var t := UiToggle.new()
	t.text = text
	t.theme = theme()
	t.button_pressed = on
	wire_sounds(t)
	return t


static func make_slider(min_value := 0.0, max_value := 1.0, step := 0.01) -> HSlider:
	var s := HSlider.new()
	s.theme = theme()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(180, 20)
	return s


static func make_icon(kind: String, size := 18.0, color := TEXT) -> UiIcon:
	var i := UiIcon.new()
	i.kind = kind
	i.color = color
	i.custom_minimum_size = Vector2(size, size)
	return i


## Full-screen dimmer that also swallows clicks meant for the game.
static func make_scrim(color := SCRIM) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.name = "Scrim"
	return r


static func make_spacer(height := GAP) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# --- text helpers -------------------------------------------------------------

## "Day 3 · 21:40"
static func day_time_text(day: int, clock: String) -> String:
	return "Day %d · %s" % [day, clock]


## Formats the game's save summary ("Day 4 · 21:15"). Reads "text" if the
## game provides one, else "day" + "clock"/"time", else "total_minutes".
static func save_summary_text(summary: Dictionary) -> String:
	if summary.has("text") and str(summary["text"]) != "":
		return str(summary["text"])
	var day := int(summary.get("day", 0))
	var clock := str(summary.get("clock", summary.get("time", "")))
	if summary.has("total_minutes"):
		var tm := float(summary["total_minutes"])
		if day <= 0:
			day = int(floor(tm / 1440.0)) + 1
		if clock == "":
			clock = clock_from_minutes(tm)
	if day <= 0:
		return "Saved run"
	return day_time_text(day, clock) if clock != "" else "Day %d" % day


static func clock_from_minutes(minute_of_day: float) -> String:
	var m := int(fposmod(minute_of_day, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]


static func duration_text(minutes: float) -> String:
	var m := int(round(minutes))
	if m < 60:
		return "%d min" % m
	if m % 60 == 0:
		return "%d h" % (m / 60)
	return "%d h %02d" % [m / 60, m % 60]


# --- sound and motion ---------------------------------------------------------

static func wire_sounds(b: BaseButton) -> void:
	b.mouse_entered.connect(func():
		if not b.disabled:
			ui_sound("ui/hover"))
	b.focus_entered.connect(func(): ui_sound("ui/hover"))
	b.pressed.connect(func(): ui_sound("ui/click"))


## UI sound, skipped while a panel is grabbing focus programmatically.
static func ui_sound(name: String) -> void:
	if Time.get_ticks_msec() < _quiet_until:
		return
	Sfx.ui(name)


## Gives keyboard focus without the hover sound.
static func focus_quietly(c: Control) -> void:
	if c == null or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	_quiet_until = Time.get_ticks_msec() + 30
	c.grab_focus()


## First enabled, focusable, visible button under `root` (depth first).
static func first_focusable(root: Node) -> Control:
	for c in root.get_children():
		if c is BaseButton:
			var b := c as BaseButton
			if not b.disabled and b.focus_mode != Control.FOCUS_NONE and b.visible:
				return b
		var inner := first_focusable(c)
		if inner != null:
			return inner
	return null


## Standard fade of a CanvasItem's alpha.
static func fade(item: CanvasItem, to_alpha: float, time := FADE_IN) -> Tween:
	var tw := item.create_tween()
	tw.tween_property(item, "modulate:a", to_alpha, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tw


static func _dot_texture(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x - c, y - c).length()
			var a := clampf(c - dist + 0.5, 0.0, 1.0)
			var ring := clampf(dist - (c - 2.2), 0.0, 1.0) * 0.35
			img.set_pixel(x, y, Color(color.r * (1.0 - ring), color.g * (1.0 - ring), color.b * (1.0 - ring), a))
	return ImageTexture.create_from_image(img)
