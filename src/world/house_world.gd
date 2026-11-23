class_name HouseWorld
extends Node3D
## The survival game's house and lot (SPEC §7.3). Owner: V.
##
## Foundation version: Version A's world logic lifted out of voxel_demo.gd
## (voxel house in chunks, GridNav, yard + roof, cutaway, shooting, enemy
## bites, fx) behind the agreed API. V extends it with the design/current
## grids, objects (doors, barricades, crates, collectors), hybrid furniture
## meshes, repair, persistence and the exit rule.

signal structure_changed
signal object_destroyed(kind: String, at: Vector3)

const SURFACE_SHADER := preload("res://src/voxel/shaders/voxel_surface.gdshader")
const GLASS_SHADER := preload("res://src/voxel/shaders/voxel_glass.gdshader")
const WALL_CARVE := 0.23
const PENETRATION := 1.5
const FLOOR_CARVE := 0.13
const FURNITURE_CARVE := 0.17
const BITE_RADIUS := 0.17
const CUT_RADIUS := 2.1

static var _pristine: VoxelGrid

var grid: VoxelGrid
var nav: GridNav
var fx: VoxelFx
var chunks: VoxelWorld
var yard: VoxelYard
var lighting: VoxelLighting
var surface_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var cut_materials: Array[ShaderMaterial] = []
var bed: Node3D

var _bullet_skip := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var _shots := 0
var _cut_origin := Vector3(0, -100, 0)
var _cut_dir := Vector3.UP
var _cut_radius := CUT_RADIUS


func setup(light: VoxelLighting) -> void:
	lighting = light


func _ready() -> void:
	_rng.seed = 1979
	_bullet_skip.resize(256)
	for i in 256:
		_bullet_skip[i] = 1 if (VoxelMat.FLAGS[i] & VoxelMat.F_PASS) != 0 else 0


## Fresh, undamaged house.
func build_new() -> void:
	surface_mat = _surface_material(VoxelHouse.ORIGIN, VoxelHouse.VS)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS_SHADER
	cut_materials.append(glass_mat)
	if lighting != null:
		lighting.night_materials.append(glass_mat)
	if _pristine == null:
		_pristine = VoxelHouse.create_grid()
		VoxelHouse.build(_pristine)
	grid = _pristine.copy()
	chunks = VoxelWorld.new()
	chunks.name = "VoxelWorld"
	chunks.setup(grid, surface_mat, glass_mat)
	add_child(chunks)
	chunks.build_all()
	nav = GridNav.new()
	HousePlan.rasterize_into(nav)
	for f in HousePlan.FURNITURE:
		if f["blocks"]:
			add_child(_box_body(f["rect"], maxf(f["height"], 0.4), 1 << 4))
	yard = VoxelYard.new()
	yard.name = "Yard"
	yard.demo = self
	add_child(yard)
	fx = VoxelFx.new()
	fx.grid = grid
	add_child(fx)
	bed = preload("res://src/world/bed_interactable.gd").new()
	for f in HousePlan.FURNITURE:
		if f["type"] == "bed":
			var c: Vector2 = (f["rect"] as Rect2).get_center()
			bed.position = Vector3(c.x, 0, c.y)
	add_child(bed)


## Foundation: persistence is V's job. Returns {} / false until implemented.
func save_data() -> Dictionary:
	return {}


func load_data(_d: Dictionary) -> bool:
	build_new()
	return false


# --- helpers used by VoxelYard (duck-typed "demo") ------------------------------------

