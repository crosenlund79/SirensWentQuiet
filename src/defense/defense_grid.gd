class_name DefenseGrid
extends Node3D
## Exp 006 (D): trenches and water moats on the outdoor lot of the ground
## storey, and the bookkeeping the other defences (spikes, drawbridges) need.
## HouseWorld owns one (`world.defense`, a child node) and calls it from its
## navigation, exit rule, weak points and save.
##
## Trenches are 1 m cells (plan cell (x, y) = [x, x+1) x [y, y+1), as
## Levels.cell_of) in `cells`: DRY or WET. Water is simplified, not
## simulated: a connected section (4-neighbours) is all dry or all wet, so
## digging next to water floods the new cell (and any dry section it joins),
## and filling floods the whole connected section at once. Water comes free
## from a rain collector standing next to the section (its downpipe), or
## costs 1 bottled water per WATER_PER_CELLS cells.
##
## Navigation (GridNav raw kinds): a wet cell is WATER (blocked for everyone
## except waders, see WeightedNav), a dry one TRENCH (walkable, costly). A
## drawbridge (WorldObject "drawbridge_1"/"drawbridge_2") over trench cells
## overrides them: OPEN when lowered, WALL (bashed like a door) when raised.
## Changes recompute navigation only around the changed cells.
##
## Bodies: in a dry trench they slow down and stand SINK_TRENCH lower; a
## wading brute SINK_WATER lower and slower. The player can't step into
## water: an invisible barrier (BARRIER_LAYER, which only the player's body
## collides with) covers every wet cell not under a lowered drawbridge.
## Spikes (WorldObject "spikes_wood"/"spikes_metal") hurt an enemy pressing
## against them, once per its contact cooldown (enemy_step).
##
## The exit rule (HouseWorld.exit_path_exists) counts water as blocking and
## drawbridges (raised or lowered: E lowers them) as passable; exit_extra()
## previews digs and fills.
##
## Save (HouseWorld world save, optional "defense"): {"cells": [[x, y, wet]]}.

signal changed
## A raised drawbridge was battered to 1 HP: it crashed down, jammed lowered.
signal bridge_smashed(o: WorldObject)

enum { DRY = 0, WET = 1 }

const DEPTH := 0.8                   ## visual depth of a trench (m)
const WATER_Y := -0.36               ## water surface height
const SINK_TRENCH := 0.38            ## bodies in a dry trench stand this much lower
const SINK_WATER := 0.6              ## a wading brute
const TRENCH_SPEED := 0.55           ## x speed in a dry trench (enemies)
const WADE_SPEED := 0.4              ## x speed wading through water
const PLAYER_TRENCH_SPEED := 0.6     ## x speed of the player climbing through a dry trench
const SINK_RATE := 2.2               ## m/s the height eases toward its goal
const BARRIER_LAYER := 32            ## the player's "lot boundary" layer: only the player collides
const HOUSE_CLEAR := 0.4             ## trenches keep this far from the house's footprint
const COLLECTOR_REACH := 1.6         ## a rain collector this close to a section fills it free
const WATER_PER_CELLS := 4           ## otherwise 1 bottled water per this many cells
const DIG_MINUTES := 4.0             ## game minutes per dug cell
const DIG_ENERGY := 1.0              ## energy per dug cell
const BACKFILL_MINUTES := 2.0
const MIN_ENERGY := 5.0
## Spike contact: [damage, cooldown s] per kind; reach beyond the body's radius.
const SPIKE_HIT := {"spikes_wood": [1, 1.8], "spikes_metal": [2, 1.5]}
const SPIKE_REACH := 0.2
## A drawbridge can be raised only with at least this share of its HP.
const RAISE_MIN_HP := 0.5
## Props one can't dig through (the flat ones can be: path, driveway, road).
const DIGGABLE_PROPS := ["path", "driveway", "road"]
## The ground image the hole mask covers (1 texel per 1 m cell).
const HOLE_ORIGIN := Vector2i(-6, -5)
const HOLE_SIZE := Vector2i(28, 20)
const EARTH := [Color(0.31, 0.24, 0.18), Color(0.28, 0.22, 0.16), Color(0.34, 0.27, 0.2), Color(0.26, 0.2, 0.15)]
const SPOIL := Color(0.4, 0.33, 0.26)
const SNOW_DUST := Color(0.82, 0.84, 0.87)

