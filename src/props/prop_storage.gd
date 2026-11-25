extends RefCounted
## Experiment 005 (F): meshes for the new furniture types and the loot pile,
## kept simple. Builder frame as in prop_furniture.gd: footprint centred,
## width w along x, depth d along z, FRONT toward +z, floor at y = 0.
##   cupboard       a kitchen base cabinet: two doors, a worktop, a kick plinth
##   storage_chest  a plank chest with iron bands and a hasp
##   tool_cabinet   a tall steel cabinet, louvres and a padlock
##   painting       a framed landscape on a thin backing (hangs on a wall)
##   loot_pile      a low heap: a split box, cans, a plank and a rag

const M := preload("res://src/props/prop_materials.gd")

const OAK := Color(0.74, 0.6, 0.44)
const OAK_DARK := Color(0.6, 0.47, 0.33)
const SAGE := Color(0.47, 0.53, 0.46)
const WORKTOP := Color(0.74, 0.62, 0.45)
const IRON := Color(0.33, 0.33, 0.34)
const STEEL_RED := Color(0.55, 0.22, 0.18)
const STEEL := Color(0.64, 0.65, 0.64)
const BLACK := Color(0.13, 0.13, 0.14)
const CARDBOARD := Color(0.64, 0.51, 0.35)


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> bool:
	match type:
		"cupboard":
			_cupboard(mm, w, d, h)
		"storage_chest":
			_chest(mm, w, d, h, rng)
		"tool_cabinet":
			_tool_cabinet(mm, w, d, h)
		"painting":
			_painting(mm, w, d, h, rng)
		"loot_pile":
			_pile(mm, w, d, h, rng)
		_:
			return false
	return true


static func _cupboard(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.2))
	mm.box(Vector3(-x + 0.03, 0, -z), Vector3(x - 0.03, 0.08, z - 0.05))
	mm.set_mat(M.L_PLAIN, SAGE, 0.06)
	mm.chamfer_box(Vector3(-x, 0.08, -z), Vector3(x, h - 0.04, z - 0.02), 0.01)
	mm.set_mat(M.L_WOOD, WORKTOP)
	mm.box(Vector3(-x - 0.01, h - 0.04, -z), Vector3(x + 0.01, h, z + 0.02))
	# two doors with a gap between and a handle each
	mm.set_mat(M.L_SCREEN, Color(0.05, 0.05, 0.05))
	mm.box(Vector3(-0.004, 0.1, z - 0.02), Vector3(0.004, h - 0.07, z - 0.016))
	mm.set_mat(M.L_METAL, STEEL, 0.1)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * 0.06 - 0.008, h - 0.3, z - 0.02), Vector3(sx * 0.06 + 0.008, h - 0.14, z + 0.01))


