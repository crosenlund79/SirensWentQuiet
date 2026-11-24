extends Node3D
## Experiment 004 (owner L): the look of one stairs piece (Levels stairs
## record): Levels.STEPS solid wooden steps over its two cells, rising from
## the ground floor to the upper floor ("up") or descending into the basement
## ("down"), with a stringer on each side. Visual only: bodies change storey
## through GameLevels, so the steps have no collision. Stairs down also get
## a dark "Pit" over their hole, seen from the ground floor (the yard's ground
## plane, just under the floor, would otherwise show through the hole).

const TREAD := 0x7b5d40
const RISER := 0x5f4630
const STRINGER := 0x4e3a28
const PIT := 0x0d0b0a

var stairs: Dictionary


static func make(st: Dictionary) -> Node3D:
	var n: Node3D = load("res://src/levels/stairs_view.gd").new()
	n.stairs = st
	n.name = "Stairs_%d_%d_%d" % [(st["cell"] as Vector2i).x, (st["cell"] as Vector2i).y, int(st["lo"])]
	n._build()
	return n


func _build() -> void:
	var d := Vector2(Levels.stairs_dir(stairs))
	var start := Levels.cell_center(stairs["cell"]) - d * 0.5
	var up: bool = int(stairs["lo"]) == Levels.GROUND
	var depth := 2.0 / float(Levels.STEPS)
	var along_x := absf(d.x) > 0.5
	var tread := _mat(TREAD)
	var riser := _mat(RISER)
	for k in Levels.STEPS:
		var top := Levels.step_height(stairs, k)
		var lo := 0.0 if up else -Levels.HEIGHT
		var h := top - lo
		if h < 0.02:
			continue
		var c := start + d * (float(k) + 0.5) * depth
		var size := Vector3(depth, h, 0.92) if along_x else Vector3(0.92, h, depth)
		_box(size, Vector3(c.x, lo + h * 0.5, c.y), riser if k % 2 == 0 else tread)
		_box(Vector3(size.x, 0.04, size.z), Vector3(c.x, top - 0.02, c.y), tread)
	# side stringers: thin slanted boards approximated by a stepped edge
	for side: float in [-1.0, 1.0]:
		var off: Vector2 = Vector2(-d.y, d.x) * 0.48 * side
		for k in Levels.STEPS:
			var top := Levels.step_height(stairs, k) + (0.12 if up else 0.0)
			var lo := top - 0.32
			var c := start + d * (float(k) + 0.5) * depth + off
			var size := Vector3(depth, 0.32, 0.05) if along_x else Vector3(0.05, 0.32, depth)
			_box(size, Vector3(c.x, (lo + top) * 0.5, c.y), _mat(STRINGER))


	if not up:
		var pit := _box(Vector3(0.98 if not along_x else 1.98, 0.01, 1.98 if not along_x else 0.98),
			Vector3(start.x + d.x, -0.012, start.y + d.y), _mat(PIT))
		pit.name = "Pit"
		pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)
	return mi


static var _mats := {}


static func _mat(c: int) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = VoxelArt.to_color(c)
		m.roughness = 0.92
		_mats[c] = m
	return _mats[c]
