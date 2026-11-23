extends Node2D
## The house walls of Version C, built from HousePlan.WALLS / OPENINGS:
## destructible sections (about 1 m, windows as 1 m panes), indestructible
## timber posts where walls meet, and door frames with open leaves.
## Keeps GridNav in sync when a section is removed (same frame as collision).

signal section_destroyed(section)

const Art := preload("res://src/illustrated/ill_art.gd")
const WallSection := preload("res://src/illustrated/wall_section.gd")

## Door leaves: which end is hinged and to which side of the wall line they swing.
const DOOR_SWING := {
	"front_door": {"hinge": "from", "side": -1.0},
	"back_door": {"hinge": "from", "side": -1.0},
	"bedroom_door": {"hinge": "to", "side": -1.0},
	"bathroom_door": {"hinge": "to", "side": -1.0},
	"utility_door": {"hinge": "to", "side": 1.0},
}

var nav: GridNav
var sections: Array = []
var posts: Array[Rect2] = []          ## plan rects
var _shadow_parent: Node
var _shadow_offset := Vector2.ZERO
var _shadow_grow := 0.0


func build(p_nav: GridNav, shadow_parent: Node) -> void:
	nav = p_nav
	_shadow_parent = shadow_parent
	_shadow_offset = Vector2(Art.m(0.17), Art.m(0.24))
	_shadow_grow = Art.m(0.07)
	_build_posts()
	# posts never break: SOLID keeps pursuers from bashing them (walkability is unchanged)
	for r in posts:
		nav.mark_rect(r, GridNav.SOLID)
		nav.refresh_region(r)
	_build_sections()
	_link()
	_build_doors()


# --- construction -------------------------------------------------------------------

static func _on_wall(w: Dictionary, p: Vector2) -> bool:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	if HousePlan.is_horizontal(w):
		return absf(p.y - a.y) < 1e-3 and p.x >= minf(a.x, b.x) - 1e-3 and p.x <= maxf(a.x, b.x) + 1e-3
	return absf(p.x - a.x) < 1e-3 and p.y >= minf(a.y, b.y) - 1e-3 and p.y <= maxf(a.y, b.y) + 1e-3


func _build_posts() -> void:
	var pts: Array[Vector2] = []
	for w in HousePlan.WALLS:
		for e in [w["a"], w["b"]]:
			var known := false
			for q in pts:
				if q.distance_to(e) < 1e-3:
					known = true
			if not known:
				pts.append(e)
	for p in pts:
		var wx := 0.0
		var wy := 0.0
		for w in HousePlan.WALLS:
			if _on_wall(w, p):
				if HousePlan.is_horizontal(w):
					wy = maxf(wy, HousePlan.thickness(w))
				else:
					wx = maxf(wx, HousePlan.thickness(w))
		if wx == 0.0:
			wx = wy
		if wy == 0.0:
			wy = wx
		var r := Rect2(p - Vector2(wx, wy) * 0.5, Vector2(wx, wy))
		posts.append(r)
		_make_post(r)


func _make_post(r: Rect2) -> void:
	var wr := Art.rect(r)
	var body := StaticBody2D.new()
	body.name = "Post"
	body.position = wr.get_center()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("material", "wood")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = wr.size
	cs.shape = rs
	body.add_child(cs)
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	poly.polygon = Art.rect_points(Rect2(-wr.size * 0.5, wr.size))
	occ.occluder = poly
	body.add_child(occ)
	var tex := Art.tex("wall_post")
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		# the template's 40 px core is the post; 8 px margins around it
		s.scale = wr.size * (56.0 / 40.0) / tex.get_size()
		body.add_child(s)
	add_child(body)
	var sh := Node2D.new()
	_shadow_parent.add_child(sh)
	for poly_r in [wr.grow(_shadow_grow), Rect2(wr.position + _shadow_offset, wr.size)]:
		var p := Polygon2D.new()
		p.polygon = Art.rect_points(poly_r)
		p.color = Color.BLACK
		sh.add_child(p)


