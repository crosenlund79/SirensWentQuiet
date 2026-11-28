class_name VoxelFx
extends Node3D
## Destruction and weapon effects for Version A, all pooled in three
## MultiMeshes (debris cubes, dust puffs, sparks) plus a few tracer meshes:
## no physics bodies. Debris is simulated here against the voxel grid itself,
## so chips bounce off walls and settle on floors as small rubble piles.
## The pools are ring buffers (MAX_DEBRIS etc.): the oldest chip is reused,
## so active debris never accumulates; settled chips stay static (no
## transform updates) until they shrink away after REST_TIME.

const MAX_DEBRIS := 700
const MAX_PUFFS := 160
const MAX_SPARKS := 140
const GRAVITY := 9.8
const GROUND_Y := -0.03
const REST_TIME := 7.0

var grid: VoxelGrid
var debris_count := 0
## Size of wall chips relative to one voxel (the survival world's 0.2 m damage uses bigger chips).
var debris_scale := 1.0

# debris pool
var _d_mm: MultiMesh
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_axis := PackedVector3Array()
var _d_scale := PackedVector3Array()
var _d_ang := PackedFloat32Array()
var _d_spin := PackedFloat32Array()
var _d_life := PackedFloat32Array()
var _d_rest := PackedByteArray()
var _d_next := 0
var _d_active := 0
# puffs
var _p_mm: MultiMesh
var _p_pos := PackedVector3Array()
var _p_vel := PackedVector3Array()
var _p_col := PackedColorArray()
var _p_size := PackedFloat32Array()
var _p_grow := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_ttl := PackedFloat32Array()
var _p_next := 0
var _p_active := 0
# sparks
var _s_mm: MultiMesh
var _s_pos := PackedVector3Array()
var _s_vel := PackedVector3Array()
var _s_life := PackedFloat32Array()
var _s_next := 0
var _s_active := 0
# tracers and muzzle flash
var _tracers: Array[MeshInstance3D] = []
var _tracer_t: Array[float] = []
var _tracer_next := 0
var _flash: MeshInstance3D
var _flash_t := 0.0
# blast (Experiment 003): a light flash and a fireball, created on first use
var _blast_light: OmniLight3D
var _fireball: MeshInstance3D
var _blast_t := 0.0
var _blast_r := 1.0
var _rng := RandomNumberGenerator.new()
var _zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0))


func _ready() -> void:
	_rng.seed = 7
	# Debris: lit vertex-coloured cubes.
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.vertex_color_is_srgb = true
	dm.roughness = 0.85
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.1
	box.material = dm
	_d_mm = _multimesh(box, MAX_DEBRIS, true)
	for arr in [_d_pos, _d_vel, _d_axis, _d_scale]:
		arr.resize(MAX_DEBRIS)
	for arr in [_d_ang, _d_spin, _d_life]:
		arr.resize(MAX_DEBRIS)
	_d_rest.resize(MAX_DEBRIS)
	# Puffs: soft lit billboards.
	var pm := ShaderMaterial.new()
	pm.shader = load("res://src/voxel/shaders/voxel_puff.gdshader")
	pm.set_shader_parameter("tex", AssetResolver.get_texture("voxel/dust", true))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = pm
	_p_mm = _multimesh(quad, MAX_PUFFS, true)
	for arr in [_p_pos, _p_vel]:
		arr.resize(MAX_PUFFS)
	_p_col.resize(MAX_PUFFS)
	for arr in [_p_size, _p_grow, _p_life, _p_ttl]:
		arr.resize(MAX_PUFFS)
	# Sparks: additive streaks.
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.75, 0.35)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.7, 0.3)
	sm.emission_energy_multiplier = 4.0
	var spark := BoxMesh.new()
	spark.size = Vector3(0.025, 0.025, 1.0)
	spark.material = sm
	_s_mm = _multimesh(spark, MAX_SPARKS, false)
	for arr in [_s_pos, _s_vel]:
		arr.resize(MAX_SPARKS)
	_s_life.resize(MAX_SPARKS)
	# Tracers.
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 6:
		var t := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.03, 0.03, 1.0)
		t.mesh = tb
		t.material_override = tm.duplicate()
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
		_tracers.append(t)
		_tracer_t.append(0.0)
	# Muzzle flash: a small additive star billboard.
	_flash = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.55, 0.55)
	_flash.mesh = fq
	var fm := ShaderMaterial.new()
	fm.shader = load("res://src/voxel/shaders/voxel_flash.gdshader")
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)


func _multimesh(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, _zero)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mesh is BoxMesh and colors else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(100, 30, 100))
	add_child(mmi)
	return mm