var world: HouseWorld
var cells := {}                      ## Vector2i -> DRY | WET
var revision := 0
var barrier_shapes := 0              ## shapes in the water barrier (tests)
var _earth: MeshInstance3D
var _water: MeshInstance3D
var _barrier: StaticBody3D
var _hole_img: Image
var _hole_tex: ImageTexture
var _bridge_sig := ""
var _spikes: Array = []
var _water_mat: StandardMaterial3D
var _cover_pending := false


func setup(w: HouseWorld) -> void:
	world = w
	name = "Defenses"
	if not w.structure_changed.is_connected(_on_structure_changed):
		w.structure_changed.connect(_on_structure_changed)


func _ready() -> void:
	_earth = MeshInstance3D.new()
	_earth.name = "Trenches"
	add_child(_earth)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_barrier = StaticBody3D.new()
	_barrier.name = "WaterBarrier"
	_barrier.collision_layer = BARRIER_LAYER
	_barrier.collision_mask = 0
	add_child(_barrier)
	if not cells.is_empty():
		_rebuild_all()


# --- cells ---------------------------------------------------------------------------

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c), Vector2.ONE)


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


func has(c: Vector2i) -> bool:
	return cells.has(c)


func is_wet(c: Vector2i) -> bool:
	return int(cells.get(c, DRY)) == WET


## -1 off the trenches, else DRY or WET, at plan point p.
func state_at(p: Vector2) -> int:
	return int(cells.get(cell_of(p), -1))


func wet_count() -> int:
	var n := 0
	for c in cells:
		if cells[c] == WET:
			n += 1
	return n


## The raw nav kind a trench gives nav cell `nc` (-1 = no trench there).
func nav_kind_at(nc: Vector2i) -> int:
	if cells.is_empty() or world == null or world.nav == null:
		return -1
	var c := cell_of(world.nav.center_of(nc))
	if not cells.has(c):
		return -1
	return GridNav.WATER if cells[c] == WET else GridNav.TRENCH


## The connected trench section containing c (4-neighbours), in `grid`.
static func flood(grid: Dictionary, c: Vector2i) -> Array:
	if not grid.has(c):
		return []
	var out := [c]
	var seen := {c: true}
	var k := 0
	while k < out.size():
		var a: Vector2i = out[k]
		k += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var b: Vector2i = a + d
			if grid.has(b) and not seen.has(b):
				seen[b] = true
				out.append(b)
	return out


func section(c: Vector2i) -> Array:
	return flood(cells, c)


