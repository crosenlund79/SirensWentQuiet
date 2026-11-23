extends StaticBody2D
## One destructible stretch of wall (about 1 m) or one window pane.
##
## Local space: +x runs along the wall, -y is the wall's outside face (the
## cladding side of exterior walls). The node is rotated into place, so the
## tileable wall strips are drawn horizontally and turn with the wall.
## Damage is tracked per 0.125 m chunk (intact -> cracked -> broken) and as
## individual bullet holes; collision, occluder and navigation only change
## when the whole section is removed (handled through `destroyed`).

signal destroyed(section)

const Art := preload("res://src/illustrated/ill_art.gd")
const CHUNK_M := 0.125
const STRIP_M := 4.0            ## wall strips tile every 4 m
const MAX_HOLES := 18
## Transparent margin of each strip as a fraction of its height (template layout).
const MARGIN_FRAC := {"wall_ext": 8.0 / 56.0, "wall_int": 8.0 / 42.0, "window": 8.0 / 56.0}

var wall: Dictionary
var from_m := 0.0
var to_m := 0.0
var kind := "solid"             ## "solid" | "window"
var exterior := false
var max_hp := 10
var hp := 10
var glass := 0                  ## windows: 0 intact, 1 cracked, 2 shattered
var removed := false
var neighbours: Array = [null, null]   ## sections touching the local -x / +x end
var end_door := [false, false]         ## a doorway at that end
var shadow: Node2D                     ## silhouette in the shared shadow group

var _len := 0.0
var _t := 0.0
var _ex := Vector2.RIGHT        ## world direction of local +x
var _shade_side := 1.0          ## local y sign that faces world down/right
var _chunks := PackedFloat32Array()
var _holes: Array = []          ## [Vector3(u, v, r)] in local px
var _shape: CollisionShape2D
var _occluders: Array[LightOccluder2D] = []
var _leak := false
var _rng := RandomNumberGenerator.new()
var _prefix := "wall_int"


func setup(p_wall: Dictionary, p_from: float, p_to: float, p_kind: String) -> void:
	wall = p_wall
	from_m = p_from
	to_m = p_to
	kind = p_kind
	exterior = wall["exterior"]
	name = "%s_%s_%.2f" % [wall["id"], kind, from_m]
	_rng.seed = hash(name)
	var r := Art.rect(HousePlan.span_rect(wall, from_m, to_m))
	position = r.get_center()
	var horiz := HousePlan.is_horizontal(wall)
	var c := HousePlan.FOOTPRINT.get_center()
	if horiz:
		_len = r.size.x
		_t = r.size.y
		rotation = PI if (exterior and wall["a"].y > c.y) else 0.0
	else:
		_len = r.size.y
		_t = r.size.x
		rotation = -PI * 0.5 if (exterior and wall["a"].x < c.x) else PI * 0.5
	_ex = Vector2.RIGHT.rotated(rotation)
	var down := Vector2.DOWN.rotated(rotation)
	_shade_side = 1.0 if (down.x + down.y) > 0.0 else -1.0
	_prefix = "window" if kind == "window" else ("wall_ext" if exterior else "wall_int")
	max_hp = maxi(3, int(round(Tuning.WALL_SECTION_HP * (to_m - from_m))))
	hp = max_hp
	var n := maxi(1, int(ceil((to_m - from_m) / CHUNK_M - 0.01)))
	_chunks.resize(n)
	_chunks.fill(0.0)
	collision_layer = 2
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(_len, _t)
	_shape.shape = rs
	add_child(_shape)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if kind != "window":
		_set_occluders([Vector2(-_len * 0.5, _len * 0.5)])


## Silhouette polygons for the soft day shadow (world space, in the shadow group).
func make_shadow(parent: Node, offset: Vector2, grow: float) -> void:
	shadow = Node2D.new()
	parent.add_child(shadow)
	var rr := world_rect()
	for poly in [rr.grow(grow), Rect2(rr.position + offset, rr.size)]:
		var p := Polygon2D.new()
		p.polygon = Art.rect_points(poly)
		p.color = Color.BLACK
		shadow.add_child(p)


func is_intact() -> bool:
	return not removed and hp == max_hp and glass == 0


func stage() -> int:
	if removed:
		return 3
	var f := float(hp) / float(max_hp)
	if f <= 0.34:
		return 2
	if hp < max_hp or glass > 0:
		return 1
	return 0


