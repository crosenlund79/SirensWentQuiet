class_name ModFx
extends Node3D
## Impact and destruction effects, cheap and capped:
##  * chips   - small solid pieces (splinters, plaster, glass, soil) simulated
##              on the CPU and drawn with one MultiMesh; they settle on the
##              floor and stay until recycled (ring buffer)
##  * dust    - soft lit puffs (one MultiMesh)
##  * glow    - sparks and bullet tracers (one additive MultiMesh)
##  * chunks  - a capped handful of short-lived rigid bodies for breaches
## No collision with characters; nothing here affects navigation.

const CHIPS := 420
const DUST := 160
const GLOW := 96
const TRACERS := 8
const MAX_CHUNKS := 10
const FLOOR_Y := 0.035
const GRAVITY := 9.8

# chips
var _c_pos := PackedVector3Array()
var _c_vel := PackedVector3Array()
var _c_size := PackedVector3Array()
var _c_axis := PackedVector3Array()
var _c_ang := PackedFloat32Array()
var _c_spin := PackedFloat32Array()
var _c_live := PackedByteArray()       # 0 free, 1 flying, 2 resting
var _c_next := 0
var _c_mm: MultiMesh
# dust
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_life := PackedFloat32Array()
var _d_max := PackedFloat32Array()
var _d_size := PackedVector2Array()    # start, end
var _d_col := PackedColorArray()
var _d_next := 0
var _d_mm: MultiMesh
# glow: sparks (0..GLOW-TRACERS) + tracers (last TRACERS)
var _g_pos := PackedVector3Array()
var _g_vel := PackedVector3Array()
var _g_life := PackedFloat32Array()
var _g_max := PackedFloat32Array()
var _g_col := PackedColorArray()
var _g_len := PackedFloat32Array()
var _g_next := 0
var _t_next := 0
var _t_from := PackedVector3Array()
var _t_to := PackedVector3Array()
var _g_mm: MultiMesh

var _chunks: Array[RigidBody3D] = []
var _chunk_age := {}
var active_chips := 0


func _ready() -> void:
	_c_mm = _make_mm(CHIPS, _box_mesh(), ModMaterials.fx_solid(), true, "Chips")
	for a in [_c_pos, _c_vel, _c_size, _c_axis]:
		a.resize(CHIPS)
	_c_ang.resize(CHIPS)
	_c_spin.resize(CHIPS)
	_c_live.resize(CHIPS)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var dust_mat := ShaderMaterial.new()
	dust_mat.shader = load("res://src/modular/fx/dust.gdshader")
	_d_mm = _make_mm(DUST, q, dust_mat, false, "Dust")
	_d_pos.resize(DUST)
	_d_vel.resize(DUST)
	_d_life.resize(DUST)
	_d_max.resize(DUST)
	_d_size.resize(DUST)
	_d_col.resize(DUST)
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = load("res://src/modular/fx/glow.gdshader")
	_g_mm = _make_mm(GLOW, _box_mesh(), glow_mat, false, "Glow")
	_g_pos.resize(GLOW)
	_g_vel.resize(GLOW)
	_g_life.resize(GLOW)
	_g_max.resize(GLOW)
	_g_col.resize(GLOW)
	_g_len.resize(GLOW)
	_t_from.resize(TRACERS)
	_t_to.resize(TRACERS)
	for i in CHIPS:
		_c_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))
	for i in DUST:
		_d_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))
	for i in GLOW:
		_g_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))


func _make_mm(count: int, mesh: Mesh, mat: Material, shadows: bool, name_: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 120))
	add_child(mmi)
	return mm


func _box_mesh() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


# --- emitters ---------------------------------------------------------------------------------