## Why cell c can't be dug ("" = it can). Doesn't check tools or energy.
func dig_reason(c: Vector2i) -> String:
	var r := cell_rect(c)
	if cells.has(c):
		return "Already dug."
	if not HouseWorld.LOT.encloses(r):
		return "Outside the lot: the fog starts there."
	if HousePlan.FOOTPRINT.grow(HOUSE_CLEAR).intersects(r):
		return "Too close to the house: it would undermine the walls."
	var inner := r.grow(-0.05)
	for f in HousePlan.PROPS:
		if not (f["type"] in DIGGABLE_PROPS) and (f["rect"] as Rect2).intersects(inner):
			return "The %s is in the way." % str(f["type"]).replace("_", " ").replace(" dead", "").replace(" tipped", "")
	if world == null:
		return ""
	if world.furniture_in(inner):
		return "Something is in the way."
	if not world.objects_in(inner).is_empty():
		return "Something is standing here."
	for s in world.foundations:
		if HouseWorld.seg_rect(s, HouseWorld.FOUNDATION_HALF).intersects(inner):
			return "There's a stone foundation here."
	if world.design != null and world.design.any_struct_in(inner.position, inner.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
		return "There's a wall in the way."
	if world.is_inside_tree() and world.bodies_in(r.grow(-0.02)):
		return "Someone is standing there."
	return ""


## What digging `new` cells changes: {cell: DRY | WET} for the new cells and
## for every dry cell a new cell connects to water.
func dig_changes(new: Array) -> Dictionary:
	var tmp := cells.duplicate()
	for c in new:
		if not tmp.has(c):
			tmp[c] = DRY
	var out := {}
	var seen := {}
	for c in new:
		if seen.has(c):
			continue
		var sec := flood(tmp, c)
		var wet := false
		for k in sec:
			seen[k] = true
			if int(tmp[k]) == WET:
				wet = true
		for k in sec:
			var st := WET if wet else DRY
			if not cells.has(k) or int(cells[k]) != st:
				out[k] = st
	return out


## What filling the section at c changes ({} if c isn't a dry trench).
func fill_changes(c: Vector2i) -> Dictionary:
	var out := {}
	if not cells.has(c) or is_wet(c):
		return out
	for k in section(c):
		out[k] = WET
	return out


## The water a fill of `n` cells next to (or away from) a rain collector costs.
static func fill_cost(n: int, near_collector: bool) -> Dictionary:
	if near_collector or n <= 0:
		return {}
	return {"water": ceili(float(n) / WATER_PER_CELLS)}


## True if a rain collector stands within COLLECTOR_REACH of any of `sec`.
func collector_near(sec: Array) -> bool:
	if world == null:
		return false
	for o in world.objects:
		if o.kind != "rain_collector":
			continue
		var fp := o.footprint().grow(COLLECTOR_REACH)
		for c in sec:
			if fp.intersects(cell_rect(c)):
				return true
	return false


## Exit-rule preview of `changes` (HouseWorld.exit_path_exists(extra)): nav
## cell -> GridNav kind for every cell that becomes water (cells under a
## drawbridge stay passable, as the rule counts bridges).
func exit_extra(changes: Dictionary) -> Dictionary:
	var extra := {}
	if world == null:
		return extra
	for c in changes:
		if int(changes[c]) != WET or bridge_over(c) != null:
			continue
		for nc in world.nav.cells_in_rect(cell_rect(c)):
			extra[nc] = GridNav.WATER
	return extra


## True if `changes` keep a way out (the last-exit rule).
func keeps_exit(changes: Dictionary) -> bool:
	var extra := exit_extra(changes)
	return extra.is_empty() or world.exit_path_exists(extra)


## True if a body stands in any cell that would become water.
func bodies_in_changes(changes: Dictionary) -> bool:
	if world == null or not world.is_inside_tree():
		return false
	for c in changes:
		if int(changes[c]) == WET and world.bodies_in(cell_rect(c).grow(-0.02)):
			return true
	return false


## Applies {cell: state} (and erases cells mapped to -1): navigation around
## each changed cell, the meshes, the barrier and the ground.
func apply_changes(changes: Dictionary) -> void:
	if changes.is_empty():
		return
	for c in changes:
		if int(changes[c]) < 0:
			cells.erase(c)
		else:
			cells[c] = int(changes[c])
	_refresh_nav(changes.keys())
	revision += 1
	_rebuild_all()
	changed.emit()


## Re-reads the raw nav kind of the nav cells inside the changed trench
## cells and refreshes only the 3x3 neighbourhoods of those that changed.
func _refresh_nav(changed_cells: Array) -> void:
	if world == null or world.nav == null:
		return
	var nav := world.nav
	var dirty := {}
	for c in changed_cells:
		for nc in nav.cells_in_rect(cell_rect(c)):
			var k := world._cell_kind(nc)
			if k == nav.get_raw(nc):
				continue
			nav.set_raw(nc, k)
			for dj in range(-1, 2):
				for di in range(-1, 2):
					dirty[nc + Vector2i(di, dj)] = true
	if not dirty.is_empty():
		nav.refresh_cells(dirty.keys())


func dig(new: Array) -> Dictionary:
	var ch := dig_changes(new)
	apply_changes(ch)
	return ch


func fill(c: Vector2i) -> Dictionary:
	var ch := fill_changes(c)
	apply_changes(ch)
	return ch


## Fills a trench cell back in (its section's other cells keep their water).
func backfill(c: Vector2i) -> bool:
	if not cells.has(c):
		return false
	apply_changes({c: -1})
	return true


# --- drawbridges and spikes ----------------------------------------------------------------

static func is_bridge(kind: String) -> bool:
	return kind == "drawbridge_1" or kind == "drawbridge_2"


static func is_spikes(kind: String) -> bool:
	return kind == "spikes_wood" or kind == "spikes_metal"


static func span_of(kind: String) -> int:
	return 2 if kind == "drawbridge_2" else 1


## The drawbridge whose span covers trench cell c, or null.
func bridge_over(c: Vector2i) -> WorldObject:
	if world == null:
		return null
	var p := cell_center(c)
	for o in world.objects:
		if is_bridge(o.kind) and o.footprint().has_point(p):
			return o
	return null


func bridges() -> Array:
	var out := []
	if world != null:
		for o in world.objects:
			if is_bridge(o.kind):
				out.append(o)
	return out


## Where a drawbridge of `span` cells would go with its span crossing trench
## cell c along rotation r's axis: {"pos", "rot", "cells", "reason"}. The
## front (the far end) faces away from the house; the hinge is on the house
## side. `r` picks the axis (0/2: north-south crossing, 1/3: east-west); the
## other axis is tried when that one doesn't fit.
func bridge_fit(c: Vector2i, span: int, r: int) -> Dictionary:
	var best := {}
	for axis in [posmod(r, 2), 1 - posmod(r, 2)]:
		var fits := _bridge_fit_axis(c, span, axis)
		if fits["reason"] == "":
			return fits
		if best.is_empty():
			best = fits
	return best


func _bridge_fit_axis(c: Vector2i, span: int, axis: int) -> Dictionary:
	var home := HousePlan.FOOTPRINT.get_center()
	var out := {"pos": cell_center(c), "rot": 0, "cells": [c], "reason": ""}
	if not cells.has(c):
		out["reason"] = "A drawbridge goes across a trench: aim at a trench cell."
		return out
	# the outward direction along the axis (front = away from the house)
	var dir := Vector2i(0, 1) if axis == 0 else Vector2i(1, 0)
	var cc := cell_center(c)
	if (cc - home).dot(Vector2(dir)) < 0.0:
		dir = -dir
	var options := [[c, c + dir], [c - dir, c]] if span == 2 else [[c]]
	var reason := ""
	for span_cells in options:
		var why := _span_reason(span_cells, dir)
		if why == "":
			var a: Vector2 = cell_center(span_cells[0])
			var b: Vector2 = cell_center(span_cells[span_cells.size() - 1])
			out["pos"] = (a + b) * 0.5
			out["cells"] = span_cells
			out["rot"] = _rot_of(dir)
			out["reason"] = ""
			return out
		if reason == "":
			reason = why
	out["rot"] = _rot_of(dir)
	out["reason"] = reason
	return out


static func _rot_of(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1):
		return 0
	if dir == Vector2i(1, 0):
		return 1
	if dir == Vector2i(0, 1):
		return 2
	return 3


func _span_reason(span_cells: Array, dir: Vector2i) -> String:
	for k in span_cells:
		if not cells.has(k):
			return "The span must lie over the trench (it's %d m long)." % span_cells.size()
		if bridge_over(k) != null:
			return "There's already a drawbridge here."
	var near: Vector2i = span_cells[0] - dir
	var far: Vector2i = span_cells[span_cells.size() - 1] + dir
	for end in [near, far]:
		if cells.has(end):
			return "Both ends must rest on firm ground: the trench is wider than the span."
		var p := cell_center(end) - Vector2(dir) * 0.35 * (1.0 if end == far else -1.0)
		if not HouseWorld.LOT.grow(0.6).has_point(p):
			return "Outside the lot: the fog starts there."
		if world != null and world.nav != null and world.nav.get_raw(world.nav.cell_of(p)) in [GridNav.WALL, GridNav.SOLID]:
			return "Something blocks the end of the span."
	if world != null:
		var rect := Rect2()
		for k in span_cells:
			rect = cell_rect(k) if rect.size == Vector2.ZERO else rect.merge(cell_rect(k))
		for o in world.objects_in(rect.grow(-0.08)):
			if not is_bridge(o.kind):
				return "Something is standing in the trench."
		if world.is_inside_tree() and world.bodies_in(rect.grow(-0.05)):
			return "Someone is standing there."
	return ""


## Raises (lowered = false) or lowers a drawbridge. Returns "" or why not.
func set_bridge(o: WorldObject, lowered: bool, instant := false) -> String:
	if o == null or not is_bridge(o.kind) or o.open == lowered:
		return ""
	if not lowered:
		if o.hp < ceili(o.max_hp * RAISE_MIN_HP):
			return "The drawbridge is too damaged to raise: repair it first."
		var why := _clear_span(o)
		if why != "":
			return why
	o.set_open(lowered, instant)
	if world != null and world.nav != null:
		world._recompute_nav(o.footprint().grow(GridNav.CELL))
	if not instant:
		Sfx.play("door/open" if lowered else "door/close", Vector3(o.pos.x, 0.6, o.pos.y))
		Sfx.play("build/hammer", Vector3(o.pos.x, 0.6, o.pos.y))
	_refresh_barrier()
	if world != null:
		world.structure_changed.emit()
	return ""


func toggle_bridge(o: WorldObject) -> String:
	return set_bridge(o, not o.open)


## Before raising: enemies on the span refuse it; the player steps off to
## the hinge (house) side.
func _clear_span(o: WorldObject) -> String:
	if world == null or not world.is_inside_tree():
		return ""
	var rect := o.footprint().grow(0.05)
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 1.4, rect.size.y)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), Vector3(rect.get_center().x, 0.85, rect.get_center().y))
	q.collision_mask = 4 | 8
	var players: Array[Node3D] = []
	for hit in world.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var b := hit["collider"] as CollisionObject3D
		if b == null or (b.collision_layer & 4) == 0 or not (b is Node3D):
			return "Something is on the bridge."
		players.append(b as Node3D)
	var back := -WorldObject.front_dir(o.rot)
	var span := float(span_of(o.kind))
	var land := o.pos + back * (span * 0.5 + 0.45)
	for b in players:
		b.global_position = Vector3(land.x, b.global_position.y, land.y)
		if b is CharacterBody3D:
			(b as CharacterBody3D).velocity = Vector3.ZERO
	return ""


