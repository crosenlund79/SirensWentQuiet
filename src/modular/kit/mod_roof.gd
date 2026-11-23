class_name ModRoof
extends Node3D
## Kit pieces: 1 m standing-seam roof panels (one MultiMesh per slope), a
## ridge cap and two siding gables. Shallow gable roof, ridge along x.
## The whole roof fades out (dithered) while the player is inside or behind it.

const M := preload("res://src/modular/kit/mod_materials.gd")
const PITCH := deg_to_rad(22.0)
const EAVE := 0.45          ## overhang north/south (m)
const RAKE := 0.5           ## overhang east/west (m)
const THICK := 0.14

var fade := 0.0
var fade_target := 0.0
var _parts: Array[GeometryInstance3D] = []

var ridge_z := HousePlan.FOOTPRINT.position.y + HousePlan.FOOTPRINT.size.y * 0.5
var x0 := HousePlan.FOOTPRINT.position.x - RAKE
var x1 := HousePlan.FOOTPRINT.end.x + RAKE


func _ready() -> void:
	var fp := HousePlan.FOOTPRINT
	var panels := int(round(x1 - x0))
	for slope in [-1.0, 1.0]:
		var mmesh := MultiMesh.new()
		mmesh.transform_format = MultiMesh.TRANSFORM_3D
		mmesh.mesh = _panel_mesh(slope)
		mmesh.instance_count = panels
		for i in panels:
			mmesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x0 + i, 0, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "RoofPanels_%s" % ("north" if slope < 0.0 else "south")
		mmi.multimesh = mmesh
		_add(mmi)
	# ridge cap and gables
	var mm := ModMesh.new()
	var ry := _under(ridge_z) + THICK
	mm.set_mat(M.L_METAL, Color(0.2, 0.21, 0.22))
	mm.box(Vector3(x0 - 0.02, ry - 0.02, ridge_z - 0.16), Vector3(x1 + 0.02, ry + 0.06, ridge_z + 0.16))
	for gx in [fp.position.x, fp.end.x]:
		var out := -1.0 if gx == fp.position.x else 1.0
		var t := HousePlan.EXTERIOR_THICKNESS * 0.5
		var base := HousePlan.WALL_HEIGHT
		var top := _under(ridge_z)
		for side in [-1.0, 1.0]:
			var x: float = gx + side * t
			mm.set_mat(M.L_SIDING if side == out else M.L_PLAIN, Color.WHITE if side == out else Color(0.5, 0.48, 0.45))
			mm.tri(Vector3(x, base, fp.position.y), Vector3(x, base, fp.end.y), Vector3(x, top, ridge_z), Vector3(side, 0, 0))
		# round attic vent on the outside face
		mm.set_mat(M.L_TRIM, M.FRAME_COLOR)
		var vx: float = gx + out * (t + 0.01)
		var vc := Vector3(vx, base + (top - base) * 0.45, ridge_z)
		var pts := PackedVector3Array()
		for k in 10:
			var a := TAU * k / 10.0
			pts.append(vc + Vector3(0, sin(a) * 0.22, cos(a) * 0.22))
		mm.poly(pts, Vector3(out, 0, 0))
	var mi := MeshInstance3D.new()
	mi.name = "RidgeAndGables"
	mi.mesh = mm.commit()
	_add(mi)


func _add(g: GeometryInstance3D) -> void:
	g.material_override = M.kit()
	add_child(g)
	_parts.append(g)


## Underside height of the roof at plan y = z.
func _under(z: float) -> float:
	var fp := HousePlan.FOOTPRINT
	var d := minf(z - fp.position.y, fp.end.y - z)
	return HousePlan.WALL_HEIGHT + d * tan(PITCH)


## One 1 m panel from eave to ridge (x 0..1), on the given slope.
func _panel_mesh(slope: float) -> ArrayMesh:
	var fp := HousePlan.FOOTPRINT
	var z_eave := fp.position.y - EAVE if slope < 0.0 else fp.end.y + EAVE
	var z_r := ridge_z
	var mm := ModMesh.new()
	var ye := _under(z_eave)
	var yr := _under(z_r)
	var n_top := Vector3(0, cos(PITCH), slope * sin(PITCH))
	mm.set_mat(M.L_ROOF)
	mm.quad(Vector3(0, ye + THICK, z_eave), Vector3(1, ye + THICK, z_eave), Vector3(1, yr + THICK, z_r), Vector3(0, yr + THICK, z_r), n_top)
	# raised seam at the panel edge
	mm.set_mat(M.L_METAL, Color(0.36, 0.38, 0.4))
	var s0 := Vector3(0.0, ye + THICK, z_eave)
	var s1 := Vector3(0.0, yr + THICK, z_r)
	mm.quad(s0 + Vector3(-0.012, 0, 0), s1 + Vector3(-0.012, 0, 0), s1 + Vector3(-0.012, 0.035, 0), s0 + Vector3(-0.012, 0.035, 0), Vector3.LEFT)
	mm.quad(s0 + Vector3(0.012, 0, 0), s0 + Vector3(0.012, 0.035, 0), s1 + Vector3(0.012, 0.035, 0), s1 + Vector3(0.012, 0, 0), Vector3.RIGHT)
	mm.quad(s0 + Vector3(-0.012, 0.035, 0), s1 + Vector3(-0.012, 0.035, 0), s1 + Vector3(0.012, 0.035, 0), s0 + Vector3(0.012, 0.035, 0), n_top)
	# soffit (underside) and fascia board
	mm.set_mat(M.L_PLAIN, Color(0.62, 0.62, 0.6))
	mm.quad(Vector3(0, ye, z_eave), Vector3(1, ye, z_eave), Vector3(1, yr, z_r), Vector3(0, yr, z_r), -n_top)
	mm.set_mat(M.L_TRIM, M.FRAME_COLOR)
	mm.quad(Vector3(0, ye - 0.03, z_eave), Vector3(1, ye - 0.03, z_eave), Vector3(1, ye + THICK + 0.01, z_eave), Vector3(0, ye + THICK + 0.01, z_eave), Vector3(0, 0, slope))
	# rake edges (only visible on the end panels, cheap enough to keep)
	for x in [0.0, 1.0]:
		var nx := -1.0 if x == 0.0 else 1.0
		mm.quad(Vector3(x, ye, z_eave), Vector3(x, yr, z_r), Vector3(x, yr + THICK, z_r), Vector3(x, ye + THICK, z_eave), Vector3(nx, 0, 0))
	return mm.commit()


func set_fade(f: float) -> void:
	fade = f
	for g in _parts:
		g.set_instance_shader_parameter("fade", f)
	visible = f < 0.999