static func _chest(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var lid := h * 0.28
	# planked body: a few horizontal boards in slightly different tones
	var rows := 3
	for k in rows:
		var y0 := (h - lid) * k / rows
		var y1 := (h - lid) * (k + 1) / rows
		mm.set_mat(M.L_ROUGH_WOOD, OAK.darkened(rng.randf_range(0.0, 0.18)), 0.2)
		mm.box(Vector3(-x, y0, -z), Vector3(x, y1 - 0.004, z))
	mm.set_mat(M.L_ROUGH_WOOD, OAK_DARK, 0.2)
	mm.chamfer_box(Vector3(-x - 0.01, h - lid, -z - 0.01), Vector3(x + 0.01, h, z + 0.01), 0.03, false)
	# iron bands and the hasp
	mm.set_mat(M.L_METAL, IRON, 0.25)
	for sx in [-0.7, 0.7]:
		mm.box(Vector3(sx * x - 0.025, 0.0, -z - 0.012), Vector3(sx * x + 0.025, h + 0.004, z + 0.012))
	mm.box(Vector3(-0.04, h - lid - 0.08, z + 0.01), Vector3(0.04, h - lid + 0.04, z + 0.025))


static func _tool_cabinet(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, STEEL_RED, 0.15)
	mm.chamfer_box(Vector3(-x, 0.0, -z), Vector3(x, h, z), 0.012)
	mm.set_mat(M.L_SCREEN, Color(0.06, 0.06, 0.06))
	mm.box(Vector3(-0.004, 0.04, z), Vector3(0.004, h - 0.04, z + 0.004))
	# louvres near the top of each door
	mm.set_mat(M.L_METAL, STEEL_RED.darkened(0.3), 0.1)
	for sx in [-1.0, 1.0]:
		for k in 4:
			var y := h - 0.18 - k * 0.04
			mm.box(Vector3(sx * x * 0.5 - x * 0.3, y, z), Vector3(sx * x * 0.5 + x * 0.3, y + 0.012, z + 0.008))
	# the handle and a padlock
	mm.set_mat(M.L_METAL, STEEL, 0.1)
	mm.box(Vector3(0.02, h * 0.45, z), Vector3(0.035, h * 0.6, z + 0.03))
	mm.set_mat(M.L_METAL, Color(0.72, 0.6, 0.3), 0.1)
	mm.box(Vector3(-0.03, h * 0.47, z + 0.01), Vector3(0.005, h * 0.53, z + 0.035))


static func _painting(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var f := 0.045
	mm.set_mat(M.L_WOOD, Color(0.42, 0.3, 0.21), 0.1)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h, z))
	# canvas: sky, a hill, a band of dark pines and a pale lake
	var sky := Color(0.62, 0.68, 0.7).lerp(Color(0.8, 0.62, 0.48), rng.randf() * 0.5)
	mm.set_mat(M.L_PLAIN, sky, 0.05)
	mm.box(Vector3(-x + f, h * 0.45, z), Vector3(x - f, h - f, z + 0.004))
	mm.set_mat(M.L_PLAIN, Color(0.36, 0.42, 0.34), 0.05)
	mm.box(Vector3(-x + f, h * 0.3, z), Vector3(x - f, h * 0.45, z + 0.005))
	mm.set_mat(M.L_PLAIN, Color(0.17, 0.24, 0.2), 0.05)
	for k in 7:
		var cx := -x + f + (w - 2.0 * f) * (k + 0.5) / 7.0
		var th := h * rng.randf_range(0.12, 0.22)
		mm.box(Vector3(cx - 0.02, h * 0.42, z + 0.005), Vector3(cx + 0.02, h * 0.42 + th, z + 0.007))
	mm.set_mat(M.L_PLAIN, Color(0.55, 0.62, 0.66), 0.05)
	mm.box(Vector3(-x + f, f, z), Vector3(x - f, h * 0.3, z + 0.004))


static func _pile(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# a split cardboard box on its side
	mm.set_mat(M.L_PLAIN, CARDBOARD.darkened(rng.randf_range(0.0, 0.15)), 0.35)
	mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), Vector3(-w * 0.15, h * 0.35, -d * 0.1)), Vector3(w * 0.45, h * 0.7, d * 0.4))
	# a plank across, cans and a rag
	mm.set_mat(M.L_ROUGH_WOOD, OAK.darkened(0.1), 0.3)
	mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(0.3, 1.2)) * Basis(Vector3.FORWARD, 0.12), Vector3(w * 0.05, h * 0.2, d * 0.15)), Vector3(w * 0.7, 0.04, 0.12))
	for k in 3:
		mm.set_mat(M.L_METAL, [Color(0.7, 0.3, 0.22), Color(0.55, 0.6, 0.62), Color(0.75, 0.65, 0.35)][k], 0.3)
		mm.cylinder(Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.0, rng.randf_range(0.0, d * 0.4)), 0.04, 0.04, 0.11, 8)
	mm.set_mat(M.L_FABRIC, Color(0.45, 0.48, 0.55), 0.3)
	mm.blob(Vector3(w * 0.25, 0.03, -d * 0.25), Vector3(0.16, 0.04, 0.12), 2, 6)
	mm.set_mat(M.L_PLAIN, BLACK, 0.2)
	mm.box(Vector3(-w * 0.45, 0.0, d * 0.2), Vector3(-w * 0.25, 0.05, d * 0.38))