func _surface_material(origin: Vector3, vs: float, model_space := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("grid_origin", origin)
	m.set_shader_parameter("voxel_size", vs)
	m.set_shader_parameter("model_space", 1.0 if model_space else 0.0)
	cut_materials.append(m)
	if lighting != null:
		lighting.night_materials.append(m)
	return m


func _box_body(rect: Rect2, height: float, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
	return body


# --- view ------------------------------------------------------------------------------

func update_view(player_pos: Vector3, camera: Camera3D, delta: float) -> void:
	_cut_origin = player_pos + Vector3(0, 1.0, 0)
	_cut_dir = (camera.global_position - _cut_origin).normalized()
	var dist := camera.global_position.distance_to(_cut_origin)
	_cut_radius = CUT_RADIUS + (dist - 20.0) * 0.03
	for m in cut_materials:
		m.set_shader_parameter("cut_origin", _cut_origin)
		m.set_shader_parameter("cut_dir", _cut_dir)
		m.set_shader_parameter("cut_radius", _cut_radius)
		m.set_shader_parameter("cut_floor", 0.45)
	if yard != null:
		yard.update_roof(player_pos, delta)


func is_cut(c: Vector3i) -> bool:
	var p := grid.center(c)
	var rel := p - _cut_origin
	var t := rel.dot(_cut_dir)
	if t <= 0.45 or p.y <= 0.45:
		return false
	return (rel - _cut_dir * t).length() < _cut_radius - 0.15


func aim_ray(from: Vector3, dir: Vector3) -> Vector3:
	var best := 200.0
	var vh := grid.raycast(from, dir, best, _bullet_skip, is_cut)
	if not vh.is_empty():
		best = vh["dist"]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * best, 1 | 8)
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	if not ph.is_empty():
		best = from.distance_to(ph["position"])
	if dir.y < -0.001:
		var tg := -from.y / dir.y
		if tg < best:
			best = tg
	return from + dir * best


# --- shooting --------------------------------------------------------------------------

## One bullet. Returns {"kind": "voxel"|"enemy"|"body"|"ground"|"none", "pos", "collider"}.
## `muzzle` (optional) is where the tracer starts.
func shoot(origin: Vector3, dir: Vector3, exclude: Array, muzzle := Vector3.INF) -> Dictionary:
	_shots += 1
	dir = dir.normalized()
	var best := Tuning.SHOT_RANGE
	var kind := "none"
	var vh := grid.raycast(origin, dir, best, _bullet_skip)
	if not vh.is_empty():
		best = vh["dist"]
		kind = "voxel"
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * best, 1 | 8)
	q.exclude = exclude
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = null
	if not ph.is_empty():
		best = origin.distance_to(ph["position"])
		col = ph["collider"]
		kind = "enemy" if col is VoxelEnemy else "body"
	if kind == "none" and dir.y < -0.001:
		var tg := -origin.y / dir.y
		if tg < best:
			best = tg
			kind = "ground"
	var hit := origin + dir * best
	match kind:
		"voxel":
			_hit_voxels(vh, dir)
		"enemy":
			(col as VoxelEnemy).take_hit(dir)
			fx.flesh_hit(hit, -dir, VoxelArt.to_color(0x5a5550))
		"body":
			var imp: int = col.get_meta("impact", VoxelMat.Impact.DUST) if col != null else VoxelMat.Impact.DUST
			fx.impact(imp, hit, ph["normal"], dir, {})
		"ground":
			fx.ground_hit(hit, dir)
	fx.tracer(muzzle if muzzle != Vector3.INF else origin, hit)
	return {"kind": kind, "pos": hit, "collider": col}


func _hit_voxels(vh: Dictionary, dir: Vector3) -> void:
	var m: int = vh["mat"]
	var pos: Vector3 = vh["pos"]
	var c: Vector3i = vh["cell"]
	var ch: Dictionary
	if m == VoxelMat.GLASS:
		ch = VoxelCarver.shatter_glass(grid, grid.idx(c.x, c.y, c.z))
	else:
		var r := WALL_CARVE
		if c.y <= VoxelHouse.FLOOR_ROW:
			r = FLOOR_CARVE
		elif not VoxelMat.is_struct(m):
			r = FURNITURE_CARVE
		ch = VoxelCarver.carve_sphere(grid, pos + dir * 0.07, r, _shots * 7919 + c.x, dir, PENETRATION if r == WALL_CARVE else 1.0)
	_apply(ch)
	fx.impact(VoxelMat.IMPACT[m], pos, vh["normal"], dir, ch)


