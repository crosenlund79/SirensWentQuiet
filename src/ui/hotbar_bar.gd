class_name HotbarBar
extends Control
## The quick-access bar on the HUD (Experiment 004, E): eight slots at the
## bottom centre with the key (1-8), a small glyph, a short name and the count
## (rounds in the magazine for weapons). The selected slot has an accent
## frame; an empty-handed bar (X, or an empty slot) shows "Hands empty".
## One Control drawn with CanvasItem primitives and redrawn only when what it
## shows changes (show_slots). The game helper (src/game/game_hotbar.gd) owns
## it, feeds it and hides it in build mode and while panels are open.

const SLOT := Vector2(66, 58)
const GAP := 6.0
const MARGIN_BOTTOM := 18.0
const SHORT := {
	"handgun": "Handgun", "shotgun": "Shotgun", "canned_food": "Cans", "snacks": "Snacks", "water": "Water",
	"bandage": "Bandage", "medkit": "Medkit", "hammer": "Hammer", "crowbar": "Crowbar", "shovel": "Shovel",
	"flashlight": "Light", "vest": "Vest", "backpack": "Pack",
}
const GLYPH := {"food": "food", "water": "water", "medical": "health", "weapon": "ammo"}

var slots: Array = []          ## [{"id", "count", "owned"}] x Hotbar.SIZE
var selected := 0
var holstered := false
var light_on := false
var _key := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var w := Hotbar.SIZE * SLOT.x + (Hotbar.SIZE - 1) * GAP
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -MARGIN_BOTTOM - SLOT.y - 16.0
	offset_bottom = -MARGIN_BOTTOM
	for i in Hotbar.SIZE:
		slots.append({"id": "", "count": -1, "owned": false})


## Updates what the bar shows; redraws only on a change.
func show_slots(new_slots: Array, sel: int, holster: bool, light := false) -> void:
	var key := "%d|%s|%s|%s" % [sel, holster, light, str(new_slots)]
	if key == _key:
		return
	_key = key
	slots = new_slots
	selected = sel
	holstered = holster
	light_on = light
	queue_redraw()


## Test access: the short label of slot `i` ("" when empty).
func label_of(i: int) -> String:
	if i < 0 or i >= slots.size():
		return ""
	return short_name(str(slots[i].get("id", "")))


static func short_name(id: String) -> String:
	return str(SHORT.get(id, Items.name_of(id))) if id != "" else ""


func _draw() -> void:
	var font := get_theme_default_font()
	var top := 16.0
	for i in slots.size():
		var e: Dictionary = slots[i]
		var id := str(e.get("id", ""))
		var owned := bool(e.get("owned", false))
		var r := Rect2(Vector2(i * (SLOT.x + GAP), top), SLOT)
		var sel := i == selected
		var bg := Color(0.06, 0.065, 0.075, 0.78 if sel else 0.6)
		draw_rect(r, bg, true)
		var frame := UiTheme.ACCENT if sel and not holstered else Color(1, 1, 1, 0.12 if not sel else 0.3)
		draw_rect(r, frame, false, 2.0 if sel else 1.0)
		var dim := 1.0 if owned else 0.38
		draw_string(font, r.position + Vector2(5, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.TEXT_DIM, 0.9))
		if id == "":
			continue
		var cat := Items.category(id)
		var glyph := str(GLYPH.get(cat, ""))
		var col := Color(UiTheme.TEXT, dim)
		if id == "flashlight" and light_on:
			col = Color(1.0, 0.9, 0.55, dim)
		if glyph != "":
			UiIcons.paint(self, glyph, Rect2(r.position + Vector2(SLOT.x * 0.5 - 10, 10), Vector2(20, 20)), Color(col, col.a * 0.85))
		else:
			_tool_glyph(id, Rect2(r.position + Vector2(SLOT.x * 0.5 - 11, 9), Vector2(22, 22)), col)
		draw_string(font, Vector2(r.position.x, r.end.y - 7), short_name(id), HORIZONTAL_ALIGNMENT_CENTER, SLOT.x, 12, col)
		var n := int(e.get("count", -1))
		if n >= 0:
			var nc := Color(UiTheme.TEXT, dim) if n > 0 else Color(UiTheme.WARN, 0.8)
			draw_string(font, Vector2(r.position.x, r.position.y + 13), str(n), HORIZONTAL_ALIGNMENT_RIGHT, SLOT.x - 5, 12, nc)
	if holstered:
		draw_string(font, Vector2(0, 11), "Hands empty  ·  X or 1-8 to take something", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(UiTheme.TEXT_DIM, 0.85))


## A tiny line glyph for tools and gear.
func _tool_glyph(id: String, r: Rect2, c: Color) -> void:
	var p := r.position
	var s := r.size.x
	var w := 2.0
	match id:
		"hammer":
			draw_line(p + Vector2(s * 0.3, s * 0.9), p + Vector2(s * 0.62, s * 0.25), c, w + 1.0, true)
			draw_rect(Rect2(p + Vector2(s * 0.42, s * 0.08), Vector2(s * 0.5, s * 0.22)), c, true)
		"crowbar":
			draw_line(p + Vector2(s * 0.25, s * 0.92), p + Vector2(s * 0.7, s * 0.15), c, w + 0.5, true)
			draw_line(p + Vector2(s * 0.7, s * 0.15), p + Vector2(s * 0.88, s * 0.25), c, w + 0.5, true)
		"shovel":
			draw_line(p + Vector2(s * 0.5, s * 0.05), p + Vector2(s * 0.5, s * 0.6), c, w, true)
			draw_rect(Rect2(p + Vector2(s * 0.32, s * 0.58), Vector2(s * 0.36, s * 0.36)), c, true)
		"flashlight":
			draw_rect(Rect2(p + Vector2(s * 0.1, s * 0.4), Vector2(s * 0.5, s * 0.22)), c, true)
			draw_colored_polygon(PackedVector2Array([p + Vector2(s * 0.6, s * 0.36), p + Vector2(s * 0.72, s * 0.28),
				p + Vector2(s * 0.72, s * 0.74), p + Vector2(s * 0.6, s * 0.66)]), c)
		_:
			draw_rect(Rect2(p + Vector2(s * 0.25, s * 0.25), Vector2(s * 0.5, s * 0.5)), c, false, w)