func chip(p: Vector3, v: Vector3, size: Vector3, col: Color, shiny := 0.0) -> void:
	var i := _c_next
	_c_next = (_c_next + 1) % CHIPS
	_c_pos[i] = p
	_c_vel[i] = v
	_c_size[i] = size
	_c_axis[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_c_ang[i] = randf() * TAU
	_c_spin[i] = randf_range(6.0, 18.0)
	_c_live[i] = 1
	_c_mm.set_instance_custom_data(i, Color(col.r, col.g, col.b, shiny))


func dust(p: Vector3, v: Vector3, s0: float, s1: float, life: float, col: Color) -> void:
	var i := _d_next
	_d_next = (_d_next + 1) % DUST
	_d_pos[i] = p
	_d_vel[i] = v
	_d_life[i] = life
	_d_max[i] = life
	_d_size[i] = Vector2(s0, s1)
	_d_col[i] = col


func spark(p: Vector3, v: Vector3, life: float, col: Color, length := 0.12) -> void:
	var i := _g_next
	_g_next = (_g_next + 1) % (GLOW - TRACERS)
	_g_pos[i] = p
	_g_vel[i] = v
	_g_life[i] = life
	_g_max[i] = life
	_g_col[i] = col
	_g_len[i] = length


func tracer(from: Vector3, to: Vector3) -> void:
	var k := _t_next
	_t_next = (_t_next + 1) % TRACERS
	var i := GLOW - TRACERS + k
	_t_from[k] = from
	_t_to[k] = to
	_g_life[i] = 0.09
	_g_max[i] = 0.09
	_g_col[i] = Color(1.0, 0.85, 0.55)


func _spray(n: int, at: Vector3, normal: Vector3, speed: float, spread: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in n:
		var r := Vector3(randf_range(-1, 1), randf_range(-0.6, 1.2), randf_range(-1, 1)) * spread
		out.append((normal + r).normalized() * speed * randf_range(0.5, 1.2))
	return out


## Material-appropriate bullet impact.
func impact(mat: String, at: Vector3, normal: Vector3) -> void:
	match mat:
		"siding":
			for v in _spray(6, at, normal, 3.2, 0.7):
				chip(at, v, Vector3(randf_range(0.04, 0.09), 0.012, 0.02), Color(0.62, 0.66, 0.68) if randf() < 0.6 else Color(0.85, 0.72, 0.52))
			for v in _spray(2, at, normal, 0.6, 0.5):
				dust(at + normal * 0.05, v, 0.12, 0.5, randf_range(0.7, 1.1), Color(0.75, 0.73, 0.7, 0.55))
		"plaster":
			for v in _spray(4, at, normal, 2.6, 0.6):
				chip(at, v, Vector3.ONE * randf_range(0.015, 0.03), Color(0.93, 0.92, 0.88))
			for v in _spray(4, at, normal, 0.8, 0.6):
				dust(at + normal * 0.05, v, 0.15, 0.7, randf_range(0.9, 1.4), Color(0.92, 0.9, 0.86, 0.6))
		"timber", "wood", "trim":
			for v in _spray(6, at, normal, 3.0, 0.7):
				chip(at, v, Vector3(randf_range(0.04, 0.1), 0.01, 0.015), Color(0.82, 0.66, 0.44).darkened(randf_range(0, 0.25)))
			dust(at + normal * 0.05, normal * 0.4, 0.1, 0.4, 0.8, Color(0.7, 0.62, 0.5, 0.45))
		"glass":
			for v in _spray(7, at, normal, 2.0, 0.9):
				chip(at, v, Vector3(randf_range(0.02, 0.05), 0.004, randf_range(0.02, 0.04)), Color(0.75, 0.88, 0.9), 1.0)
			spark(at, Vector3.ZERO, 0.08, Color(0.9, 0.95, 1.0), 0.05)
		"metal":
			for v in _spray(9, at, normal, 6.0, 0.8):
				spark(at, v, randf_range(0.12, 0.3), Color(1.0, 0.75, 0.35), 0.1)
			dust(at + normal * 0.04, normal * 0.3, 0.06, 0.25, 0.4, Color(0.4, 0.4, 0.4, 0.4))
		"fabric":
			for v in _spray(3, at, normal, 1.6, 0.8):
				chip(at, v, Vector3.ONE * randf_range(0.015, 0.025), Color(0.92, 0.9, 0.86))
			for v in _spray(3, at, normal, 0.5, 0.7):
				dust(at + normal * 0.05, v, 0.08, 0.35, 0.9, Color(0.85, 0.83, 0.8, 0.5))
		"ground":
			for v in _spray(5, at, Vector3.UP, 2.4, 0.5):
				chip(at, v, Vector3.ONE * randf_range(0.015, 0.035), Color(0.38, 0.33, 0.27))
			for v in _spray(2, at, Vector3.UP, 0.6, 0.6):
				dust(at, v, 0.12, 0.6, 1.0, Color(0.55, 0.5, 0.42, 0.55))
		"enemy":
			for v in _spray(4, at, normal, 1.8, 0.7):
				chip(at, v, Vector3.ONE * randf_range(0.015, 0.03), Color(0.3, 0.08, 0.07))
			dust(at, normal * 0.3, 0.1, 0.35, 0.45, Color(0.35, 0.12, 0.1, 0.6))
		_:
			for v in _spray(4, at, normal, 2.4, 0.7):
				chip(at, v, Vector3.ONE * randf_range(0.015, 0.03), Color(0.5, 0.5, 0.5))
			dust(at + normal * 0.05, normal * 0.4, 0.1, 0.4, 0.8, Color(0.7, 0.7, 0.7, 0.45))


## Glass pane bursting: shards over the whole opening, falling both ways.
func shatter(center: Vector3, along: Vector3, width: float, height: float, normal: Vector3) -> void:
	for k in 46:
		var p := center + along * randf_range(-0.5, 0.5) * width + Vector3.UP * randf_range(-0.5, 0.5) * height
		var v := normal * randf_range(-1.6, 2.4) + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 1.2), randf_range(-0.5, 0.5))
		chip(p, v, Vector3(randf_range(0.03, 0.09), 0.005, randf_range(0.02, 0.07)), Color(0.72, 0.86, 0.88), 1.0)
	for k in 4:
		spark(center + along * randf_range(-0.4, 0.4) * width, Vector3.ZERO, 0.1, Color(0.85, 0.92, 1.0), 0.04)


