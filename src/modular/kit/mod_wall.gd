class_name ModWall
extends StaticBody3D
## Kit piece: one wall module (normally 1 m) on the house grid.
##
## Kinds: SOLID, WINDOW (glass + frame), DOOR (open doorway with a standing-open
## leaf; not destructible). Solid and window modules have hit points
## (Tuning.WALL_SECTION_HP) and four visible damage states:
##   INTACT -> DAMAGED (holes, loose boards, chipped plaster)
##          -> HEAVY (ragged hole, broken stud, torn insulation)
##          -> DESTROYED (stubs, hanging studs, rubble; no collision)
## The module owns its collision; ModHouse owns navigation updates.
##
## Module space: x along the wall (0..length), y up, side A faces +z, side B -z.

signal state_changed(module: ModWall, old_state: int)

enum Kind { SOLID, WINDOW, DOOR }
enum State { INTACT, DAMAGED, HEAVY, DESTROYED }

const DAMAGED_AT := 7
const HEAVY_AT := 3
const GLASS_HITS := 2
const MAX_MARKS := 20
const LAYER_WALLS := 2

# --- configuration (set before the module enters the tree) ---------------------
var kind := Kind.SOLID
var length := 1.0
var thickness := HousePlan.EXTERIOR_THICKNESS
var exterior := false
var outside := -1                 ## -1 interior wall, 0 side A is outdoors, 1 side B
var tint_a := Color.WHITE         ## room paint on side A
var tint_b := Color.WHITE
var sill := HousePlan.WINDOW_SILL
var head := HousePlan.WINDOW_HEAD
var door_style := ""              ## "front", "back" or "interior"
var door_swing := 1.0             ## leaf opens toward +z (1) or -z (-1)
var door_hinge_end := false       ## hinge at x = length instead of x = 0
var plan_rect := Rect2()          ## real footprint in plan meters
var wall_id := ""
var world_x0 := 0.0               ## world coordinate (along the wall) of local x = 0
var seed := 0

# --- state ----------------------------------------------------------------------
var hp := Tuning.WALL_SECTION_HP
var state := State.INTACT
var glass_hits := 0
var impacts: Array[Vector2] = []  ## local (x, y) of hits
var cut := 100.0                  ## current cutaway height (100 = full)
var cut_target := 100.0

var _body: MeshInstance3D
var _glass: MeshInstance3D
var _leaf: MeshInstance3D
var _marks: MultiMeshInstance3D
var _rubble: MeshInstance3D
var _shapes: Array[CollisionShape3D] = []
var _glass_shape: CollisionShape3D


func _ready() -> void:
	collision_layer = LAYER_WALLS
	collision_mask = 0
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.material_override = ModMaterials.kit()
	add_child(_body)
	_set_body_mesh(ModWallGeometry.intact(self))
	_build_collision()
	if kind == Kind.WINDOW:
		_glass = MeshInstance3D.new()
		_glass.name = "Glass"
		_glass.mesh = ModWallGeometry.glass_mesh(self)
		_glass.material_override = ModMaterials.glass()
		_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glass)
	elif kind == Kind.DOOR:
		_leaf = MeshInstance3D.new()
		_leaf.name = "DoorLeaf"
		var w := length - 0.06
		_leaf.mesh = ModWallGeometry.door_leaf(door_style, w)
		_leaf.material_override = ModMaterials.kit()
		var t := thickness * 0.5
		var hinge := Vector3(length - 0.03 if door_hinge_end else 0.03, 0.0, door_swing * (t + 0.035))
		# standing fully open against the wall, slightly ajar
		var base_dir := -1.0 if door_hinge_end else 1.0
		var ang := deg_to_rad(174.0) * door_swing * base_dir
		var b := Basis(Vector3.UP, -ang)
		if door_hinge_end:
			b = b * Basis(Vector3.UP, PI)
		_leaf.transform = Transform3D(b, hinge)
		add_child(_leaf)


func is_destructible() -> bool:
	return kind != Kind.DOOR


func is_glass_intact() -> bool:
	return kind == Kind.WINDOW and glass_hits < GLASS_HITS


## Material struck at a local point (for effects): "glass", "siding", "plaster" or "trim".
func material_at(local: Vector3) -> String:
	if is_glass_intact() and local.y > sill and local.y < head and absf(local.z) < thickness * 0.5 - 0.01:
		return "glass"
	if kind == Kind.DOOR and local.y < head:
		return "trim"
	if state == State.DESTROYED:
		return "timber"
	var s := 0 if local.z > 0.0 else 1
	return "siding" if s == outside else "plaster"


## Apply one hit. `local` is the impact point in module space. Returns the
## struck material ("glass", "glass_shatter", "siding", "plaster", "trim", "timber").
func take_hit(local: Vector3, amount: int, bullet: bool) -> String:
	var mat := material_at(local)
	if mat == "glass":
		glass_hits += 1
		if glass_hits >= GLASS_HITS:
			_shatter_glass()
			return "glass_shatter"
		var wp := to_global(Vector3(local.x, local.y, ModWallGeometry._glass_z(self)))
		_glass.set_instance_shader_parameter("crack", Vector4(wp.x, wp.y, wp.z, 0.55))
		return "glass"
	if not is_destructible() or state == State.DESTROYED:
		return mat
	impacts.append(Vector2(local.x, local.y))
	if bullet and absf(absf(local.z) - thickness * 0.5) < 0.03:
		_add_mark(local, 0 if mat != "plaster" or randf() < 0.7 else 2, mat)
	elif not bullet:
		_add_mark(Vector3(local.x, local.y, signf(local.z) * thickness * 0.5), 1, mat)
	_damage(amount)
	return mat