## A raised drawbridge battered down to nothing crashes down instead of
## vanishing: it lies lowered at 1 HP (too damaged to raise) until repaired.
## Called by WorldObject.take_damage.
func smash_bridge(o: WorldObject) -> void:
	o.hp = 1
	o.set_open(true, false)
	if world != null and world.nav != null:
		world._recompute_nav(o.footprint().grow(GridNav.CELL))
	Sfx.play("structure/break", Vector3(o.pos.x, 0.5, o.pos.y))
	_refresh_barrier()
	bridge_smashed.emit(o)
	if world != null:
		world.structure_changed.emit()


## Weak points for bombers (HouseWorld.weak_points format): raised drawbridges.
func weak_points(from: Vector2, near: Vector2) -> Array:
	var out := []
	if world == null:
		return out
	var wood_door := float(WorldObject.max_hp_of("door", "wood"))
	for o in bridges():
		if o.open:
			continue
		var front := WorldObject.front_dir(o.rot)
		var tip: Vector2 = o.pos + front * (span_of(o.kind) * 0.5)
		var stand := world._stand_point(tip, front)
		if stand == Vector2.INF:
			continue
		var seg := Vector3i(7, roundi(o.pos.x * 4.0), roundi(o.pos.y * 4.0))     # a unique key (not a wall segment)
		out.append(world._weak_point("drawbridge", stand, tip, 1.0, float(o.hp) / wood_door, from, near, seg, o, o.mat))
	return out


