extends Node2D
## Procedural effects for Version C: muzzle flash (with a brief shadow-casting
## light), tracer, material-specific impact particles, persistent floor specks
## and debris decals, shell casings and the dust burst of a collapsing section.

signal shake(amount: float)

const Art := preload("res://src/illustrated/ill_art.gd")
const MAX_CASINGS := 60

var specks: Specks
var debris_layer: Node2D
var _casings: Array[Node2D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234
	z_index = Art.Z_FX
	z_as_relative = false
	debris_layer = Art.layer(self, "Debris", Art.Z_DECALS)
	specks = Specks.new()
	specks.z_index = Art.Z_DECALS + 1
	specks.z_as_relative = false
	add_child(specks)


# --- gun ------------------------------------------------------------------------------

func muzzle(pos: Vector2, dir: Vector2, light_origin: Vector2) -> void:
	var f := Flash.new()
	f.position = pos
	f.rotation = dir.angle()
	f.material = Art.additive()
	add_child(f)
	var l := PointLight2D.new()
	l.texture = Art.tex("light_soft")
	l.position = light_origin
	l.texture_scale = 0.85
	l.color = Color(1.0, 0.8, 0.5)
	l.energy = 2.4
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 1.5
	l.shadow_color = Color(0, 0, 0, 0.8)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, 0.07)
	tw.tween_callback(l.queue_free)
	# a small puff of smoke from the muzzle
	var p := _particles(pos, dir, 6, 0.6, Color(0.7, 0.68, 0.64, 0.35), "dot", 25.0, 60.0, 0.5, 1.4)
	p.spread = 25.0
	_casing(pos - dir * Art.m(0.3), dir)


func tracer(a: Vector2, b: Vector2) -> void:
	var t := Tracer.new()
	t.a = a
	t.b = b
	t.material = Art.additive()
	add_child(t)


func _casing(pos: Vector2, dir: Vector2) -> void:
	var c := Polygon2D.new()
	c.polygon = PackedVector2Array([Vector2(-2.2, -0.9), Vector2(2.2, -0.9), Vector2(2.2, 0.9), Vector2(-2.2, 0.9)])
	c.color = Color(0.78, 0.6, 0.28)
	c.z_index = Art.Z_DECALS + 2
	c.z_as_relative = false
	c.position = pos
	add_child(c)
	var side := dir.orthogonal() * -1.0
	var land := pos + side * Art.m(_rng.randf_range(0.5, 0.9)) - dir * Art.m(_rng.randf_range(0.0, 0.3))
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "position", land, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", _rng.randf_range(4.0, 9.0), 0.28)
	_casings.append(c)
	if _casings.size() > MAX_CASINGS:
		var old: Node2D = _casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# --- impacts ----------------------------------------------------------------------------

## `normal` points back toward the shooter (away from the struck surface).
func impact(pos: Vector2, normal: Vector2, material: String) -> void:
	match material:
		"cladding", "wood":
			_particles(pos, normal, 14, 0.45, Color(0.72, 0.56, 0.36), "splinter", 90.0, 280.0, 0.35, 0.7).spread = 55.0
			_particles(pos, normal, 6, 0.7, Color(0.6, 0.55, 0.48, 0.5), "dot", 30.0, 90.0, 0.6, 1.8).spread = 50.0
			_scatter(pos, normal, 4, [Color(0.74, 0.58, 0.38), Color(0.2, 0.2, 0.22)])
		"plaster":
			_particles(pos, normal, 12, 0.9, Color(0.88, 0.86, 0.8, 0.55), "dot", 25.0, 110.0, 0.5, 2.4).spread = 60.0
			_particles(pos, normal, 7, 0.4, Color(0.92, 0.9, 0.86), "shard", 80.0, 220.0, 0.4, 0.8).spread = 50.0
			_scatter(pos, normal, 5, [Color(0.86, 0.83, 0.77), Color(0.75, 0.6, 0.42)])
		"glass":
			_particles(pos, normal, 18, 0.5, Color(0.8, 0.92, 1.0, 0.9), "shard", 70.0, 260.0, 0.4, 0.9).spread = 80.0
			_particles(pos, -normal, 14, 0.5, Color(0.8, 0.92, 1.0, 0.9), "shard", 90.0, 300.0, 0.4, 0.9).spread = 60.0
			_scatter(pos, normal, 4, [Color(0.82, 0.92, 0.98)])
			_scatter(pos, -normal, 9, [Color(0.82, 0.92, 0.98)])
		"metal":
			var sp := _particles(pos, normal, 12, 0.18, Color(1.0, 0.85, 0.45), "spark", 160.0, 420.0, 0.6, 1.0)
			sp.spread = 70.0
			sp.material = Art.additive()
			_particles(pos, normal, 4, 0.5, Color(0.55, 0.55, 0.55, 0.45), "dot", 20.0, 60.0, 0.5, 1.4)
		"flesh":
			_particles(pos, -normal, 7, 0.35, Color(0.32, 0.06, 0.06), "dot", 60.0, 150.0, 0.25, 0.5).spread = 40.0
			_particles(pos, normal, 5, 0.6, Color(0.55, 0.53, 0.5, 0.45), "dot", 20.0, 60.0, 0.5, 1.2)
			_scatter(pos, -normal, 3, [Color(0.25, 0.05, 0.05, 0.85)])
		_:
			_particles(pos, normal, 8, 0.6, Color(0.5, 0.45, 0.38, 0.5), "dot", 30.0, 90.0, 0.5, 1.6).spread = 60.0


