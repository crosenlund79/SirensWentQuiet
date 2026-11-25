class_name MapTraveller
extends Node3D
## Exp 007 (T): the tiny voxel Eli (or the yard car) that travels along the
## road route on the region map (RegionMapScreen.play_travel). A few boxes,
## unshaded enough to read at night; it faces along the road and bobs while
## walking. `follow(points, t)` places it at fraction t of the route.
## Sizes are in map units (1 unit = one 25 m cell): exaggerated so the figure
## reads from the travel camera.

const BODY := Color(0.36, 0.44, 0.52)       ## Eli's jacket
const LEGS := Color(0.22, 0.22, 0.26)
const SKIN := Color(0.86, 0.72, 0.6)
const PACK := Color(0.45, 0.36, 0.24)
const CAR_BODY := Color(0.62, 0.22, 0.18)
const CAR_GLASS := Color(0.55, 0.68, 0.78)
const LAMP := Color(1.0, 0.92, 0.7)

var car := false
var _rig: Node3D
var _t := 0.0
var _lengths := PackedFloat32Array()
var _total := 0.0


func setup(by_car: bool) -> void:
	car = by_car
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	if car:
		_box(Vector3(0.9, 0.35, 1.7), Vector3(0, 0.3, 0), CAR_BODY)
		_box(Vector3(0.8, 0.3, 0.9), Vector3(0, 0.62, 0.1), CAR_GLASS)
		for x in [-0.3, 0.3]:
			_box(Vector3(0.16, 0.12, 0.06), Vector3(x, 0.34, -0.86), LAMP, true)
		for x in [-0.42, 0.42]:
			for z in [-0.55, 0.55]:
				_box(Vector3(0.12, 0.26, 0.3), Vector3(x, 0.13, z), LEGS)
	else:
		for x in [-0.12, 0.12]:
			_box(Vector3(0.16, 0.5, 0.18), Vector3(x, 0.25, 0), LEGS)
		_box(Vector3(0.46, 0.55, 0.28), Vector3(0, 0.77, 0), BODY)
		_box(Vector3(0.34, 0.4, 0.16), Vector3(0, 0.8, 0.2), PACK)
		_box(Vector3(0.3, 0.3, 0.3), Vector3(0, 1.2, 0), SKIN)
	# a soft glow so the figure reads on the night map
	var l := OmniLight3D.new()
	l.light_color = LAMP
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.position = Vector3(0, 1.4, 0)
	add_child(l)


func _box(size: Vector3, at: Vector3, col: Color, glow := false) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.2 if glow else 0.25
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(mi)


## Places the figure at fraction `t` (0..1) of the polyline `pts` (map world
## points), facing along it.
func follow(pts: PackedVector3Array, t: float) -> void:
	if pts.size() == 0:
		return
	if pts.size() == 1:
		position = pts[0]
		return
	if _lengths.size() != pts.size():
		_measure(pts)
	var want := clampf(t, 0.0, 1.0) * _total
	var i := 1
	while i < pts.size() - 1 and _lengths[i] < want:
		i += 1
	var seg := maxf(_lengths[i] - _lengths[i - 1], 0.0001)
	var k := clampf((want - _lengths[i - 1]) / seg, 0.0, 1.0)
	var a: Vector3 = pts[i - 1]
	var b: Vector3 = pts[i]
	position = a.lerp(b, k)
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() > 0.001:
		rotation.y = atan2(-d.x, -d.z)
	_t = t


func _measure(pts: PackedVector3Array) -> void:
	_lengths.resize(pts.size())
	_lengths[0] = 0.0
	for i in range(1, pts.size()):
		_lengths[i] = _lengths[i - 1] + pts[i - 1].distance_to(pts[i])
	_total = _lengths[pts.size() - 1]


func _process(_delta: float) -> void:
	if _rig != null and not car:
		_rig.position.y = absf(sin(_t * 240.0)) * 0.12