# --- spawning ----------------------------------------------------------------------

func debris(pos: Vector3, vel: Vector3, color: Color, size := 1.0, shape := Vector3.ONE) -> void:
	var i := _d_next
	_d_next = (_d_next + 1) % MAX_DEBRIS
	if _d_life[i] <= 0.0:
		_d_active += 1
	_d_pos[i] = pos
	_d_vel[i] = vel
	_d_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	_d_ang[i] = _rng.randf() * TAU
	_d_spin[i] = _rng.randf_range(4.0, 16.0)
	_d_scale[i] = shape * size
	_d_life[i] = REST_TIME + _rng.randf() * 4.0
	_d_rest[i] = 0
	_d_mm.set_instance_color(i, color)


func puff(pos: Vector3, vel: Vector3, color: Color, size: float, grow: float, ttl: float) -> void:
	var i := _p_next
	_p_next = (_p_next + 1) % MAX_PUFFS
	if _p_life[i] <= 0.0:
		_p_active += 1
	_p_pos[i] = pos
	_p_vel[i] = vel
	_p_col[i] = color
	_p_size[i] = size
	_p_grow[i] = grow
	_p_life[i] = ttl
	_p_ttl[i] = ttl


func sparks(pos: Vector3, normal: Vector3, count: int, speed := 6.0) -> void:
	for k in count:
		var i := _s_next
		_s_next = (_s_next + 1) % MAX_SPARKS
		if _s_life[i] <= 0.0:
			_s_active += 1
		var v := (normal + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.3, 0.9), _rng.randf_range(-0.8, 0.8))).normalized()
		_s_pos[i] = pos
		_s_vel[i] = v * speed * _rng.randf_range(0.5, 1.2)
		_s_life[i] = _rng.randf_range(0.12, 0.32)


func tracer(from: Vector3, to: Vector3) -> void:
	var t := _tracers[_tracer_next]
	_tracer_t[_tracer_next] = 0.07
	_tracer_next = (_tracer_next + 1) % _tracers.size()
	var d := to - from
	if d.length() < 0.05:
		return
	var mid := from + d * 0.5
	t.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT).scaled(Vector3(1, 1, d.length())), mid)
	t.visible = true


func muzzle(pos: Vector3) -> void:
	_flash.global_position = pos
	_flash.visible = true
	_flash_t = 0.05
	(_flash.material_override as ShaderMaterial).set_shader_parameter("seed", _rng.randf())


## Material-appropriate impact. `change` is a VoxelCarver change (may be empty).
func impact(kind: int, pos: Vector3, normal: Vector3, dir: Vector3, change: Dictionary) -> void:
	var n := normal if normal.length() > 0.1 else -dir
	var cells: PackedInt32Array = change.get("cells", PackedInt32Array())
	var colors: PackedInt32Array = change.get("colors", PackedInt32Array())
	var mats: PackedByteArray = change.get("mats", PackedByteArray())
	# Voxel chunks flying out of the hole, in the removed voxels' own colours.
	var cap := 18
	var stride := maxi(1, cells.size() / cap)
	var k := 0
	while k < cells.size():
		var c := grid.coords(cells[k])
		var p := grid.center(c)
		var m := mats[k]
		var glass := (VoxelMat.FLAGS[m] & VoxelMat.F_GLASS) != 0
		# Chips pop out of the surface and mostly drop at the foot of the wall.
		var out := n * _rng.randf_range(0.3, 1.5) + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.1, 1.3), _rng.randf_range(-0.6, 0.6))
		if glass:
			out = n * _rng.randf_range(-0.8, 1.6) + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(0.0, 1.0), _rng.randf_range(-0.8, 0.8))
		var col := VoxelArt.to_color(colors[k])
		var imp: int = VoxelMat.IMPACT[m]
		var shape := Vector3.ONE
		var size := _rng.randf_range(0.55, 1.0)
		if imp == VoxelMat.Impact.WOOD and _rng.randf() < 0.5:
			shape = Vector3(0.35, 0.35, 1.6)   # splinter
		elif glass:
			shape = Vector3(1.0, 0.15, 0.8)
			size = _rng.randf_range(0.3, 0.7)
			col = Color(0.75, 0.88, 0.92)
		elif imp == VoxelMat.Impact.FLUFF:
			size = _rng.randf_range(0.4, 0.8)
			out *= 0.45
		debris(p, out, col, size * (debris_scale if not glass else 1.0), shape)
		k += stride if not glass else maxi(1, cells.size() / 36)
	# Dust and sparks by material.
	var base_col := VoxelArt.to_color(colors[0]) if colors.size() > 0 else Color(0.5, 0.48, 0.44)
	match kind:
		VoxelMat.Impact.METAL:
			sparks(pos, n, 12)
			puff(pos + n * 0.05, n * 0.4, Color(0.45, 0.45, 0.45, 0.5), 0.25, 0.6, 0.5)
		VoxelMat.Impact.GLASS:
			sparks(pos, n, 4, 3.0)
			puff(pos, n * 0.3, Color(0.85, 0.9, 0.95, 0.3), 0.3, 0.8, 0.5)
		VoxelMat.Impact.PLASTER:
			for i in 3:
				puff(pos + n * 0.1, n * _rng.randf_range(0.4, 1.0) + Vector3(_rng.randf_range(-0.3, 0.3), 0.2, _rng.randf_range(-0.3, 0.3)), Color(0.9, 0.88, 0.84, 0.75), 0.35, 1.3, 1.4)
		VoxelMat.Impact.FLUFF:
			for i in 3:
				puff(pos + n * 0.1, n * 0.5 + Vector3(0, 0.3, 0), Color(0.92, 0.72, 0.62, 0.7), 0.3, 1.0, 1.6)
		VoxelMat.Impact.CONCRETE, VoxelMat.Impact.CERAMIC:
			sparks(pos, n, 3, 4.0)
			for i in 2:
				puff(pos + n * 0.1, n * 0.6 + Vector3(0, 0.3, 0), Color(0.72, 0.7, 0.66, 0.7), 0.3, 1.2, 1.2)
		VoxelMat.Impact.DUST:
			for i in 2:
				puff(pos + n * 0.05, n * 0.5 + Vector3(0, 0.4, 0), Color(0.45, 0.4, 0.33, 0.7), 0.3, 1.1, 1.1)
		_:
			var dc := base_col.lerp(Color(0.85, 0.8, 0.7), 0.5)
			dc.a = 0.65
			for i in 2:
				puff(pos + n * 0.1, n * 0.6 + Vector3(0, 0.25, 0), dc, 0.28, 1.1, 1.0)


