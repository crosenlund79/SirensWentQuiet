class_name MapMarkers
extends Control
## The 2D layer over the region map (SPEC-003 §6). Owner: M.
## Draws a pin per known place (category colour and glyph, a stem down to the
## ground, the name when close or hovered), the road route from the house to
## the selected place, and a hover card. Mouse: hover, click to select, drag
## to pan, wheel to zoom at the cursor. Undiscovered places are not in
## `entries` at all (hidden).

signal place_clicked(id: String)
signal hover_changed(id: String)

const HEAD_R := 10.0
const HOME_R := 12.5
const LIFT := 18.0              ## pixels between the building top and the pin
const HIT_R := 15.0
const LABEL_DISTANCE := 105.0   ## camera distance under which every name shows
const CLICK_SLOP := 6.0

var view: RegionMapView
## [{id, name, cat, ground: Vector3, top: Vector3, sub: String}]
var entries: Array = []
var selected := ""
var hovered := ""
var planned := ""
var route_world := PackedVector3Array()
var traveller_world := Vector3.INF      ## Exp 007 (T): the travelling Eli (or car): a pin over him and a ring at his feet
var traveller_label := ""

var _screen := {}               ## id -> [ground_px, head_px, depth]
var _drag := false
var _press := Vector2.ZERO
var _press_world := Vector3.INF
var _moved := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_project()
	queue_redraw()


func _project() -> void:
	_screen.clear()
	if view == null or view.camera == null:
		return
	var cam := view.camera.global_position
	for e in entries:
		var top: Vector3 = e["top"]
		if not view.is_visible_point(top):
			continue
		var g := view.project(e["ground"])
		var h := view.project(top) - Vector2(0.0, LIFT)
		_screen[e["id"]] = [g, h, cam.distance_to(top)]


## The place under a position (closest pin head within reach), or "".
func hit(pos: Vector2) -> String:
	var best := ""
	var bd := HIT_R * HIT_R
	for id in _screen:
		var d := (_screen[id][1] as Vector2).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = id
	return best


func head_position(id: String) -> Vector2:
	return _screen[id][1] if _screen.has(id) else Vector2.INF


