extends Control
## Exp 007 (O): the overview's blueprint mode: a clean top-down plan of one
## storey drawn from an OverviewPlan (walls coloured by integrity, windows,
## knocked-out sections, doors with their swing, barricades, window boards,
## stairs with UP / DOWN, floor holes and damaged floor, dug cells, pillars,
## foundations, observation holes, collapsed and strained roof zones), turned
## with the camera (Z / C) so it matches the 3D view.

const PAPER := Color(0.06, 0.15, 0.26, 0.97)
const GRID := Color(0.75, 0.88, 1.0, 0.07)
const INK := Color(0.88, 0.94, 1.0)
const INK_DIM := Color(0.7, 0.82, 0.95, 0.55)
const FLOOR := Color(0.55, 0.75, 0.95, 0.13)
const DUG := Color(0.75, 0.62, 0.45, 0.28)
const GLASS := Color(0.55, 0.9, 1.0)
const WOOD := Color(0.95, 0.76, 0.46)
const IRON := Color(0.72, 0.8, 0.9)
const STONE := Color(0.8, 0.8, 0.76)
const WARN := Color(0.98, 0.74, 0.32)
const BAD := Color(0.96, 0.36, 0.3)
const HOLE := Color(1.0, 0.82, 0.3)
const MARGIN_M := 2.6                  ## metres of yard around the footprint

var plan := {}
var yaw := 0.0                         ## the camera's yaw (rad): the plan turns with it
var top_px := 150.0                    ## the overview card's height (kept free)

var _scale := 40.0
var _origin := Vector2.ZERO
var _centre := HousePlan.FOOTPRINT.get_center()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_plan(p: Dictionary, y: float) -> void:
	plan = p
	yaw = y
	queue_redraw()


func set_yaw(y: float) -> void:
	if absf(y - yaw) > 0.0001:
		yaw = y
		queue_redraw()


## Plan point -> screen point.
func to_screen(p: Vector2) -> Vector2:
	var r := p - _centre
	var c := cos(yaw)
	var s := sin(yaw)
	return _origin + Vector2(r.x * c - r.y * s, r.x * s + r.y * c) * _scale