## A blast (Experiment 003, HouseWorld.explode): a bright flash of light and
## a fireball, a shower of debris in the removed voxels' own colours (plus
## `extra` colours, e.g. splintered doors), sparks, a ring of dust rolling
## out along the ground and a column of dark smoke. `change` is the blast's
## VoxelCarver change (may be empty).
func blast(center: Vector3, radius: float, change: Dictionary, extra := PackedColorArray()) -> void:
	_blast_effect_nodes()
	_blast_t = BLAST_TIME
	_blast_r = radius
	_blast_light.global_position = center + Vector3(0, 0.4, 0)
	_blast_light.omni_range = radius * 5.0
	_blast_light.visible = true
	_fireball.global_position = center
	_fireball.visible = true
	_update_blast(0.0)
	var cells: PackedInt32Array = change.get("cells", PackedInt32Array())
	var colors: PackedInt32Array = change.get("colors", PackedInt32Array())
	var mats: PackedByteArray = change.get("mats", PackedByteArray())
	# debris in the materials' colours, thrown away from the centre
	var n := mini(cells.size(), 150)
	var stride := maxi(1, cells.size() / maxi(n, 1))
	var k := 0
	while k < cells.size() and n > 0:
		var p := grid.center(grid.coords(cells[k]))
		var away := p - center
		away.y = maxf(away.y, 0.0)
		var v := away.normalized() * _rng.randf_range(3.0, 9.0) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(2.0, 6.0), _rng.randf_range(-1, 1))
		var m := mats[k]
		var shape := Vector3.ONE
		if VoxelMat.IMPACT[m] == VoxelMat.Impact.WOOD and _rng.randf() < 0.5:
			shape = Vector3(0.35, 0.35, 1.8)
		elif m == VoxelMat.METAL_SHEET:
			shape = Vector3(1.3, 0.2, 1.1)
		var col := VoxelArt.to_color(colors[k])
		if (VoxelMat.FLAGS[m] & VoxelMat.F_GLASS) != 0:
			col = Color(0.75, 0.88, 0.92)
			shape = Vector3(1.0, 0.15, 0.8)
		debris(p, v, col.darkened(_rng.randf_range(0.0, 0.35)), _rng.randf_range(0.6, 1.25) * debris_scale, shape)
		k += stride
		n -= 1
	for c in extra:
		var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		debris(center + Vector3(0, 0.6, 0), dir * _rng.randf_range(3.0, 7.0) + Vector3(0, _rng.randf_range(2.0, 5.0), 0), c, _rng.randf_range(0.8, 1.6), Vector3(0.35, 0.35, 1.8))
	sparks(center, Vector3.UP, 36, 9.0)
	# dust rolling out along the ground, then a slow column of dark smoke
	for i in 18:
		var a := TAU * i / 18.0 + _rng.randf_range(-0.15, 0.15)
		var out := Vector3(cos(a), 0, sin(a))
		puff(Vector3(center.x, 0.25, center.z) + out * 0.3, out * _rng.randf_range(3.0, 5.5) + Vector3(0, 0.3, 0),
				Color(0.55, 0.5, 0.44, 0.8), 0.6, 2.2, _rng.randf_range(2.2, 3.4))
	for i in 10:
		puff(center + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.0, 0.6), _rng.randf_range(-0.4, 0.4)),
				Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(1.0, 2.6), _rng.randf_range(-0.5, 0.5)),
				Color(0.2, 0.18, 0.16, 0.85), 0.7, 2.0, _rng.randf_range(3.0, 4.5))
	for i in 6:
		puff(center + Vector3(_rng.randf_range(-0.3, 0.3), 0.3, _rng.randf_range(-0.3, 0.3)), Vector3(0, 0.6, 0),
				Color(1.0, 0.62, 0.28, 0.9), 0.5, 1.6, 0.45)