## A wall section gave way: debris on both sides, a dust cloud, flying planks.
func wall_removed(section) -> void:
	var c: Vector2 = section.center()
	var along := Vector2.RIGHT.rotated(section.rotation)
	var across := along.orthogonal()
	var is_window: bool = section.kind == "window"
	for side in [-1.0, 1.0]:
		for k in 2:
			var name_ := "debris_glass" if (is_window and k == 0) else ("debris_plaster" if k == 0 else "debris_planks")
			if section.exterior and side < 0.0 and name_ == "debris_plaster":
				name_ = "debris_planks"
			var tex := Art.tex(name_)
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.texture = tex
			var size_m := _rng.randf_range(0.75, 1.0)
			var k_ := size_m * Art.PX_PER_M / tex.get_size().x
			s.scale = Vector2(k_, k_)
			s.rotation = section.rotation + _rng.randf_range(-0.5, 0.5) + (PI if _rng.randf() < 0.5 else 0.0)
			s.position = c + across * side * Art.m(_rng.randf_range(0.3, 0.55)) + along * Art.m(_rng.randf_range(-0.35, 0.35))
			debris_layer.add_child(s)
	# the gap itself: a scatter of splinters and plaster crumbs over the subfloor
	for i in 26:
		var p := c + along * Art.m(_rng.randf_range(-0.5, 0.5)) + across * Art.m(_rng.randf_range(-0.6, 0.6))
		specks.add(p, _rng.randf_range(0.8, 2.2), [Color(0.82, 0.8, 0.74), Color(0.7, 0.55, 0.36), Color(0.15, 0.12, 0.1)][i % 3])
	var dust := _particles(c, across, 36, 1.6, Color(0.78, 0.75, 0.7, 0.5), "dot", 20.0, 120.0, 1.5, 4.5)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(Art.m(0.4), Art.m(0.15))
	dust.spread = 180.0
	dust.rotation = section.rotation
	for side in [-1.0, 1.0]:
		var pl := _particles(c, across * side, 10, 0.7, Color(0.62, 0.48, 0.32), "splinter", 120.0, 320.0, 0.9, 2.0)
		pl.spread = 70.0
	shake.emit(5.0)


func body_hit(pos: Vector2, dir: Vector2) -> void:
	impact(pos, -dir, "flesh")


## Swing at the player: a small whoosh of dust.
func swing(pos: Vector2, dir: Vector2) -> void:
	_particles(pos + dir * Art.m(0.35), dir, 5, 0.4, Color(0.6, 0.58, 0.55, 0.3), "dot", 20.0, 50.0, 0.4, 1.0).spread = 70.0


func _scatter(pos: Vector2, normal: Vector2, n: int, colors: Array) -> void:
	for i in n:
		var d := normal.rotated(_rng.randf_range(-1.0, 1.0)) * Art.m(_rng.randf_range(0.08, 0.5))
		specks.add(pos + d, _rng.randf_range(0.6, 1.5), colors[i % colors.size()])


func _particles(pos: Vector2, dir: Vector2, amount: int, life: float, color: Color, tex: String,
		v_min: float, v_max: float, s_min: float, s_max: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = life
	p.texture = Art.fx_texture(tex)
	p.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	p.spread = 45.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.damping_min = v_max * 1.4
	p.damping_max = v_max * 2.2
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	if tex == "splinter" or tex == "spark":
		p.particle_flag_align_y = false
		p.angle_min = 0.0
		p.angle_max = 0.0
		p.particle_flag_align_y = true
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.6, color)
	p.color_ramp = g
	if tex == "dot":
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.5))
		sc.add_point(Vector2(1, 1.0))
		p.scale_amount_curve = sc
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.5, false).timeout.connect(p.queue_free)
	return p


# --- drawing helpers -------------------------------------------------------------------

class Flash extends Node2D:
	var _t := 0.0
	const DUR := 0.06

	func _process(delta: float) -> void:
		_t += delta
		if _t >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - clampf(_t / DUR, 0.0, 1.0)
		var pts := PackedVector2Array()
		for i in 10:
			var a := (float(i) / 10.0) * TAU
			var r := (18.0 if i % 2 == 0 else 6.0) * (0.6 + 0.4 * k)
			if i == 0:
				r = 30.0 * (0.6 + 0.4 * k)
			pts.append(Vector2(cos(a), sin(a)) * r + Vector2(6, 0))
		draw_colored_polygon(pts, Color(1.0, 0.62, 0.22, 0.75 * k))
		draw_circle(Vector2(4, 0), 6.0 * k + 2.0, Color(1.0, 0.95, 0.75, k))


class Tracer extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var _t := 0.0
	const DUR := 0.09

	func _process(delta: float) -> void:
		_t += delta
		if _t >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - clampf(_t / DUR, 0.0, 1.0)
		var head := b
		var tail := a.lerp(b, clampf(_t / DUR, 0.0, 1.0) * 0.85)
		draw_line(tail, head, Color(1.0, 0.7, 0.35, 0.35 * k), 5.0)
		draw_line(tail, head, Color(1.0, 0.93, 0.75, 0.9 * k), 1.6)


## Persistent floor marks (plaster crumbs, splinters, glass glints, drops):
## one node draws them all.
class Specks extends Node2D:
	const MAX := 5000
	var _p := PackedVector2Array()
	var _r := PackedFloat32Array()
	var _c := PackedColorArray()

	func add(p: Vector2, r: float, c: Color) -> void:
		_p.append(p)
		_r.append(r)
		_c.append(c)
		if _p.size() > MAX:
			_p = _p.slice(500)
			_r = _r.slice(500)
			_c = _c.slice(500)
		queue_redraw()

	func _draw() -> void:
		for i in _p.size():
			var c := _c[i]
			draw_circle(_p[i] + Vector2(0.5, 0.7), _r[i] + 0.4, Color(0, 0, 0, 0.35 * c.a))
			draw_circle(_p[i], _r[i], c)