## A hit at a world point. `dir` is the travel direction of the bullet (or
## the swing). Returns the impact material for effects.
func hit(world_point: Vector2, dmg: int, dir: Vector2, bash := false) -> String:
	if removed:
		return "none"
	var lp := to_local(world_point)
	var ld := dir.rotated(-rotation)
	var face := -1.0 if ld.y > 0.0 else 1.0     # local y sign of the face that was struck
	var u := clampf(lp.x, -_len * 0.5 + 1.0, _len * 0.5 - 1.0)
	var material := "plaster"
	if exterior and face < 0.0:
		material = "cladding"
	if kind == "window" and glass < 2:
		glass += 1
		queue_redraw()
		return "glass"
	if stage() >= 2:
		material = "wood"
	hp -= dmg
	var ci := clampi(int((u + _len * 0.5) / _len * _chunks.size()), 0, _chunks.size() - 1)
	_chunks[ci] += 1.0
	for k in [ci - 1, ci + 1]:
		if k >= 0 and k < _chunks.size():
			_chunks[k] += 0.45 if not bash else 0.7
	if not bash:
		var v := face * (_t * 0.5 - _rng.randf_range(1.5, 3.5))
		_holes.append(Vector3(u, v, _rng.randf_range(1.6, 2.4)))
		if _holes.size() > MAX_HOLES:
			_holes.pop_front()
	if hp <= 0:
		_destroy()
	else:
		_update_leak()
		queue_redraw()
	return material


func _destroy() -> void:
	removed = true
	hp = 0
	_shape.disabled = true
	collision_layer = 0
	_set_occluders([])
	if shadow != null:
		shadow.visible = false
	for nb in neighbours:
		if nb != null and is_instance_valid(nb):
			nb.on_neighbour_removed(self)
	queue_redraw()
	destroyed.emit(self)


func on_neighbour_removed(_other) -> void:
	queue_redraw()


## World-space centre of the section.
func center() -> Vector2:
	return global_position


func world_rect() -> Rect2:
	return Art.rect(HousePlan.span_rect(wall, from_m, to_m))


func end_point(i: int) -> Vector2:
	return to_global(Vector2((-0.5 if i == 0 else 0.5) * _len, 0.0))


# --- light leaks: a broken section lets a sliver of light through ---------------

func _update_leak() -> void:
	if _leak or kind == "window" or stage() < 2:
		return
	_leak = true
	var best := 0
	for i in _chunks.size():
		if _chunks[i] > _chunks[best]:
			best = i
	var cw := _len / _chunks.size()
	var g0 := -_len * 0.5 + best * cw
	var g1 := g0 + cw
	var parts: Array = []
	if g0 > -_len * 0.5 + 0.5:
		parts.append(Vector2(-_len * 0.5, g0))
	if g1 < _len * 0.5 - 0.5:
		parts.append(Vector2(g1, _len * 0.5))
	_set_occluders(parts)


func _set_occluders(spans: Array) -> void:
	for o in _occluders:
		o.queue_free()
	_occluders.clear()
	for s in spans:
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
		poly.polygon = Art.rect_points(Rect2(Vector2(s.x, -_t * 0.5), Vector2(s.y - s.x, _t)))
		occ.occluder = poly
		add_child(occ)
		_occluders.append(occ)


# --- drawing ----------------------------------------------------------------------

func _level(i: int) -> int:
	var c := _chunks[i]
	var lv := 0
	if c >= 0.4:
		lv = 1
	if c >= 2.4:
		lv = 2
	var f := float(hp) / float(max_hp)
	if f <= 0.6 and lv == 0 and (i % 3 != 1 or f <= 0.45):
		lv = 1
	if f <= 0.34 and c >= 0.9:
		lv = 2
	for e in 2:
		var nb = neighbours[e]
		var torn: bool = nb != null and is_instance_valid(nb) and nb.removed
		if torn and ((e == 0 and i == 0) or (e == 1 and i == _chunks.size() - 1)):
			lv = 2
	return lv


func _draw() -> void:
	if removed:
		return
	if kind == "window":
		_draw_window()
	else:
		_draw_strip()
	_draw_holes()
	_draw_ends()


func _strip_tex(lv: int) -> Texture2D:
	var suffix: String = ["", "_cracked", "_broken"][lv]
	return Art.tex(_prefix + suffix)


func _dest_h(tex: Texture2D) -> float:
	var mf: float = MARGIN_FRAC.get(_prefix, 0.15)
	return _t / (1.0 - 2.0 * mf)