func _damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	var ns := state
	if hp == 0:
		ns = State.DESTROYED
	elif hp <= HEAVY_AT:
		ns = State.HEAVY
	elif hp <= DAMAGED_AT:
		ns = State.DAMAGED
	if ns != state:
		set_state(ns)


## Jump straight to a state (scenarios, tests). Hit points follow the state.
func set_state(ns: int) -> void:
	if ns == state:
		return
	var old := state
	state = ns
	match ns:
		State.DAMAGED:
			hp = mini(hp, DAMAGED_AT)
			_set_body_mesh(ModWallGeometry.damaged(self))
		State.HEAVY:
			hp = mini(hp, HEAVY_AT)
			if kind == Kind.WINDOW and is_glass_intact():
				glass_hits = GLASS_HITS
				_shatter_glass()
			_set_body_mesh(ModWallGeometry.heavy(self, _impact_center()))
			_hide_marks_inside(0.4)
		State.DESTROYED:
			hp = 0
			if kind == Kind.WINDOW and is_glass_intact():
				glass_hits = GLASS_HITS
				_shatter_glass()
			_set_body_mesh(ModWallGeometry.destroyed(self))
			_hide_marks_inside(10.0)
			for s in _shapes:
				s.disabled = true
			collision_layer = 0
			_rubble = MeshInstance3D.new()
			_rubble.name = "Rubble"
			_rubble.mesh = ModWallGeometry.rubble(self)
			_rubble.material_override = ModMaterials.kit()
			add_child(_rubble)
	state_changed.emit(self, old)


func set_cut(h: float) -> void:
	cut = h
	for g in [_body, _glass, _leaf, _marks]:
		if g != null:
			(g as GeometryInstance3D).set_instance_shader_parameter("cut_height", h)


func world_center() -> Vector3:
	return to_global(Vector3(length * 0.5, 1.2, 0.0))


func _set_body_mesh(m: Mesh) -> void:
	_body.mesh = m
	_body.set_instance_shader_parameter("tint_a", tint_a)
	_body.set_instance_shader_parameter("tint_b", tint_b)
	_body.set_instance_shader_parameter("cut_height", cut)


func _impact_center() -> Vector2:
	if impacts.is_empty():
		return Vector2(length * 0.5, 1.1)
	var c := Vector2.ZERO
	for p in impacts:
		c += p
	return c / impacts.size()


func _build_collision() -> void:
	var t := thickness
	match kind:
		Kind.SOLID:
			_add_box(Vector3(length * 0.5, HousePlan.WALL_HEIGHT * 0.5, 0), Vector3(length, HousePlan.WALL_HEIGHT, t))
		Kind.WINDOW:
			_add_box(Vector3(length * 0.5, sill * 0.5, 0), Vector3(length, sill, t))
			var top := HousePlan.WALL_HEIGHT - head
			_add_box(Vector3(length * 0.5, head + top * 0.5, 0), Vector3(length, top, t))
			_glass_shape = _add_box(Vector3(length * 0.5, (sill + head) * 0.5, 0), Vector3(length, head - sill, t * 0.5))
		Kind.DOOR:
			var top := HousePlan.WALL_HEIGHT - HousePlan.DOOR_HEIGHT
			_add_box(Vector3(length * 0.5, HousePlan.DOOR_HEIGHT + top * 0.5, 0), Vector3(length, top, t))


func _add_box(center: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = center
	add_child(cs)
	_shapes.append(cs)
	return cs


func _shatter_glass() -> void:
	if _glass != null:
		_glass.queue_free()
		_glass = null
	if _glass_shape != null:
		_glass_shape.disabled = true
		_shapes.erase(_glass_shape)
		_glass_shape.queue_free()
		_glass_shape = null
	# the frame stays (part of the body mesh); only the pane and its collider go


# --- bullet holes and cracks -------------------------------------------------------------

func _add_mark(local: Vector3, cell: int, mat: String) -> void:
	if _marks == null:
		_marks = MultiMeshInstance3D.new()
		_marks.name = "Marks"
		var mmesh := MultiMesh.new()
		mmesh.transform_format = MultiMesh.TRANSFORM_3D
		mmesh.use_custom_data = true
		mmesh.instance_count = MAX_MARKS
		mmesh.visible_instance_count = 0
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mmesh.mesh = q
		_marks.multimesh = mmesh
		_marks.material_override = ModMaterials.marks()
		_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_marks)
		_marks.set_instance_shader_parameter("cut_height", cut)
	var mm := _marks.multimesh
	var i := mm.visible_instance_count
	if i >= MAX_MARKS:
		i = randi() % MAX_MARKS
	else:
		mm.visible_instance_count = i + 1
	var nz := 1.0 if local.z > 0.0 else -1.0
	var size := randf_range(0.2, 0.27) if cell == 0 else randf_range(0.3, 0.42)
	var b := Basis(Vector3.UP, 0.0 if nz > 0.0 else PI) * Basis(Vector3.BACK, randf() * TAU).scaled(Vector3(size, size, size))
	var p := Vector3(local.x, local.y, nz * (thickness * 0.5 + 0.004 + i * 0.0002))
	mm.set_instance_transform(i, Transform3D(b, p))
	var tint := Color(0.82, 0.62, 0.4) if mat == "siding" else Color(0.86, 0.85, 0.82)
	mm.set_instance_custom_data(i, Color(cell, tint.r, tint.g, tint.b))


func _hide_marks_inside(margin: float) -> void:
	if _marks == null:
		return
	var mm := _marks.multimesh
	var c := _impact_center()
	for i in mm.visible_instance_count:
		var t := mm.get_instance_transform(i)
		if margin > 5.0 or Vector2(t.origin.x, t.origin.y).distance_to(c) < margin:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), t.origin))