func _fit() -> void:
	var ext := HousePlan.FOOTPRINT.size + Vector2.ONE * MARGIN_M * 2.0
	if absf(sin(yaw)) > 0.7:
		ext = Vector2(ext.y, ext.x)
	var area := Rect2(Vector2(30, top_px + 10), size - Vector2(60, top_px + 70))
	_scale = minf(area.size.x / ext.x, area.size.y / ext.y)
	_origin = area.get_center()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if plan.is_empty():
		return
	_fit()
	var font := UiTheme.font("regular")
	var fs := UiTheme.px(14)
	# 1 m grid over the house and some yard
	var g := HousePlan.FOOTPRINT.grow(MARGIN_M)
	for x in range(int(g.position.x), int(g.end.x) + 1):
		draw_line(to_screen(Vector2(x, g.position.y)), to_screen(Vector2(x, g.end.y)), GRID, 1.0)
	for y in range(int(g.position.y), int(g.end.y) + 1):
		draw_line(to_screen(Vector2(g.position.x, y)), to_screen(Vector2(g.end.x, y)), GRID, 1.0)
	if not plan.get("exists", false):
		_text(font, to_screen(_centre), "%s is not built yet" % str(plan.get("label", "")), fs + 4, INK_DIM, true)
		return
	for f in plan["foundations"]:
		_fill_rect(f["rect"], Color(WOOD, 0.22) if f["timber"] else Color(STONE, 0.22))
	for c in plan["floor"]:
		_fill_rect(Levels.cell_rect(c), FLOOR)
	for c in plan["dug"]:
		_fill_rect(Levels.cell_rect(c), DUG)
	for c in plan["floor_damaged"]:
		var r := Levels.cell_rect(c)
		for k in 3:
			draw_circle(to_screen(r.position + Vector2(0.25 + 0.25 * k, 0.3 + 0.2 * (k % 2))), maxf(2.0, _scale * 0.05), Color(WARN, 0.7))
	for c in plan["no_floor"]:
		var r := Levels.cell_rect(c).grow(-0.15)
		draw_line(to_screen(r.position), to_screen(r.end), Color(BAD, 0.75), 2.0)
		draw_line(to_screen(Vector2(r.end.x, r.position.y)), to_screen(Vector2(r.position.x, r.end.y)), Color(BAD, 0.75), 2.0)
	# roof zones
	for z in plan["collapsed"]:
		_hatch(z["rect"], Color(BAD, 0.45))
		_outline(z["rect"], BAD, 2.0)
		_text(font, to_screen((z["rect"] as Rect2).get_center()), "ROOF DOWN", fs, BAD, true)
	for z in plan["strained"]:
		_outline((z["rect"] as Rect2).grow(-0.08), Color(WARN, 0.85), 2.0, true)
		_text(font, to_screen((z["rect"] as Rect2).get_center()) + Vector2(0, fs + 2), "strained", fs - 2, WARN, true)
	# stairs
	for s in plan["stairs"]:
		_draw_stairs(s, font, fs)
	# walls
	var wall_w := maxf(3.0, _scale * 0.17)
	for w in plan["walls"]:
		var a := to_screen(w["a"])
		var b := to_screen(w["b"])
		match str(w["kind"]):
			"wall":
				var col := _integrity_color(float(w["integrity"]))
				var width := wall_w * (1.5 if w["material"] == "stone" else 1.0)
				draw_line(a, b, col, width)
				if w["plated"]:
					draw_line(a, b, IRON, maxf(1.5, width * 0.3))
				if w["material"] == "stone":
					draw_line(a, b, Color(PAPER, 0.6), maxf(1.0, width * 0.15))
			"window":
				var n := (b - a).orthogonal().normalized() * wall_w * 0.32
				draw_line(a + n, b + n, GLASS, 1.5)
				draw_line(a - n, b - n, GLASS, 1.5)
				draw_line(a, b, Color(GLASS, 0.35), 1.0)
			"missing":
				_dashed(a, b, Color(BAD, 0.85), maxf(2.0, wall_w * 0.45))
	# doors, barricades, boards
	for o in plan["objects"]:
		_draw_object(o, wall_w)
	# pillars
	for c in plan["pillars"]:
		var cc := Levels.cell_center(c)
		_fill_rect(Rect2(cc - Vector2(0.2, 0.2), Vector2(0.4, 0.4)), STONE)
	# observation holes
	for p in plan["holes"]:
		var sp := to_screen(p)
		draw_circle(sp, maxf(4.0, _scale * 0.13), Color(HOLE, 0.25))
		draw_arc(sp, maxf(4.0, _scale * 0.13), 0.0, TAU, 20, HOLE, 2.0)
		draw_circle(sp, 2.0, HOLE)
	# north arrow and legend
	var na := Vector2(size.x - 60, top_px + 50)
	var nd := (to_screen(_centre + Vector2(0, -1)) - to_screen(_centre)).normalized()
	draw_line(na - nd * 18, na + nd * 18, INK, 2.0)
	draw_line(na + nd * 18, na + nd * 10 + nd.orthogonal() * 6, INK, 2.0)
	draw_line(na + nd * 18, na + nd * 10 - nd.orthogonal() * 6, INK, 2.0)
	_text(font, na + nd * 32, "N", fs, INK, true)
	_legend(font, fs)


func _integrity_color(f: float) -> Color:
	if f >= 0.92:
		return INK
	if f >= 0.6:
		return WARN.lerp(INK, (f - 0.6) / 0.32)
	if f >= 0.35:
		return BAD.lerp(WARN, (f - 0.35) / 0.25)
	return BAD


func _draw_object(o: Dictionary, wall_w: float) -> void:
	var a: Vector2 = o["a"]
	var b: Vector2 = o["b"]
	var front := WorldObject.front_dir(int(o["rot"]))
	var col := (WOOD if o["mat"] == "wood" else IRON).lerp(BAD, clampf(float(o["damage"]) * 1.2, 0.0, 1.0))
	match str(o["kind"]):
		"door":
			var inward := -front
			var leaf_end := a + (inward if o["open"] else (b - a).normalized())
			draw_line(to_screen(a), to_screen(leaf_end), col, maxf(2.0, wall_w * 0.5))
			var pts := PackedVector2Array()
			var d0 := (b - a).normalized()
			for k in 13:
				var t := float(k) / 12.0
				pts.append(to_screen(a + (d0 * cos(t * PI * 0.5) + inward * sin(t * PI * 0.5)) * 1.0))
			draw_polyline(pts, Color(col, 0.55), 1.0)
		"barricade":
			var pts := PackedVector2Array()
			var d := b - a
			for k in 9:
				var t := float(k) / 8.0
				pts.append(to_screen(a + d * t + front * (0.12 if k % 2 == 0 else -0.12)))
			draw_polyline(pts, col, maxf(2.0, wall_w * 0.35))
		"boards":
			var off := front * 0.2
			draw_line(to_screen(a + off), to_screen(b + off), col, maxf(2.0, wall_w * 0.4))
			for k in 4:
				var p := a + (b - a) * (0.15 + 0.23 * k) + off
				draw_line(to_screen(p - front * 0.1), to_screen(p + front * 0.1), col, 1.5)