func _draw_strip() -> void:
	var n := _chunks.size()
	var cw := _len / n
	# merge runs of equal damage level: one region draw per run (few draw calls)
	var runs: Array = []          # [level, first, last]
	for i in n:
		var lv := _level(i)
		if runs.is_empty() or runs[-1][0] != lv:
			runs.append([lv, i, i])
		else:
			runs[-1][2] = i
	for r in runs:
		var x0: float = -_len * 0.5 + r[1] * cw
		var x1: float = -_len * 0.5 + (r[2] + 1) * cw
		var tex := _strip_tex(r[0])
		if tex == null:
			draw_rect(Rect2(Vector2(x0, -_t * 0.5), Vector2(x1 - x0, _t)), Color(0.25, 0.22, 0.2) if r[0] < 2 else Color(0.1, 0.08, 0.07))
			continue
		var dh := _dest_h(tex)
		var ts := tex.get_size()
		var a := to_global(Vector2(x0, 0)).dot(_ex) / Art.PX_PER_M
		var src := Rect2(Vector2(a * ts.x / STRIP_M, 0.0), Vector2((x1 - x0) / Art.PX_PER_M * ts.x / STRIP_M, ts.y))
		draw_texture_rect_region(tex, Rect2(Vector2(x0, -dh * 0.5), Vector2(x1 - x0, dh)), src)
	for r in runs:
		if r[0] < 2:
			_shade_band(-_len * 0.5 + r[1] * cw, -_len * 0.5 + (r[2] + 1) * cw)


## World-consistent light: a cool shadow band on the side facing down-right and
## a thin warm rim on the side facing up-left (the strips carry no light).
func _shade_band(x0: float, x1: float) -> void:
	var e := _t * 0.5 * _shade_side
	var inner := e - _shade_side * _t * 0.42
	var c0 := Color(0.05, 0.06, 0.1, 0.34)
	var c1 := Color(0.05, 0.06, 0.1, 0.0)
	draw_polygon(PackedVector2Array([Vector2(x0, e), Vector2(x1, e), Vector2(x1, inner), Vector2(x0, inner)]),
		PackedColorArray([c0, c0, c1, c1]))
	var r := -e + _shade_side * 1.6
	draw_line(Vector2(x0, r), Vector2(x1, r), Color(1.0, 0.94, 0.82, 0.25), 1.2)
	# heavy hand-inked edges (the strips' own lines are fine detail)
	for y in [-_t * 0.5, _t * 0.5]:
		draw_line(Vector2(x0, y), Vector2(x1, y), Art.INK, 2.2)


func _draw_window() -> void:
	var name_ := "window"
	if stage() == 2:
		name_ = "window_broken"
	elif glass == 2:
		name_ = "window_shattered"
	elif glass == 1:
		name_ = "window_cracked"
	var tex := Art.tex(name_)
	if tex == null:
		draw_rect(Rect2(Vector2(-_len * 0.5, -_t * 0.5), Vector2(_len, _t)), Color(0.5, 0.6, 0.66))
		return
	var dh := _dest_h(tex)
	draw_texture_rect(tex, Rect2(Vector2(-_len * 0.5, -dh * 0.5), Vector2(_len, dh)), false)
	if stage() < 2:
		_shade_band(-_len * 0.5, _len * 0.5)


func _draw_holes() -> void:
	var n := _chunks.size()
	var cw := _len / n
	for h in _holes:
		var ci := clampi(int((h.x + _len * 0.5) / cw), 0, n - 1)
		if _level(ci) >= 2:
			continue
		var p := Vector2(h.x, h.y)
		var r: float = h.z
		# splinter fringe of fresh raw wood, then the dark puncture
		for k in 6:
			var a := float(k) / 6.0 * TAU + float(int(h.x * 7.0) % 5)
			var q := p + Vector2(cos(a), sin(a)) * r * 1.5
			draw_line(p, q, Color(0.82, 0.66, 0.46, 0.9), 0.9)
		draw_circle(p, r * 1.05, Art.INK)
		draw_circle(p + Vector2(-0.3, -0.3), r * 0.55, Color(0.02, 0.015, 0.01))


func _draw_ends() -> void:
	for e in 2:
		var x := (-0.5 if e == 0 else 0.5) * _len
		var sgn := -1.0 if e == 0 else 1.0
		var nb = neighbours[e]
		if end_door[e]:
			draw_line(Vector2(x, -_t * 0.5), Vector2(x, _t * 0.5), Art.INK, 2.0)
		elif nb != null and is_instance_valid(nb) and nb.removed:
			# torn end: splinters sticking out into the gap
			var rr := RandomNumberGenerator.new()
			rr.seed = hash(name + str(e))
			for k in 5:
				var y := rr.randf_range(-_t * 0.45, _t * 0.45)
				var ln := rr.randf_range(3.0, 8.0)
				var wd := rr.randf_range(1.0, 2.2)
				var tip := Vector2(x + sgn * ln, y + rr.randf_range(-2.0, 2.0))
				var pts := PackedVector2Array([Vector2(x - sgn * 1.0, y - wd), tip, Vector2(x - sgn * 1.0, y + wd)])
				draw_colored_polygon(pts, Color(0.78, 0.62, 0.42))
				pts.append(pts[0])
				draw_polyline(pts, Art.INK, 0.8)