# --- bodies --------------------------------------------------------------------------------

## A lowered drawbridge under plan point p (bodies walk on its deck).
func _on_deck(p: Vector2) -> bool:
	if world == null:
		return false
	for o in world.objects:
		if is_bridge(o.kind) and o.open and o.footprint().grow(0.05).has_point(p):
			return true
	return false


## [sink depth, speed factor] for a body at p (wader: may stand in water).
func ground_at(p: Vector2, wader := false) -> Array:
	var st := state_at(p)
	if st < 0 or _on_deck(p):
		return [0.0, 1.0]
	if st == WET:
		return [SINK_WATER, WADE_SPEED] if wader else [SINK_TRENCH, TRENCH_SPEED]
	return [SINK_TRENCH, TRENCH_SPEED]


## Per physics frame for a living ground-floor enemy (AIEnemy calls it):
## the trench or water under it, and the spikes it presses against.
func enemy_step(e: AIEnemy, delta: float) -> void:
	var p := e.plan_pos()
	if not cells.is_empty():
		var g := ground_at(p, e.wades())
		e.terrain_scale = g[1]
		e.floor_y = move_toward(e.floor_y, -float(g[0]), SINK_RATE * delta)
	elif e.terrain_scale != 1.0 or e.floor_y < 0.0:
		e.terrain_scale = 1.0
		e.floor_y = move_toward(e.floor_y, 0.0, SINK_RATE * delta)
	e.spike_cd = maxf(e.spike_cd - delta, 0.0)
	if e.spike_cd > 0.0 or _spikes.is_empty() or e.retreating:
		return
	var reach := float(e.def.get("radius", 0.25)) + SPIKE_REACH
	for o in _spikes:
		if not is_instance_valid(o) or o.hp <= 0:
			continue
		var fp: Rect2 = o.footprint()
		var q := p.clamp(fp.position, fp.end)
		if q.distance_to(p) > reach:
			continue
		var hit: Array = SPIKE_HIT.get(o.kind, [1, 1.8])
		e.spike_cd = float(hit[1])
		var dir := Vector3(p.x - q.x, 0, p.y - q.y)
		e.take_damage(int(hit[0]), dir if dir.length() > 0.01 else Vector3.FORWARD, "spikes")
		if world != null and world.fx != null:
			var at := Vector3(q.x, 0.6, q.y)
			world.fx.debris(at, Vector3(dir.x, 1.2, dir.z), Color(0.45, 0.06, 0.05), 0.5)
		return


