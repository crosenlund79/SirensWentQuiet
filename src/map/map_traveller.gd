class_name MapTraveller
extends Node3D
## Exp 007 (T): the tiny voxel Eli (or the yard car) that travels along the
## road route on the region map (RegionMapScreen.play_travel). A few boxes,
## unshaded enough to read at night; it faces along the road and bobs while
## walking. `follow(points, t)` places it at fraction t of the route.
## Sizes are in map units (1 unit = one 25 m cell): exaggerated so the figure
## reads from the travel camera.

const BODY := Color(0.14, 0.2, 0.32)        ## Eli's jacket (dark, to read on snow)
const LEGS := Color(0.08, 0.08, 0.1)
const SKIN := Color(0.86, 0.66, 0.5)
const PACK := Color(0.95, 0.62, 0.22)       ## the amber pack (UiTheme.ACCENT)
const CAR_BODY := Color(0.58, 0.14, 0.1)
const CAR_GLASS := Color(0.2, 0.28, 0.36)
const LAMP := Color(1.0, 0.92, 0.7)
const SCALE := 2.0                          ## a map token, not to scale
## Exp 012 (L, §21): the car is a small, battered vintage off-road 4x4 at
## about half the old token's size (the old one dwarfed the houses).
const CAR_SCALE := 1.0
const OLIVE := Color(0.36, 0.4, 0.29)       ## faded army-surplus paint
const OLIVE_DARK := Color(0.27, 0.3, 0.22)
const PANEL := Color(0.62, 0.58, 0.47)      ## a mismatched replacement door
const RUST := Color(0.5, 0.3, 0.18)
const RUBBER := Color(0.08, 0.08, 0.09)
const STEEL := Color(0.22, 0.23, 0.25)
const CAN := Color(0.55, 0.16, 0.12)

var car := false
var _rig: Node3D
var _t := 0.0
var _lengths := PackedFloat32Array()
var _total := 0.0


func setup(by_car: bool) -> void:
	car = by_car
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.scale = Vector3.ONE * SCALE
	add_child(_rig)
	if car:
		_rig.scale = Vector3.ONE * CAR_SCALE
		_build_4x4()
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
	l.position = Vector3(0, 1.4 * SCALE, 0)
	add_child(l)


## Exp 012 (L, §21): the 4x4 in boxes (front is -z): a raised body on four
## chunky tyres, a boxy cab set back with dark glass, a bull bar, a spare
## wheel on the tailgate, a roof rack with a jerrycan, rust patches and a
## mismatched door; a soft dark ground disc keeps it seated on the map.
func _build_4x4() -> void:
	_box(Vector3(0.8, 0.3, 1.5), Vector3(0, 0.4, 0), OLIVE)                 # body
	_box(Vector3(0.74, 0.12, 0.62), Vector3(0, 0.6, -0.42), OLIVE_DARK)     # bonnet
	_box(Vector3(0.76, 0.32, 0.86), Vector3(0, 0.71, 0.22), OLIVE)          # cab
	_box(Vector3(0.7, 0.2, 0.05), Vector3(0, 0.74, -0.22), CAR_GLASS)       # windscreen
	for x in [-0.385, 0.385]:
		_box(Vector3(0.02, 0.18, 0.7), Vector3(x, 0.75, 0.22), CAR_GLASS)   # side windows
	_box(Vector3(0.02, 0.24, 0.42), Vector3(0.405, 0.42, -0.05), PANEL)     # the odd door
	_box(Vector3(0.02, 0.1, 0.22), Vector3(-0.405, 0.32, 0.45), RUST)       # rust
	_box(Vector3(0.18, 0.02, 0.14), Vector3(-0.18, 0.67, -0.55), RUST)
	_box(Vector3(0.84, 0.06, 0.06), Vector3(0, 0.3, -0.8), STEEL)           # bull bar
	for x in [-0.28, 0.28]:
		_box(Vector3(0.06, 0.26, 0.06), Vector3(x, 0.4, -0.8), STEEL)
	for x in [-0.26, 0.26]:
		_box(Vector3(0.14, 0.1, 0.04), Vector3(x, 0.48, -0.77), LAMP, true)  # headlamps
	_box(Vector3(0.36, 0.36, 0.12), Vector3(0, 0.46, 0.81), RUBBER)         # spare wheel
	_box(Vector3(0.7, 0.04, 0.8), Vector3(0, 0.9, 0.22), STEEL)             # roof rack
	_box(Vector3(0.22, 0.14, 0.3), Vector3(0.18, 0.99, 0.32), CAN)          # jerrycan
	_box(Vector3(0.24, 0.08, 0.26), Vector3(-0.16, 0.96, 0.08), Color(0.4, 0.34, 0.24))   # a tarp bundle
	for x in [-0.4, 0.4]:
		for z in [-0.48, 0.5]:
			_box(Vector3(0.16, 0.34, 0.34), Vector3(x, 0.17, z), RUBBER)    # chunky tyres
			_box(Vector3(0.17, 0.12, 0.12), Vector3(x, 0.17, z), STEEL)     # hubs
	var disc := MeshInstance3D.new()
	disc.name = "Ground"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.05
	cyl.height = 0.02
	cyl.radial_segments = 28
	disc.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.02, 0.03, 0.04, 0.32)
	disc.material_override = m
	disc.position = Vector3(0, 0.02, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(disc)


func _box(size: Vector3, at: Vector3, col: Color, glow := false) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.5
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
		_rig.position.y = absf(sin(_t * 240.0)) * 0.12 * SCALE
