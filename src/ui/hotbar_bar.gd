class_name HotbarBar
extends Control
## The quick-access bar on the HUD (Experiment 004, E): eight slots at the
## bottom centre with the key (1-8), a pixel icon (Exp 006), a short name and the count
## (rounds in the magazine for weapons). The selected slot has an accent
## frame; an empty-handed bar (X, or an empty slot) shows "Hands empty".
## One Control drawn with CanvasItem primitives and redrawn only when what it
## shows changes (show_slots). The game helper (src/game/game_hotbar.gd) owns
## it, feeds it and hides it in build mode and while panels are open.

const SLOT := Vector2(68, 62)      # Exp 006 (U): room for the pixel font and 24 px icons
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
	# Exp 006 (U): Pixel Operator at 16 and 24 px pixel icons; square slots
	# with a hard shadow and the amber frame on the selected one.
	var font := UiTheme.font()
	var top := 16.0
	for i in slots.size():
		var e: Dictionary = slots[i]
		var id := str(e.get("id", ""))
		var owned := bool(e.get("owned", false))
		var r := Rect2(Vector2(i * (SLOT.x + GAP), top), SLOT)
		var sel := i == selected
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35), true)
		var bg := Color(UiTheme.BG_SOLID, 0.82 if sel else 0.62)
		draw_rect(r, bg, true)
		var frame := UiTheme.ACCENT if sel and not holstered else Color(UiTheme.LINE, 0.2 if not sel else 0.45)
		draw_rect(r.grow(-1.0 if sel else -0.5), frame, false, 2.0 if sel else 1.0)
		var dim := 1.0 if owned else 0.38
		draw_string(font, r.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UiTheme.TEXT_DIM, 0.9))
		if id == "":
			continue
		var col := Color(UiTheme.TEXT, dim)
		if id == "flashlight" and light_on:
			col = Color(1.0, 0.9, 0.55, dim)
		var icon := UiIcons.for_item(id)
		var ir := Rect2(r.position + Vector2(SLOT.x * 0.5 - 12, 16), Vector2(24, 24))
		UiIcons.paint(self, icon, Rect2(ir.position + Vector2(1, 1), ir.size), Color(0, 0, 0, 0.5 * dim))
		UiIcons.paint(self, icon, ir, col)
		draw_string(font, Vector2(r.position.x, r.end.y - 6), short_name(id), HORIZONTAL_ALIGNMENT_CENTER, SLOT.x, 16, col)
		var n := int(e.get("count", -1))
		if n >= 0:
			var nc := Color(UiTheme.TEXT, dim) if n > 0 else Color(UiTheme.WARN, 0.8)
			draw_string(font, Vector2(r.position.x, r.position.y + 15), str(n), HORIZONTAL_ALIGNMENT_RIGHT, SLOT.x - 5, 16, nc)
	if holstered:
		draw_string_outline(font, Vector2(0, 11), "Hands empty  ·  X or 1-8 to take something", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, 4, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, 11), "Hands empty  ·  X or 1-8 to take something", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(UiTheme.TEXT_DIM, 0.9))