## A wall module changing state: debris scaled by how bad it got.
func wall_burst(m: ModWall, heavy: bool, from_dir: Vector3) -> void:
	var c := m.world_center()
	var along := m.global_transform.basis.x.normalized()
	var nrm := m.global_transform.basis.z.normalized()
	var push := from_dir.normalized() if from_dir.length_squared() > 0.01 else nrm
	var n := 46 if heavy else 18
	for k in n:
		var p := c + along * randf_range(-0.45, 0.45) * m.length + Vector3.UP * randf_range(-0.9, 0.5)
		var side := 1.0 if randf() < 0.65 else -1.0
		var v := push * side * randf_range(0.8, 3.5) + Vector3(randf_range(-0.8, 0.8), randf_range(0.0, 2.5), randf_range(-0.8, 0.8))
		var r := randf()
		if m.exterior and r < 0.3:
			chip(p, v, Vector3(randf_range(0.08, 0.22), 0.015, randf_range(0.04, 0.12)), Color(0.62, 0.66, 0.68))
		elif r < 0.55:
			chip(p, v, Vector3(randf_range(0.05, 0.14), randf_range(0.01, 0.03), randf_range(0.04, 0.1)), Color(0.92, 0.91, 0.87))
		elif r < 0.8:
			chip(p, v, Vector3(randf_range(0.06, 0.2), 0.02, 0.03), Color(0.85, 0.7, 0.48))
		elif m.exterior:
			chip(p, v, Vector3.ONE * randf_range(0.04, 0.08), Color(0.95, 0.78, 0.5))
		else:
			chip(p, v, Vector3.ONE * randf_range(0.02, 0.05), Color(0.8, 0.79, 0.75))
	var puffs := 14 if heavy else 6
	for k in puffs:
		var p := c + along * randf_range(-0.5, 0.5) * m.length + Vector3.UP * randf_range(-1.1, 0.6)
		var v := Vector3(randf_range(-0.5, 0.5), randf_range(0.05, 0.4), randf_range(-0.5, 0.5)) + push * randf_range(0.2, 0.9)
		dust(p, v, randf_range(0.3, 0.5), randf_range(1.0, 1.6), randf_range(1.6, 2.6), Color(0.78, 0.76, 0.72, 0.5))
	var chunks := 5 if heavy else 2
	for k in chunks:
		_chunk(m, c + along * randf_range(-0.35, 0.35) * m.length + Vector3.UP * randf_range(-0.6, 0.5), push)


func _chunk(m: ModWall, at: Vector3, push: Vector3) -> void:
	if _chunks.size() >= MAX_CHUNKS:
		var old: RigidBody3D = _chunks.pop_front()
		_chunk_age.erase(old)
		old.queue_free()
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | 2
	body.mass = 2.0
	var size: Vector3
	var col: Color
	var r := randf()
	if m.exterior and r < 0.45:
		size = Vector3(randf_range(0.35, 0.7), 0.025, 0.14)
		col = Color(0.62, 0.66, 0.68)
	elif r < 0.75:
		size = Vector3(randf_range(0.25, 0.45), 0.016, randf_range(0.15, 0.3))
		col = Color(0.92, 0.91, 0.87)
	else:
		size = Vector3(0.045, randf_range(0.4, 0.8), 0.09)
		col = Color(0.85, 0.7, 0.48)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mm := ModMesh.new()
	mm.set_mat(ModMaterials.L_PLAIN, col)
	mm.cbox(Vector3.ZERO, size)
	mi.mesh = mm.commit()
	mi.material_override = ModMaterials.kit()
	body.add_child(mi)
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3(randf(), randf(), randf()).normalized(), randf() * TAU), at)
	body.linear_velocity = push * randf_range(1.5, 3.5) + Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 2.0), randf_range(-0.6, 0.6))
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_chunks.append(body)
	_chunk_age[body] = 0.0