func _gui_input(event: InputEvent) -> void:
	if view == null or view.camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
				_press = mb.position
				_press_world = view.ray_plane(mb.position, RegionMapView.GROUND_Y)
			else:
				if _drag and _moved < CLICK_SLOP:
					place_clicked.emit(hit(mb.position))
				_drag = false
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var at := view.ray_plane(mb.position, RegionMapView.GROUND_Y)
			view.zoom_by(0.87 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.87, at)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			_moved = maxf(_moved, mm.position.distance_to(_press))
			if _moved >= CLICK_SLOP and _press_world != Vector3.INF:
				var now := view.ray_plane(mm.position, RegionMapView.GROUND_Y)
				if now != Vector3.INF:
					view.drag_pan(_press_world - now)
		var h := "" if (_drag and _moved >= CLICK_SLOP) else hit(mm.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			hover_changed.emit(h)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
		hovered = ""
		hover_changed.emit("")


# --- drawing ------------------------------------------------------------------

func _entry(id: String) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func _draw() -> void:
	if view == null or view.camera == null:
		return
	_draw_route()
	var order := _screen.keys()
	order.sort_custom(func(a, b): return _screen[a][2] > _screen[b][2])
	# keep the important ones on top
	for id in [planned, selected, hovered, MapInfo.HOME]:
		if id != "" and order.has(id):
			order.erase(id)
			order.append(id)
	var close := view.distance < LABEL_DISTANCE
	for id in order:
		var e := _entry(id)
		if e.is_empty():
			continue
		var g: Vector2 = _screen[id][0]
		var h: Vector2 = _screen[id][1]
		var is_home: bool = id == MapInfo.HOME
		var r := HOME_R if is_home else HEAD_R
		var col := MapInfo.category_color(e["cat"])
		var hot: bool = id == hovered or id == selected
		if hot:
			r += 1.5
		draw_line(g, h + Vector2(0, r - 1.0), Color(0, 0, 0, 0.35), 3.0, true)
		draw_line(g, h + Vector2(0, r - 1.0), Color(1, 1, 1, 0.7), 1.2, true)
		draw_circle(g, 2.2, Color(1, 1, 1, 0.8))
		if id == selected:
			draw_arc(h, r + 5.0, 0.0, TAU, 40, UiTheme.ACCENT, 2.2, true)
		if id == planned:
			_draw_dashed_ring(h, r + (9.0 if id == selected else 5.0), UiTheme.ACCENT)
		draw_circle(h, r + 1.6, Color(0.05, 0.05, 0.06, 0.85))
		draw_circle(h, r, col)
		_glyph(e["cat"], h, r)
		if close or hot or is_home or id == planned:
			_label(e["name"], h + Vector2(r + 6.0, 5.0), 14 if hot or is_home else 13, UiTheme.TEXT if hot or is_home else Color(0.95, 0.93, 0.9, 0.92))
			if id == planned:
				_label("PLANNED", h + Vector2(r + 6.0, 19.0), 11, UiTheme.ACCENT)
	if hovered != "" and hovered != selected and _screen.has(hovered):
		_draw_card(_entry(hovered), _screen[hovered][1])
	_draw_traveller()


## Exp 007 (T): a pin over the travelling figure (MapTraveller), so it reads
## at any zoom, over the route line.
func _draw_traveller() -> void:
	if traveller_world == Vector3.INF or not view.is_visible_point(traveller_world):
		return
	var g := view.project(traveller_world)
	var top := view.project(traveller_world + Vector3(0, 2.9, 0))
	var h := top - Vector2(0, 16.0)
	draw_arc(g, 9.0, 0.0, TAU, 28, Color(0, 0, 0, 0.5), 4.0, true)
	draw_arc(g, 9.0, 0.0, TAU, 28, UiTheme.ACCENT, 2.0, true)
	draw_line(top, h + Vector2(0, 7.0), Color(0, 0, 0, 0.35), 3.0, true)
	draw_line(top, h + Vector2(0, 7.0), Color(1, 1, 1, 0.8), 1.2, true)
	draw_circle(h, 8.6, Color(0.05, 0.05, 0.06, 0.9))
	draw_circle(h, 7.0, UiTheme.ACCENT)
	draw_circle(h, 2.4, Color(0.05, 0.05, 0.06, 0.9))
	if traveller_label != "":
		_label(traveller_label, h + Vector2(13.0, 5.0), 14, UiTheme.TEXT)


func _draw_route() -> void:
	if route_world.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in route_world:
		if not view.is_visible_point(p):
			return
		pts.append(view.project(p))
	draw_polyline(pts, Color(0, 0, 0, 0.45), 5.0, true)
	# dashes along the polyline
	var dash := 9.0
	var gap := 6.0
	var acc := 0.0
	var on := true
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var len := a.distance_to(b)
		var t := 0.0
		while t < len:
			var seg := minf((dash if on else gap) - acc, len - t)
			if on:
				draw_line(a.lerp(b, t / len), a.lerp(b, (t + seg) / len), UiTheme.ACCENT, 2.4, true)
			t += seg
			acc += seg
			if acc >= (dash if on else gap) - 0.001:
				acc = 0.0
				on = not on


func _draw_dashed_ring(c: Vector2, r: float, col: Color) -> void:
	for k in 12:
		var a := TAU * k / 12.0
		draw_arc(c, r, a, a + TAU / 24.0, 4, col, 2.0, true)


func _label(text: String, pos: Vector2, size: int, col: Color) -> void:
	var f := UiTheme.font()                  # Exp 006 (U): the pixel font at a crisp size
	size = UiTheme.px(size)
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.02, 0.02, 0.03, 0.85))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_card(e: Dictionary, at: Vector2) -> void:
	if e.is_empty():
		return
	var f := UiTheme.font()                  # Exp 006 (U)
	var name: String = e["name"]
	var sub: String = e.get("sub", "")
	var w := maxf(UiTheme.font("bold").get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 24.0
	var rect := Rect2(at + Vector2(-w * 0.5, -HEAD_R - 58.0), Vector2(w, 44.0))
	rect.position.x = clampf(rect.position.x, 8.0, size.x - w - 8.0)
	rect.position.y = maxf(rect.position.y, 8.0)
	var sb := UiTheme.card_style()
	sb.bg_color = Color(0.03, 0.032, 0.04, 0.88)
	draw_style_box(sb, rect)
	draw_string(UiTheme.font("bold"), rect.position + Vector2(12, 19), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.TEXT)
	draw_string(f, rect.position + Vector2(12, 36), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.TEXT_DIM)


## Small dark category glyphs inside the pin.
func _glyph(cat: String, c: Vector2, r: float) -> void:
	var k := Color(0.08, 0.08, 0.1, 0.92)
	var s := r * 0.55
	match cat:
		MapInfo.HOME, "residential":
			var pts := PackedVector2Array([c + Vector2(-s, s * 0.8), c + Vector2(-s, -s * 0.1), c + Vector2(0, -s), c + Vector2(s, -s * 0.1), c + Vector2(s, s * 0.8)])
			draw_colored_polygon(pts, k)
		"medical":
			draw_rect(Rect2(c - Vector2(s * 0.3, s), Vector2(s * 0.6, s * 2.0)), k)
			draw_rect(Rect2(c - Vector2(s, s * 0.3), Vector2(s * 2.0, s * 0.6)), k)
		"weapons":
			draw_arc(c, s * 0.8, 0.0, TAU, 20, k, 1.8, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * s * 0.3, c + d * s * 1.15, k, 1.8)
		"food":
			draw_rect(Rect2(c + Vector2(-s * 0.65, -s * 0.85), Vector2(s * 1.3, s * 1.7)), k)
			draw_rect(Rect2(c + Vector2(-s * 0.65, -s * 0.3), Vector2(s * 1.3, s * 0.35)), MapInfo.category_color("food"))
		"construction":
			draw_rect(Rect2(c + Vector2(-s, -s * 0.85), Vector2(s * 2.0, s * 0.7)), k)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.2), Vector2(s * 0.45, s * 1.25)), k)
		"knowledge":      # Exp 006 (R): an open book
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.6), c + Vector2(-s * 0.08, -s * 0.35), c + Vector2(-s * 0.08, s * 0.85), c + Vector2(-s, s * 0.6)]), k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s * 0.6), c + Vector2(s * 0.08, -s * 0.35), c + Vector2(s * 0.08, s * 0.85), c + Vector2(s, s * 0.6)]), k)