func _post_intervals(w: Dictionary) -> Array:
	var out := []
	var horiz := HousePlan.is_horizontal(w)
	for r in posts:
		var c := r.get_center()
		if not _on_wall(w, c):
			continue
		if horiz:
			out.append(Vector2(r.position.x, r.end.x))
		else:
			out.append(Vector2(r.position.y, r.end.y))
	return out


func _build_sections() -> void:
	for w in HousePlan.WALLS:
		var cuts := _post_intervals(w)
		for span in HousePlan.wall_spans(w):
			if span["kind"] == "door":
				continue
			var ranges := [Vector2(span["from"], span["to"])]
			for c in cuts:
				var next := []
				for rg in ranges:
					if c.y <= rg.x or c.x >= rg.y:
						next.append(rg)
						continue
					if c.x > rg.x:
						next.append(Vector2(rg.x, c.x))
					if c.y < rg.y:
						next.append(Vector2(c.y, rg.y))
				ranges = next
			for rg in ranges:
				var ln: float = rg.y - rg.x
				if ln < 0.05:
					continue
				var n := maxi(1, int(round(ln)))
				for k in n:
					var s: WallSection = WallSection.new()
					s.setup(w, rg.x + ln * k / n, rg.x + ln * (k + 1) / n, span["kind"])
					s.make_shadow(_shadow_parent, _shadow_offset, _shadow_grow)
					s.destroyed.connect(_on_section_destroyed)
					add_child(s)
					sections.append(s)


func _link() -> void:
	for s in sections:
		for o in sections:
			if s == o or s.wall["id"] != o.wall["id"]:
				continue
			if absf(s.to_m - o.from_m) < 1e-3 or absf(s.from_m - o.to_m) < 1e-3:
				var e := _end_toward(s, o.center())
				s.neighbours[e] = o
		for d in HousePlan.openings_on(s.wall["id"]):
			if d["kind"] != "door":
				continue
			for edge in [d["from"], d["to"]]:
				if absf(s.from_m - edge) < 1e-3 or absf(s.to_m - edge) < 1e-3:
					var along := s.wall["a"] as Vector2
					var p := Vector2(edge, along.y) if HousePlan.is_horizontal(s.wall) else Vector2(along.x, edge)
					s.end_door[_end_toward(s, Art.w(p))] = true


func _end_toward(s, p: Vector2) -> int:
	return 0 if s.end_point(0).distance_to(p) < s.end_point(1).distance_to(p) else 1


func _build_doors() -> void:
	for o in HousePlan.OPENINGS:
		if o["kind"] != "door":
			continue
		var w := HousePlan.wall_by_id(o["wall"])
		var frame := DoorFrame.new()
		frame.opening = o
		frame.wall = w
		frame.z_index = 1
		add_child(frame)
		var spec: Dictionary = DOOR_SWING.get(o["id"], {"hinge": "from", "side": 1.0})
		var horiz := HousePlan.is_horizontal(w)
		var t := HousePlan.thickness(w)
		var at: float = o[spec["hinge"]]
		var side: float = spec["side"]
		var hinge: Vector2
		var dir: Vector2
		var away: float = -1.0 if spec["hinge"] == "from" else 1.0   # away from the opening, along the wall
		if horiz:
			hinge = Vector2(at, w["a"].y + side * t * 0.5)
			dir = Vector2(away * sin(deg_to_rad(5.0)), side * cos(deg_to_rad(5.0)))
		else:
			hinge = Vector2(w["a"].x + side * t * 0.5, at)
			dir = Vector2(side * cos(deg_to_rad(5.0)), away * sin(deg_to_rad(5.0)))
		var tex := Art.tex("door_leaf")
		if tex == null:
			continue
		var leaf := Sprite2D.new()
		leaf.texture = tex
		var k := (0.9 + 2.0 * Art.ART_MARGIN_M) * Art.PX_PER_M / tex.get_size().x
		leaf.scale = Vector2(k, k)
		leaf.position = Art.w(hinge + dir * 0.45)
		leaf.rotation = dir.angle()
		leaf.z_index = 2
		if w["exterior"]:
			leaf.modulate = Color(0.42, 0.44, 0.47)   # charcoal exterior doors
		add_child(leaf)