const BLAST_TIME := 0.55


func blast_active() -> bool:
	return _blast_t > 0.0


func _blast_effect_nodes() -> void:
	if _blast_light != null:
		return
	_blast_light = OmniLight3D.new()
	_blast_light.name = "BlastLight"
	_blast_light.light_color = Color(1.0, 0.66, 0.34)
	_blast_light.omni_attenuation = 1.2
	_blast_light.shadow_enabled = false
	_blast_light.visible = false
	add_child(_blast_light)
	_fireball = MeshInstance3D.new()
	_fireball.name = "Fireball"
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 9
	sph.rings = 5
	_fireball.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.7, 0.35, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fireball.material_override = m
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireball.visible = false
	add_child(_fireball)


## t = seconds since the blast.
func _update_blast(t: float) -> void:
	var f := clampf(t / BLAST_TIME, 0.0, 1.0)
	_blast_light.light_energy = 14.0 * pow(1.0 - f, 2.0)
	var s := _blast_r * (0.3 + 0.6 * sqrt(f))
	_fireball.scale = Vector3(s, s * 0.8, s)
	_fireball.rotation.y = f * 1.3
	var m := _fireball.material_override as StandardMaterial3D
	m.albedo_color = Color(1.0, lerpf(0.62, 0.32, f), lerpf(0.28, 0.1, f), pow(1.0 - f, 1.5) * 0.5)


func ground_hit(pos: Vector3, dir: Vector3) -> void:
	for i in 4:
		debris(pos + Vector3(0, 0.03, 0), Vector3(_rng.randf_range(-1, 1), _rng.randf_range(1.5, 3.0), _rng.randf_range(-1, 1)) - dir * 0.8, Color(0.33, 0.28, 0.22), 0.45)
	puff(pos + Vector3(0, 0.05, 0), Vector3(0, 0.5, 0) - dir * 0.3, Color(0.42, 0.37, 0.3, 0.75), 0.3, 1.2, 1.0)


func flesh_hit(pos: Vector3, dir: Vector3, cloth: Color) -> void:
	for i in 3:
		debris(pos, dir * 2.0 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)), cloth, 0.35)
	puff(pos, dir * 0.6, Color(0.22, 0.12, 0.1, 0.55), 0.22, 0.8, 0.45)


func casing(pos: Vector3, side: Vector3) -> void:
	casing_kind(pos, side, "pistol")


## Exp 013: a spent case out of the ejection port: "pistol" (a small brass
## case), "rifle" (a long brass case), "shell" (a fat red shotgun shell).
## They tumble, bounce and settle like debris and fade with it (pooled).
func casing_kind(pos: Vector3, side: Vector3, kind := "pistol") -> void:
	var vel := side * _rng.randf_range(1.6, 2.6) + Vector3(0, _rng.randf_range(1.6, 2.6), 0)
	match kind:
		"shell":
			debris(pos, vel * 0.85, Color(0.72, 0.13, 0.1), 0.55, Vector3(0.62, 0.62, 1.5))
		"rifle":
			debris(pos, vel, Color(0.8, 0.62, 0.26), 0.36, Vector3(0.42, 0.42, 1.7))
		_:
			debris(pos, vel, Color(0.78, 0.6, 0.25), 0.3, Vector3(0.5, 0.5, 1.0))


