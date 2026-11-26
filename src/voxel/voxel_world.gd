class_name VoxelWorld
extends Node3D
## Renders and collides a VoxelGrid in 16^3 chunks: one MeshInstance3D (opaque
## + glass surface) and one StaticBody3D (ConcavePolygonShape3D on layer
## "walls") per non-empty chunk. No node per voxel. After a change, collision
## of the touched chunks is rebuilt at once (same frame); their meshes are
## rebuilt within a per-frame time budget, normally the same frame too.

const CHUNK := Vector3i(16, 16, 16)
const WALL_LAYER := 2

var grid: VoxelGrid
var material: Material
var glass_material: Material
var collision_rows := Vector2i(VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI)
var visual_budget_ms := 6.0

var last_rebuild_ms := 0.0      ## last chunk mesh rebuild
var worst_rebuild_ms := 0.0
var last_collision_ms := 0.0    ## collision rebuild of the last change (all its chunks)
var last_change_chunks := 0
var last_change_mesh_ms := 0.0  ## mesh rebuild of the last change (all its chunks)
var rebuilds := 0
var mesh_ms_total := 0.0
var face_count := 0

var _chunks := {}               # Vector3i -> {"mesh": MeshInstance3D, "body": StaticBody3D, "shape": CollisionShape3D, "faces": int}
var _dirty := {}                # chunks waiting for a mesh rebuild


func setup(g: VoxelGrid, mat: Material, glass_mat: Material) -> void:
	grid = g
	material = mat
	glass_material = glass_mat


func chunk_count() -> int:
	var n := 0
	for k in _chunks:
		if _chunks[k]["faces"] > 0:
			n += 1
	return n


func build_all() -> void:
	for c in chunk_coords():
		build_chunk(c)


## Exp 009 (R): every chunk of the grid, in build_all's order (the loading
## screen builds them a few per frame with build_chunk).
func chunk_coords() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cz in range(0, grid.sz, CHUNK.z):
		for cy in range(0, grid.sy, CHUNK.y):
			for cx in range(0, grid.sx, CHUNK.x):
				out.append(Vector3i(cx / CHUNK.x, cy / CHUNK.y, cz / CHUNK.z))
	return out


## Exp 009 (R): one chunk's mesh and collision (build_all does every chunk).
func build_chunk(c: Vector3i) -> void:
	_rebuild_mesh(c)
	_rebuild_collision(c)


## Exp 009 (R): true while nothing is built yet (HouseWorld.defer_chunks).
func needs_build() -> bool:
	return grid != null and _chunks.is_empty()


## Cells in [lo, hi) changed: collision now, meshes soon.
func mark_dirty(lo: Vector3i, hi: Vector3i) -> void:
	if hi.x <= lo.x:
		return
	var c0 := Vector3i(maxi(lo.x, 0) / CHUNK.x, maxi(lo.y, 0) / CHUNK.y, maxi(lo.z, 0) / CHUNK.z)
	var c1 := Vector3i(maxi(hi.x - 1, 0) / CHUNK.x, maxi(hi.y - 1, 0) / CHUNK.y, maxi(hi.z - 1, 0) / CHUNK.z)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for cz in range(c0.z, c1.z + 1):
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var c := Vector3i(cx, cy, cz)
				_rebuild_collision(c)
				_dirty[c] = true
				n += 1
	last_collision_ms = (Time.get_ticks_usec() - t0) / 1000.0
	last_change_chunks = n
	last_change_mesh_ms = 0.0


## Cells in [lo, hi) changed colour only (no shape): meshes soon, collision untouched.
func mark_visual_dirty(lo: Vector3i, hi: Vector3i) -> void:
	if hi.x <= lo.x:
		return
	var c0 := Vector3i(maxi(lo.x, 0) / CHUNK.x, maxi(lo.y, 0) / CHUNK.y, maxi(lo.z, 0) / CHUNK.z)
	var c1 := Vector3i(maxi(hi.x - 1, 0) / CHUNK.x, maxi(hi.y - 1, 0) / CHUNK.y, maxi(hi.z - 1, 0) / CHUNK.z)
	for cz in range(c0.z, c1.z + 1):
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				_dirty[Vector3i(cx, cy, cz)] = true


func flush(budget_ms := -1.0) -> void:
	if _dirty.is_empty():
		return
	var budget := visual_budget_ms if budget_ms < 0.0 else budget_ms
	var t_start := Time.get_ticks_usec()
	for c in _dirty.keys():
		var t0 := Time.get_ticks_usec()
		_rebuild_mesh(c)
		_dirty.erase(c)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		last_rebuild_ms = ms
		last_change_mesh_ms += ms
		worst_rebuild_ms = maxf(worst_rebuild_ms, ms)
		mesh_ms_total += ms
		rebuilds += 1
		if (Time.get_ticks_usec() - t_start) / 1000.0 > budget:
			break


func _process(_delta: float) -> void:
	flush()


func _chunk_range(c: Vector3i) -> Array:
	var lo := Vector3i(c.x * CHUNK.x, c.y * CHUNK.y, c.z * CHUNK.z)
	return [lo, lo + CHUNK]


func _entry(c: Vector3i) -> Dictionary:
	if _chunks.has(c):
		return _chunks[c]
	var e := {"mesh": null, "body": null, "shape": null, "faces": 0}
	_chunks[c] = e
	return e


func _rebuild_mesh(c: Vector3i) -> void:
	var r := _chunk_range(c)
	var opaque := VoxelMesher.build_arrays(grid, r[0], r[1], false)
	var glass := VoxelMesher.build_arrays(grid, r[0], r[1], true)
	var e := _entry(c)
	face_count -= e["faces"]
	var faces := 0
	if opaque.is_empty() and glass.is_empty():
		if e["mesh"] != null:
			(e["mesh"] as MeshInstance3D).mesh = null
		e["faces"] = 0
		return
	var mesh := ArrayMesh.new()
	if not opaque.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, opaque)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		faces += (opaque[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	if not glass.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glass_material)
		faces += (glass[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	if e["mesh"] == null:
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_%d" % [c.x, c.y, c.z]
		add_child(mi)
		e["mesh"] = mi
	(e["mesh"] as MeshInstance3D).mesh = mesh
	e["faces"] = faces
	face_count += faces


func _rebuild_collision(c: Vector3i) -> void:
	var r := _chunk_range(c)
	var faces := VoxelMesher.collision_faces(grid, r[0], r[1], collision_rows.x, collision_rows.y)
	var e := _entry(c)
	if faces.is_empty():
		if e["shape"] != null:
			(e["shape"] as CollisionShape3D).disabled = true
		return
	if e["body"] == null:
		var body := StaticBody3D.new()
		body.name = "ChunkBody_%d_%d_%d" % [c.x, c.y, c.z]
		body.collision_layer = 1 << (WALL_LAYER - 1)
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		add_child(body)
		e["body"] = body
		e["shape"] = cs
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var csn: CollisionShape3D = e["shape"]
	csn.shape = shape
	csn.disabled = false


## Applies a VoxelCarver change: dirties chunks (with an AO margin).
func apply_change(ch: Dictionary) -> void:
	if (ch["cells"] as PackedInt32Array).is_empty():
		return
	mark_dirty(ch["lo"], ch["hi"])