# --- damage -----------------------------------------------------------------------

## Enemy swings: damage the nearest standing section around a plan point.
func bash_at(plan_point: Vector2, dmg: int, dir: Vector2) -> String:
	var wp := Art.w(plan_point)
	var best = null
	var best_d := INF
	for s in sections:
		if s.removed:
			continue
		var r: Rect2 = s.world_rect().grow(Art.m(0.3))
		if not r.has_point(wp):
			continue
		var d: float = s.center().distance_to(wp)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return "none"
	var rr: Rect2 = best.world_rect()
	var p := Vector2(clampf(wp.x, rr.position.x, rr.end.x), clampf(wp.y, rr.position.y, rr.end.y))
	return best.hit(p, dmg, dir, true)


func _on_section_destroyed(s) -> void:
	var r := HousePlan.span_rect(s.wall, s.from_m, s.to_m)
	for c in nav.cells_in_rect(r):
		if nav.get_raw(c) != GridNav.SOLID:
			nav.set_raw(c, GridNav.OPEN)
	nav.refresh_region(r)
	section_destroyed.emit(s)


func intact_count() -> int:
	var n := 0
	for s in sections:
		if not s.removed:
			n += 1
	return n


## Pre-damage for showcase scenarios: hits spread along the section.
func damage_section(s, hits: int) -> void:
	for i in hits:
		if s.removed:
			return
		var u := (float(i % 5) / 4.0 - 0.5) * 0.7
		var lp := Vector2(u * s._len, 0.0)
		var dir := Vector2.DOWN.rotated(s.rotation) * (1.0 if i % 2 == 0 else -1.0)
		s.hit(s.to_global(lp), 1, dir.rotated(-0.0))


## Frames (jambs + threshold) of an open doorway.
class DoorFrame extends Node2D:
	const ArtC := preload("res://src/illustrated/ill_art.gd")
	var opening: Dictionary
	var wall: Dictionary

	func _draw() -> void:
		var r := ArtC.rect(HousePlan.span_rect(wall, opening["from"], opening["to"]))
		var horiz := HousePlan.is_horizontal(wall)
		var ext: bool = wall["exterior"]
		var sill := Color(0.6, 0.6, 0.58) if ext else Color(0.52, 0.4, 0.28)
		draw_rect(r, sill)
		var n := 5
		for k in n:
			var f := (k + 0.5) / n
			if horiz:
				var y := r.position.y + r.size.y * f
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.18), 0.6)
			else:
				var x := r.position.x + r.size.x * f
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.18), 0.6)
		var ink := ArtC.INK
		if horiz:
			draw_line(r.position, Vector2(r.end.x, r.position.y), ink, 1.2)
			draw_line(Vector2(r.position.x, r.end.y), r.end, ink, 1.2)
		else:
			draw_line(r.position, Vector2(r.position.x, r.end.y), ink, 1.2)
			draw_line(Vector2(r.end.x, r.position.y), r.end, ink, 1.2)
		# jamb casings at both ends (slightly proud of the wall faces)
		var jw := ArtC.m(0.05)
		var over := ArtC.m(0.03)
		for e in 2:
			var jr: Rect2
			if horiz:
				var x := r.position.x if e == 0 else r.end.x - jw
				jr = Rect2(Vector2(x, r.position.y - over), Vector2(jw, r.size.y + over * 2.0))
			else:
				var y := r.position.y if e == 0 else r.end.y - jw
				jr = Rect2(Vector2(r.position.x - over, y), Vector2(r.size.x + over * 2.0, jw))
			draw_rect(jr, Color(0.2, 0.21, 0.23) if ext else Color(0.86, 0.83, 0.77))
			draw_rect(jr, ink, false, 1.0)
