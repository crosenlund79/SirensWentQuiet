class_name ModFloorKit
extends RefCounted
## Kit piece: 1 m x 1 m floor tile module, one finish per room (HousePlan
## "floor"). All tiles of one finish are drawn with a single MultiMesh, and
## the finish texture is world-aligned so tiles join seamlessly.

const M := preload("res://src/modular/kit/mod_materials.gd")
const TILE_TOP := 0.025

static var _tiles := {}


## Tile mesh for a finish layer: top face plus small bevelled sides.
static func tile_mesh(layer: int) -> ArrayMesh:
	if _tiles.has(layer):
		return _tiles[layer]
	var mm := ModMesh.new()
	mm.set_mat(layer)
	var b := 0.004
	mm.quad(Vector3(b, TILE_TOP, b), Vector3(1 - b, TILE_TOP, b), Vector3(1 - b, TILE_TOP, 1 - b), Vector3(b, TILE_TOP, 1 - b), Vector3.UP)
	mm.set_mat(layer, Color(0.8, 0.8, 0.8))
	mm.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1 - b, TILE_TOP, b), Vector3(b, TILE_TOP, b), Vector3(0, 1, -1).normalized())
	mm.quad(Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(b, TILE_TOP, 1 - b), Vector3(1 - b, TILE_TOP, 1 - b), Vector3(0, 1, 1).normalized())
	mm.quad(Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(b, TILE_TOP, b), Vector3(b, TILE_TOP, 1 - b), Vector3(-1, 1, 0).normalized())
	mm.quad(Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1 - b, TILE_TOP, 1 - b), Vector3(1 - b, TILE_TOP, b), Vector3(1, 1, 0).normalized())
	var mesh := mm.commit()
	_tiles[layer] = mesh
	return mesh


## One MultiMeshInstance3D per finish, covering every room rect on the 1 m grid.
static func build(parent: Node3D) -> int:
	var by_layer := {}
	for r in HousePlan.ROOMS:
		var layer: int = M.FLOOR_LAYERS.get(r["floor"], M.L_FLOOR_WOOD)
		var rect: Rect2 = r["rect"]
		if not by_layer.has(layer):
			by_layer[layer] = []
		for j in range(int(rect.position.y), int(rect.end.y)):
			for i in range(int(rect.position.x), int(rect.end.x)):
				by_layer[layer].append(Vector3(i, 0, j))
	var count := 0
	for layer in by_layer:
		var cells: Array = by_layer[layer]
		var mmesh := MultiMesh.new()
		mmesh.transform_format = MultiMesh.TRANSFORM_3D
		mmesh.mesh = tile_mesh(layer)
		mmesh.instance_count = cells.size()
		for k in cells.size():
			mmesh.set_instance_transform(k, Transform3D(Basis.IDENTITY, cells[k]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FloorTiles_%d" % layer
		mmi.multimesh = mmesh
		mmi.material_override = M.kit()
		parent.add_child(mmi)
		count += cells.size()
	# foundation slab under the whole footprint (visible where walls are breached)
	var fp := HousePlan.FOOTPRINT.grow(HousePlan.EXTERIOR_THICKNESS * 0.5 + 0.06)
	var mm := ModMesh.new()
	mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.78, 0.77, 0.74))
	mm.box(Vector3(fp.position.x, -0.05, fp.position.y), Vector3(fp.end.x, 0.018, fp.end.y), ["-y"])
	var slab := MeshInstance3D.new()
	slab.name = "Foundation"
	slab.mesh = mm.commit()
	slab.material_override = M.kit()
	parent.add_child(slab)
	return count