func _apply(ch: Dictionary) -> void:
	if (ch["cells"] as PackedInt32Array).is_empty():
		return
	chunks.apply_change(ch)
	if VoxelCarver.sync_nav(nav, grid, ch["lo"], ch["hi"]) > 0:
		structure_changed.emit()


# --- enemies ---------------------------------------------------------------------------

## An enemy swing at nav cell `target`: bites the voxels still blocking it.
func enemy_strike(attacker_pos: Vector3, target: Vector2) -> void:
	var h := _rng.randf_range(0.2, 1.5)
	var aim := target
	var to_t := target - Vector2(attacker_pos.x, attacker_pos.z)
	var along := Vector2(0, 1) if absf(to_t.x) > absf(to_t.y) else Vector2(1, 0)
	var blockers := _blockers(target, along)
	if not blockers.is_empty():
		var b: Vector3 = blockers[_rng.randi() % blockers.size()]
		h = clampf(b.y, 0.2, 1.55)
		aim = Vector2(b.x, b.z)
	var from := Vector3(attacker_pos.x, h, attacker_pos.z)
	var to := Vector3(aim.x + _rng.randf_range(-0.08, 0.08), h, aim.y + _rng.randf_range(-0.08, 0.08))
	var dir := (to - from).normalized()
	var vh := grid.raycast(from, dir, from.distance_to(to) + 0.4, _bullet_skip)
	var center := to
	var m := VoxelMat.DRYWALL
	var n := -dir
	if not vh.is_empty():
		center = (vh["pos"] as Vector3) + dir * 0.1
		m = vh["mat"]
		n = vh["normal"]
	var ch := VoxelCarver.carve_sphere(grid, center, BITE_RADIUS, _rng.randi())
	if (ch["cells"] as PackedInt32Array).is_empty():
		return
	_apply(ch)
	fx.impact(VoxelMat.IMPACT[m], center - dir * 0.1, n, dir, ch)


func _blockers(target: Vector2, along: Vector2) -> Array:
	var out := []
	var half := Vector2.ONE * GridNav.CELL * 0.5 + along * GridNav.CELL
	var xr := grid.centre_range(0, target.x - half.x, target.x + half.x)
	var zr := grid.centre_range(2, target.y - half.y, target.y + half.y)
	for y in range(VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI + 1):
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				if VoxelMat.is_struct(grid.get_mat(x, y, z)):
					out.append(grid.center(Vector3i(x, y, z)))
	return out


# --- queries ---------------------------------------------------------------------------

func interactables() -> Array:
	return [bed] if bed != null else []


func bed_position() -> Vector3:
	return bed.global_position if bed != null else Vector3(2.5, 0, 2.0)


func count_objects(_kind: String) -> int:
	return 0


func repair_all() -> void:
	var pristine := _pristine.copy()
	grid.mat = pristine.mat
	grid.col = pristine.col
	grid.pcol = pristine.pcol
	grid.pmask = pristine.pmask
	grid.solid_count = pristine.solid_count
	chunks.mark_dirty(Vector3i.ZERO, Vector3i(grid.sx, grid.sy, grid.sz))
	HousePlan.rasterize_into(nav)
	structure_changed.emit()


func damage_summary() -> Dictionary:
	return {"missing_voxels": _pristine.solid_count - grid.solid_count, "damaged_objects": 0}


func is_blocked(p: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var y := 1.0
	for seg in [[Vector3(p.x, y, p.y - 0.25), Vector3(p.x, y, p.y + 0.25)], [Vector3(p.x - 0.25, y, p.y), Vector3(p.x + 0.25, y, p.y)]]:
		for pair in [[seg[0], seg[1]], [seg[1], seg[0]]]:
			var q := PhysicsRayQueryParameters3D.create(pair[0], pair[1], 1 | 2 | 16)
			if not space.intersect_ray(q).is_empty():
				return true
	return false


func exit_path_exists() -> bool:
	return true