## The player's step (the game calls it while the player is on the ground
## floor): returns the speed factor and eases the player's floor height.
func player_step(pl: Node3D, delta: float) -> float:
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var g := ground_at(p) if not cells.is_empty() else [0.0, 1.0]
	var y := float(pl.get("floor_y"))
	var goal := -float(g[0])
	if not is_equal_approx(y, goal):
		pl.set("floor_y", move_toward(y, goal, SINK_RATE * delta))
	return PLAYER_TRENCH_SPEED if g[0] > 0.0 else 1.0


# --- persistence ---------------------------------------------------------------------------

func save_data() -> Dictionary:
	var list := []
	for c in cells:
		list.append([c.x, c.y, int(cells[c])])
	return {"cells": list}


## Restores saved trenches (anything malformed is dropped; a section with any
## water is all water).
func load_data(d: Variant) -> void:
	var loaded := {}
	if d is Dictionary and (d as Dictionary).get("cells") is Array:
		for e in d["cells"]:
			if not (e is Array) or (e as Array).size() != 3:
				continue
			var ok := true
			for x in e:
				if typeof(x) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(x)):
					ok = false
			if not ok:
				continue
			var c := Vector2i(int(e[0]), int(e[1]))
			if not HouseWorld.LOT.encloses(cell_rect(c)) or HousePlan.FOOTPRINT.grow(HOUSE_CLEAR).intersects(cell_rect(c)):
				continue
			loaded[c] = WET if int(e[2]) == WET else DRY
	var fixed := {}
	for c in loaded:
		if fixed.has(c):
			continue
		var sec := flood(loaded, c)
		var wet := false
		for k in sec:
			if loaded[k] == WET:
				wet = true
		for k in sec:
			fixed[k] = WET if wet else DRY
	cells.clear()
	apply_changes(fixed)
	if fixed.is_empty():
		_rebuild_all()