func chunk_count() -> int:
	return _chunks.size()


# --- simulation ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_step_chips(delta)
	_step_dust(delta)
	_step_glow(delta)
	_step_chunks(delta)


func _step_chips(delta: float) -> void:
	var count := 0
	for i in CHIPS:
		var live := _c_live[i]
		if live == 0:
			continue
		count += 1
		if live == 2:
			continue
		var v := _c_vel[i]
		var p := _c_pos[i] + v * delta
		v.y -= GRAVITY * delta
		var ang := _c_ang[i] + _c_spin[i] * delta
		if p.y < FLOOR_Y + _c_size[i].y * 0.5:
			p.y = FLOOR_Y + _c_size[i].y * 0.5
			v = Vector3(v.x * 0.45, -v.y * 0.25, v.z * 0.45)
			_c_spin[i] *= 0.5
			if v.length_squared() < 0.08:
				_c_live[i] = 2
				# settle flat
				var yaw := Basis(Vector3.UP, ang)
				_c_mm.set_instance_transform(i, Transform3D(yaw.scaled(_c_size[i]), p))
				_c_pos[i] = p
				continue
		_c_vel[i] = v
		_c_pos[i] = p
		_c_ang[i] = ang
		var b := Basis(_c_axis[i], ang) * Basis.from_scale(_c_size[i])
		_c_mm.set_instance_transform(i, Transform3D(b, p))
	active_chips = count


func _step_dust(delta: float) -> void:
	for i in DUST:
		if _d_life[i] <= 0.0:
			continue
		_d_life[i] -= delta
		var t := 1.0 - _d_life[i] / _d_max[i]
		if _d_life[i] <= 0.0:
			_d_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))
			continue
		var v := _d_vel[i] * (1.0 - delta * 1.8)
		v.y -= 0.15 * delta
		_d_vel[i] = v
		_d_pos[i] += v * delta
		var s := lerpf(_d_size[i].x, _d_size[i].y, 1.0 - pow(1.0 - t, 2.0))
		_d_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), _d_pos[i]))
		var c := _d_col[i]
		_d_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, c.a * (1.0 - t) * smoothstep(0.0, 0.08, t)))


func _step_glow(delta: float) -> void:
	for i in GLOW:
		if _g_life[i] <= 0.0:
			continue
		_g_life[i] -= delta
		if _g_life[i] <= 0.0:
			_g_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))
			continue
		var a := _g_life[i] / _g_max[i]
		var c := _g_col[i]
		if i >= GLOW - TRACERS:
			var k := i - (GLOW - TRACERS)
			var from := _t_from[k]
			var to := _t_to[k]
			var d := to - from
			var length := d.length()
			if length < 0.01:
				continue
			# a bright streak travelling toward the target
			var head := clampf(1.0 - a, 0.0, 1.0) * 0.5 + 0.5
			var seg_start := from + d * maxf(0.0, head - 0.55)
			var seg_end := from + d * head
			var seg := seg_end - seg_start
			var basis := _along(seg.normalized(), Vector3(0.028, 0.028, seg.length()))
			_g_mm.set_instance_transform(i, Transform3D(basis, (seg_start + seg_end) * 0.5))
			_g_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, a * 0.9))
			continue
		var v := _g_vel[i]
		v.y -= GRAVITY * 0.6 * delta
		_g_vel[i] = v
		_g_pos[i] += v * delta
		var ln := maxf(_g_len[i], v.length() * 0.025)
		var dir := v.normalized() if v.length_squared() > 0.001 else Vector3.UP
		_g_mm.set_instance_transform(i, Transform3D(_along(dir, Vector3(0.012, 0.012, ln)), _g_pos[i]))
		_g_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, a))


func _along(dir: Vector3, size: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	return Basis(x * size.x, y * size.y, dir * size.z)


func _step_chunks(delta: float) -> void:
	for b in _chunks.duplicate():
		if not is_instance_valid(b):
			_chunks.erase(b)
			continue
		var age: float = _chunk_age.get(b, 0.0) + delta
		_chunk_age[b] = age
		if age > 4.0:
			var s := clampf(1.0 - (age - 4.0) / 0.6, 0.0, 1.0)
			for c in b.get_children():
				if c is MeshInstance3D:
					c.scale = Vector3(s, s, s)
			if s <= 0.0:
				_chunks.erase(b)
				_chunk_age.erase(b)
				b.queue_free()