# --- simulation -----------------------------------------------------------------------

func _solid(p: Vector3) -> bool:
	if grid == null:
		return p.y < GROUND_Y
	var c := grid.cell_of(p)
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= grid.sx or c.y >= grid.sy or c.z >= grid.sz:
		return p.y < GROUND_Y
	return grid.mat[grid.idx(c.x, c.y, c.z)] != 0 or p.y < GROUND_Y


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_debris(delta)
	_update_puffs(delta)
	_update_sparks(delta)
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			var m := _tracers[i].material_override as StandardMaterial3D
			m.albedo_color.a = clampf(_tracer_t[i] / 0.07, 0.0, 1.0) * 0.9
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	if _blast_t > 0.0:
		_blast_t -= delta
		_update_blast(BLAST_TIME - _blast_t)
		if _blast_t <= 0.0:
			_blast_light.visible = false
			_fireball.visible = false


func _update_debris(delta: float) -> void:
	debris_count = _d_active
	if _d_active <= 0:
		return
	var active := 0
	for i in MAX_DEBRIS:
		var life := _d_life[i]
		if life <= 0.0:
			continue
		life -= delta
		_d_life[i] = life
		if life <= 0.0:
			_d_mm.set_instance_transform(i, _zero)
			continue
		active += 1
		# Experiment 004: a chip that has settled keeps its transform until it
		# starts to shrink away (no per-frame MultiMesh writes for rubble)
		if _d_rest[i] == 2 and life > 0.6:
			continue
		var p := _d_pos[i]
		if _d_rest[i] == 0:
			var v := _d_vel[i]
			v.y -= GRAVITY * delta
			var np := p
			# axis-separated moves against the voxel grid
			np.x += v.x * delta
			if _solid(np):
				np.x = p.x
				v.x *= -0.3
			np.z += v.z * delta
			if _solid(np):
				np.z = p.z
				v.z *= -0.3
			np.y += v.y * delta
			if _solid(np):
				np.y = p.y
				if v.y < 0.0:
					v *= Vector3(0.55, -0.28, 0.55)
					if v.length() < 0.6:
						_d_rest[i] = 1
						v = Vector3.ZERO
				else:
					v.y = 0.0
			_d_vel[i] = v
			_d_pos[i] = np
			_d_ang[i] += _d_spin[i] * delta
			p = np
		var s := _d_scale[i] * clampf(life / 0.6, 0.0, 1.0)
		var b := Basis(_d_axis[i], _d_ang[i]) if _d_rest[i] == 0 else Basis(Vector3.UP, _d_ang[i])
		_d_mm.set_instance_transform(i, Transform3D(b.scaled(s), p + Vector3(0, 0.05 * s.y if _d_rest[i] >= 1 else 0.0, 0)))
		if _d_rest[i] == 1:
			_d_rest[i] = 2
	_d_active = active


func _update_puffs(delta: float) -> void:
	if _p_active <= 0:
		return
	var active := 0
	for i in MAX_PUFFS:
		if _p_life[i] <= 0.0:
			continue
		_p_life[i] -= delta
		if _p_life[i] <= 0.0:
			_p_mm.set_instance_transform(i, _zero)
			continue
		active += 1
		var t := 1.0 - _p_life[i] / _p_ttl[i]
		_p_vel[i] *= 1.0 - minf(delta * 2.5, 0.9)
		_p_pos[i] += (_p_vel[i] + Vector3(0, 0.12, 0)) * delta
		var s := _p_size[i] * (1.0 + _p_grow[i] * sqrt(t) * 2.0)
		_p_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), _p_pos[i]))
		var c := _p_col[i]
		_p_mm.set_instance_color(i, Color(c.r, c.g, c.b, c.a * (1.0 - t) * minf(1.0, t * 8.0 + 0.3)))
	_p_active = active


func _update_sparks(delta: float) -> void:
	if _s_active <= 0:
		return
	var active := 0
	for i in MAX_SPARKS:
		if _s_life[i] <= 0.0:
			continue
		_s_life[i] -= delta
		if _s_life[i] <= 0.0:
			_s_mm.set_instance_transform(i, _zero)
			continue
		active += 1
		_s_vel[i].y -= GRAVITY * delta
		_s_pos[i] += _s_vel[i] * delta
		var v := _s_vel[i]
		var len := clampf(v.length() * 0.025, 0.04, 0.25)
		var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
		_s_mm.set_instance_transform(i, Transform3D(Basis.looking_at(v.normalized(), up).scaled(Vector3(1, 1, len)), _s_pos[i]))
	_s_active = active