# --- visuals -------------------------------------------------------------------------------

func _on_structure_changed() -> void:
	_spikes.clear()
	if world != null:
		for o in world.objects:
			if is_spikes(o.kind):
				_spikes.append(o)
	var sig := _bridges_signature()
	if sig != _bridge_sig:
		_refresh_barrier()


func _bridges_signature() -> String:
	var s := ""
	for o in bridges():
		s += "%d,%d,%d,%d;" % [roundi(o.pos.x * 10), roundi(o.pos.y * 10), o.rot, 1 if o.open else 0]
	return s


func _rebuild_all() -> void:
	_on_structure_changed()
	_refresh_barrier()
	_build_meshes()
	_apply_ground()


## One box per wet cell that no lowered drawbridge covers (player only).
func _refresh_barrier() -> void:
	_bridge_sig = _bridges_signature()
	if _barrier == null:
		return
	for ch in _barrier.get_children():
		_barrier.remove_child(ch)
		ch.queue_free()
	barrier_shapes = 0
	for c in cells:
		if cells[c] != WET:
			continue
		var b := bridge_over(c)
		if b != null and b.open:
			continue
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 2.4, 1.0)
		cs.shape = box
		var cc := cell_center(c)
		cs.position = Vector3(cc.x, 1.0, cc.y)
		_barrier.add_child(cs)
		barrier_shapes += 1