func _draw_stairs(s: Dictionary, font: Font, fs: int) -> void:
	var r: Rect2 = s["rect"]
	_fill_rect(r, Color(INK, 0.08))
	_outline(r, INK_DIM, 1.5)
	var from: Vector2 = s["from"]
	var to: Vector2 = s["to"]
	var d := (to - from).normalized()
	var across := Vector2(-d.y, d.x) * (minf(r.size.x, r.size.y) * 0.5)
	var start := r.get_center() - d * (maxf(r.size.x, r.size.y) * 0.5)
	for k in range(1, Levels.STEPS):
		var p := start + d * (2.0 * float(k) / float(Levels.STEPS))
		draw_line(to_screen(p - across), to_screen(p + across), Color(INK, 0.35), 1.0)
	var a := to_screen(r.get_center() - d * 0.7)
	var b := to_screen(r.get_center() + d * 0.7)
	draw_line(a, b, INK, 2.0)
	var bd := (b - a).normalized()
	draw_line(b, b - bd * 8 + bd.orthogonal() * 5, INK, 2.0)
	draw_line(b, b - bd * 8 - bd.orthogonal() * 5, INK, 2.0)
	_text(font, to_screen(r.get_center()) + bd.orthogonal() * 14, ("UP " if s["up"] else "DOWN ") + Levels.number(int(s["to_storey"])), fs - 2, INK, true)


func _legend(font: Font, fs: int) -> void:
	var items := [[INK, "wall"], [WARN, "damaged"], [BAD, "broken / knocked out"], [GLASS, "window"],
		[WOOD, "door, barricade, boards"], [HOLE, "observation hole"], [Color(BAD, 0.6), "no floor / roof down"]]
	var x := 30.0
	var y := size.y - 26.0
	for it in items:
		draw_rect(Rect2(Vector2(x, y - 9), Vector2(14, 6)), it[0])
		draw_string(font, Vector2(x + 20, y), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, INK_DIM)
		x += 30.0 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x
		if x > size.x - 200:
			x = 30.0
			y -= 20.0


func _poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([to_screen(r.position), to_screen(Vector2(r.end.x, r.position.y)), to_screen(r.end), to_screen(Vector2(r.position.x, r.end.y))])


func _fill_rect(r: Rect2, col: Color) -> void:
	draw_colored_polygon(_poly(r), col)


func _outline(r: Rect2, col: Color, width: float, dashed := false) -> void:
	var p := _poly(r)
	for k in 4:
		if dashed:
			_dashed(p[k], p[(k + 1) % 4], col, width)
		else:
			draw_line(p[k], p[(k + 1) % 4], col, width)


func _dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / 8.0))
	for k in n:
		if k % 2 == 0:
			draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, width)


func _hatch(r: Rect2, col: Color) -> void:
	var step := 0.35
	var k := -r.size.y
	while k < r.size.x:
		var p0 := Vector2(r.position.x + k, r.position.y)
		var p1 := Vector2(r.position.x + k + r.size.y, r.end.y)
		# clip the diagonal to the rect
		if p0.x < r.position.x:
			p0 = Vector2(r.position.x, r.position.y + (r.position.x - p0.x))
		if p1.x > r.end.x:
			p1 = Vector2(r.end.x, r.end.y - (p1.x - r.end.x))
		if p0.x <= p1.x:
			draw_line(to_screen(p0), to_screen(p1), col, 1.5)
		k += step


func _text(font: Font, at: Vector2, text: String, fs: int, col: Color, centred := false) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w * 0.5, -fs * 0.35) if centred else at
	draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