func _build_meshes() -> void:
	if _earth == null:
		return
	if cells.is_empty():
		_earth.mesh = null
		_water.mesh = null
		return
	var mm := PropMesh.new()
	var top := VoxelYard.GROUND_Y
	for c in cells:
		var tone: Color = EARTH[(c.x * 7 + c.y * 13) & 3]
		var x0 := float(c.x)
		var z0 := float(c.y)
		mm.set_mat(PropMaterials.L_SOIL, tone.darkened(0.25), 0.4)
		mm.quad(Vector3(x0, -DEPTH, z0), Vector3(x0 + 1, -DEPTH, z0), Vector3(x0 + 1, -DEPTH, z0 + 1), Vector3(x0, -DEPTH, z0 + 1), Vector3.UP)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has(c + d):
				continue
			# the earth wall on this side, facing into the trench
			var a: Vector3
			var b: Vector3
			if d.x != 0:
				var ex := x0 + (1.0 if d.x > 0 else 0.0)
				a = Vector3(ex, 0, z0)
				b = Vector3(ex, 0, z0 + 1)
			else:
				var ez := z0 + (1.0 if d.y > 0 else 0.0)
				a = Vector3(x0, 0, ez)
				b = Vector3(x0 + 1, 0, ez)
			mm.set_mat(PropMaterials.L_SOIL, tone, 0.3)
			mm.quad(a + Vector3(0, top, 0), b + Vector3(0, top, 0), b + Vector3(0, -DEPTH, 0), a + Vector3(0, -DEPTH, 0), Vector3(-d.x, 0, -d.y))
			# a low spoil heap along the lip outside, dusted with snow
			var o1 := Vector3(d.x, 0, d.y) * 0.02
			var o2 := Vector3(d.x, 0, d.y) * 0.17
			var lo := (a + o1).min(b + o2)
			var hi := (a + o1).max(b + o2)
			mm.set_mat(PropMaterials.L_SOIL, SPOIL.lerp(SNOW_DUST, 0.35), 0.25)
			mm.box(Vector3(lo.x, top, lo.z), Vector3(hi.x, top + 0.06, hi.z))
	var em := mm.commit()
	if em.get_surface_count() > 0:
		em.surface_set_material(0, PropMaterials.kit())
	_earth.mesh = em
	# water: one quad per wet cell
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in cells:
		if cells[c] != WET:
			continue
		any = true
		var x0 := float(c.x)
		var z0 := float(c.y)
		st.set_normal(Vector3.UP)
		for v in [Vector3(x0, WATER_Y, z0), Vector3(x0 + 1, WATER_Y, z0), Vector3(x0 + 1, WATER_Y, z0 + 1),
				Vector3(x0, WATER_Y, z0), Vector3(x0 + 1, WATER_Y, z0 + 1), Vector3(x0, WATER_Y, z0 + 1)]:
			st.add_vertex(v)
	if any:
		var wm := st.commit()
		wm.surface_set_material(0, _water_material())
		_water.mesh = wm
	else:
		_water.mesh = null


func _water_material() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color(0.07, 0.1, 0.12)
		_water_mat.roughness = 0.06
		_water_mat.metallic = 0.25
		_water_mat.metallic_specular = 0.9
		_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_mat


## Cuts the trench cells out of the ground plane (voxel_ground.gdshader's
## hole mask), keeps grass tufts and shrubs out of them.
func _apply_ground() -> void:
	if world == null or world.yard == null:
		return
	var ground := world.yard.get_node_or_null("Ground") as MeshInstance3D
	if ground != null and ground.material_override is ShaderMaterial:
		if _hole_img == null:
			_hole_img = Image.create(HOLE_SIZE.x, HOLE_SIZE.y, false, Image.FORMAT_L8)
		_hole_img.fill(Color.BLACK)
		for c in cells:
			var px: Vector2i = c - HOLE_ORIGIN
			if px.x >= 0 and px.y >= 0 and px.x < HOLE_SIZE.x and px.y < HOLE_SIZE.y:
				_hole_img.set_pixel(px.x, px.y, Color.WHITE)
		if _hole_tex == null:
			_hole_tex = ImageTexture.create_from_image(_hole_img)
		else:
			_hole_tex.update(_hole_img)
		var m := ground.material_override as ShaderMaterial
		m.set_shader_parameter("hole_tex", _hole_tex)
		m.set_shader_parameter("hole_rect", Vector4(HOLE_ORIGIN.x, HOLE_ORIGIN.y, HOLE_SIZE.x, HOLE_SIZE.y))
		m.set_shader_parameter("holes", 1.0 if not cells.is_empty() else 0.0)
	if not _cover_pending:          # the grass tufts are rebuilt once per frame at most
		_cover_pending = true
		_cover_changed.call_deferred()


func _cover_changed() -> void:
	_cover_pending = false
	if world != null and is_instance_valid(world):
		world.ground_cover_changed()


## Plan rects of the trench cells (no grass or shrubs grow in them).
func cover_rects() -> Array:
	var out := []
	for c in cells:
		out.append(cell_rect(c))
	return out
