class_name VoxelRig
extends Node3D
## Small voxel-sculpted character (0.05 m voxels) with procedural animation.
## Parts: torso (with head child), two arms, two legs, optional gun. Faces -Z.
## Meshes are sculpted from implicit functions once per look and shared.

const VS := 0.05

enum Look { PLAYER, ENEMY_A, ENEMY_B, ENEMY_C, ENEMY_D }

const HIP_Y := 0.9
const SHOULDER_Y := 1.42
const NECK_Y := 1.5

static var _mesh_cache := {}
static var material: ShaderMaterial
static var _player_material: ShaderMaterial
static var _enemy_material: ShaderMaterial

var look := Look.PLAYER
var hunch := 0.0             ## forward lean of the torso (rad)
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var gun: Node3D
var parts: Array[MeshInstance3D] = []

var walk_phase := 0.0
var speed := 0.0             ## current ground speed (m/s), drives the gait
var _gait := 0.0             ## Refinement 01: current leg swing (radians), eased toward the speed's
var aim_pitch := 0.0         ## right arm aiming (player)
var aiming := false
var recoil := 0.0
var swing := 0.0             ## enemy swing progress 1 -> 0
var stagger := 0.0
## Experiment 004 (E), player only: without a weapon in hand (`aiming` false)
## the arms hang and sway a little; `carry` holds the right arm out (the
## flashlight, pointed by aim_pitch); `held` is the small item in the right
## hand (set_held); `use_t` lifts the hand once (eating, drinking, bandaging).
var carry := false
var held := ""
var use_t := 0.0
var _held_node: Node3D
var _flash := 0.0
var _fade := 1.0
var _t := 0.0


## Base character material (night uniform lives here; the per-look
## materials below share its parameters through `night_materials`).
static func shared_material() -> ShaderMaterial:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://src/voxel/shaders/voxel_character.gdshader")
	return material


## Character material with an x-ray silhouette pass (warm for the player,
## pale red for psychos) shown only where walls hide the figure.
static func look_material(player: bool) -> ShaderMaterial:
	var m := _player_material if player else _enemy_material
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = shared_material().shader
	var x := ShaderMaterial.new()
	x.shader = load("res://src/voxel/shaders/voxel_xray.gdshader")
	x.set_shader_parameter("tint", Color(1.0, 0.72, 0.35, 0.5) if player else Color(0.95, 0.5, 0.45, 0.32))
	m.next_pass = x
	if player:
		_player_material = m
	else:
		_enemy_material = m
	return m


func _init(which: Look = Look.PLAYER) -> void:
	look = which


func _ready() -> void:
	var enemy := look != Look.PLAYER
	hunch = 0.38 if enemy else 0.0
	torso = _pivot(self, Vector3(0, HIP_Y, 0), "torso")
	head = _pivot(torso, Vector3(0, NECK_Y - HIP_Y, -0.03 if not enemy else -0.06), "head")
	arm_l = _pivot(torso, Vector3(-0.23, SHOULDER_Y - HIP_Y, 0), "arm_l")
	arm_r = _pivot(torso, Vector3(0.23, SHOULDER_Y - HIP_Y, 0), "arm_r")
	leg_l = _pivot(self, Vector3(-0.1, HIP_Y, 0), "leg_l")
	leg_r = _pivot(self, Vector3(0.1, HIP_Y, 0), "leg_r")
	if look == Look.PLAYER:
		gun = _pivot(arm_r, Vector3(0, -0.58, 0), "gun")


func _pivot(parent: Node3D, pos: Vector3, part: String) -> Node3D:
	var n := Node3D.new()
	n.name = part
	n.position = pos
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(look, part)
	mi.material_override = look_material(look == Look.PLAYER)
	n.add_child(mi)
	parts.append(mi)
	return n


func set_flash(v: float) -> void:
	_flash = v
	for p in parts:
		p.set_instance_shader_parameter("flash", v)


func set_fade(v: float) -> void:
	_fade = v
	for p in parts:
		p.set_instance_shader_parameter("fade", v)


## The small item in the right hand (player): "flashlight", "hammer",
## "crowbar", "shovel", "food", "water", "medical", or "" (nothing). Simple
## boxes in arm space (the arm points down -Y; the hand is at y -0.6).
func set_held(kind: String) -> void:
	if kind == held and (_held_node != null) == (kind != ""):
		return
	held = kind
	if _held_node != null:
		_held_node.queue_free()
		_held_node = null
	if kind == "" or arm_r == null:
		return
	_held_node = held_model(kind)
	if _held_node != null:
		_held_node.name = "Held"
		_held_node.position = Vector3(0, -0.6, 0)
		arm_r.add_child(_held_node)


## Hand position in world space (where a held flashlight shines from).
func hand_global() -> Vector3:
	if arm_r == null or not arm_r.is_inside_tree():
		return global_position + Vector3(0, 1.0, 0)
	return arm_r.global_transform * Vector3(0, -0.72, 0)


static func held_model(kind: String) -> Node3D:
	# [size, offset, colour] boxes; -Y is "forward" when the arm is raised
	var parts := []
	match kind:
		"flashlight":
			parts = [[Vector3(0.05, 0.2, 0.05), Vector3(0, -0.08, 0), Color(0.12, 0.12, 0.13)],
				[Vector3(0.07, 0.05, 0.07), Vector3(0, -0.2, 0), Color(0.2, 0.2, 0.21)],
				[Vector3(0.055, 0.01, 0.055), Vector3(0, -0.228, 0), Color(1.0, 0.95, 0.75)]]
		"hammer":
			parts = [[Vector3(0.03, 0.03, 0.3), Vector3(0, -0.02, -0.06), Color(0.45, 0.3, 0.18)],
				[Vector3(0.05, 0.12, 0.05), Vector3(0, -0.02, -0.22), Color(0.3, 0.31, 0.33)]]
		"crowbar":
			parts = [[Vector3(0.025, 0.025, 0.55), Vector3(0, -0.02, -0.12), Color(0.55, 0.12, 0.1)],
				[Vector3(0.025, 0.1, 0.025), Vector3(0, -0.06, -0.39), Color(0.55, 0.12, 0.1)]]
		"shovel":
			parts = [[Vector3(0.03, 0.03, 0.8), Vector3(0, -0.02, -0.1), Color(0.5, 0.36, 0.22)],
				[Vector3(0.16, 0.02, 0.2), Vector3(0, -0.02, -0.58), Color(0.35, 0.37, 0.38)]]
		"drill":      # Exp 007 (O): a hand drill
			parts = [[Vector3(0.07, 0.08, 0.2), Vector3(0, -0.04, -0.1), Color(0.86, 0.58, 0.14)],
				[Vector3(0.05, 0.12, 0.06), Vector3(0, 0.04, 0.0), Color(0.12, 0.12, 0.13)],
				[Vector3(0.015, 0.015, 0.14), Vector3(0, -0.04, -0.27), Color(0.72, 0.72, 0.74)]]
		"food":
			parts = [[Vector3(0.08, 0.1, 0.08), Vector3(0, -0.05, 0.02), Color(0.7, 0.32, 0.2)]]
		"water":
			parts = [[Vector3(0.065, 0.2, 0.065), Vector3(0, -0.07, 0.02), Color(0.55, 0.72, 0.85)],
				[Vector3(0.03, 0.03, 0.03), Vector3(0, -0.185, 0.02), Color(0.2, 0.4, 0.75)]]
		"medical":
			parts = [[Vector3(0.12, 0.09, 0.04), Vector3(0, -0.05, 0.02), Color(0.86, 0.86, 0.84)],
				[Vector3(0.05, 0.015, 0.042), Vector3(0, -0.05, 0.02), Color(0.75, 0.15, 0.15)]]
		_:
			parts = [[Vector3(0.08, 0.08, 0.08), Vector3(0, -0.04, 0.02), Color(0.5, 0.48, 0.44)]]
	var root := Node3D.new()
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		mi.mesh = box
		mi.position = p[1]
		var m := StandardMaterial3D.new()
		m.albedo_color = p[2]
		m.roughness = 0.7
		if kind == "flashlight" and p == parts[-1]:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.92, 0.7)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Muzzle tip in world space (player).
func muzzle_global() -> Vector3:
	if gun == null:
		return global_position + Vector3(0, Tuning.MUZZLE_HEIGHT, 0)
	return gun.global_transform * Vector3(0, -0.26, 0)


func animate(delta: float) -> void:
	_t += delta
	var enemy := look != Look.PLAYER
	# Refinement 01: the gait follows the real ground speed. The legs swing by
	# `swing` (radians, growing with speed) and the cycle advances by distance
	# travelled over the step length those legs actually cover (2 x leg x
	# sin(swing)), so the feet keep pace with the ground instead of
	# scrambling. Above walking speed (the player's sprint, a runner) the gait
	# turns into a run: longer swing, more lean and bounce, pumping arms.
	var walk_top := 4.0 if not enemy else 1.4
	var g := speed / walk_top
	var run := clampf((g - 1.05) / 0.5, 0.0, 1.0)
	var swing_amp := 0.5 * clampf(g, 0.0, 1.0) + 0.27 * run
	_gait = move_toward(_gait, swing_amp, delta * 4.0)       # smooth start and stop
	if speed > 0.05:
		var step := maxf(2.0 * HIP_Y * sin(maxf(_gait, 0.05)) * 1.25, 0.32)
		walk_phase += delta * speed * PI / step
	var amp := clampf(g, 0.0, 1.0) if speed > 0.05 else _gait * 2.0
	var s := sin(walk_phase)
	var bob := absf(cos(walk_phase)) * (0.045 + 0.04 * run) * amp
	var breathe := sin(_t * (2.0 if not enemy else 1.3)) * 0.012
	torso.position.y = HIP_Y + bob + breathe
	var lean := hunch + amp * (0.06 if not enemy else 0.1) + run * 0.16 - stagger * 0.5 - recoil * 0.06
	torso.rotation = Vector3(-lean, sin(walk_phase) * (0.06 + 0.05 * run) * amp, sin(walk_phase * 0.5) * (0.08 if enemy else 0.02) * amp)
	leg_l.rotation.x = s * _gait
	leg_r.rotation.x = -s * _gait
	if enemy:
		# limp: right leg drags
		leg_r.rotation.x *= 0.6
		head.rotation = Vector3(0.25 + sin(_t * 0.9) * 0.08, sin(_t * 0.7) * 0.25, sin(_t * 1.3) * 0.12)
		var reach := 0.35 + sin(_t * 1.7) * 0.05
		var sw := 0.0
		if swing > 0.0:
			# wind up overhead, then strike down and forward
			var p := 1.0 - swing
			sw = 2.3 * sin(p / 0.55 * PI * 0.5) if p < 0.55 else 2.3 * (1.0 - (p - 0.55) / 0.45) - 0.2
		arm_l.rotation = Vector3(reach + s * 0.25 * amp + sw, 0, -0.08)
		arm_r.rotation = Vector3(reach - s * 0.25 * amp + sw * 0.9, 0, 0.12)
	else:
		head.rotation = Vector3(0.05, 0, 0)
		if aiming:
			arm_l.rotation = Vector3(1.2 + aim_pitch * 0.8, 0, 0.5)
			arm_r.rotation = Vector3(PI * 0.5 + aim_pitch + recoil * 0.35, 0, 0)
		else:
			# empty or busy hands: relaxed, swinging with the gait, a slow idle sway
			var sway := sin(_t * 1.1) * 0.03 * (1.0 - amp)
			arm_l.rotation = Vector3(-s * (0.45 + 0.4 * run) * amp + sway + run * 0.25, 0, -0.07)
			var lift := sin(clampf(use_t, 0.0, 1.0) * PI) * 1.7
			if carry:
				arm_r.rotation = Vector3(1.3 + aim_pitch * 0.8 + lift * 0.3, 0, 0.0)
			elif held != "":
				arm_r.rotation = Vector3(0.32 + s * 0.18 * amp + lift, 0, 0.08)
			else:
				arm_r.rotation = Vector3(s * (0.45 + 0.4 * run) * amp - sway + lift + run * 0.25, 0, 0.07)
			use_t = maxf(use_t - delta * 1.6, 0.0)
	recoil = maxf(recoil - delta * 9.0, 0.0)
	stagger = maxf(stagger - delta * 3.5, 0.0)
	if _flash > 0.0:
		set_flash(maxf(_flash - delta * 7.0, 0.0))


# --- sculpting ------------------------------------------------------------------------

static func _palette(which: Look) -> Dictionary:
	match which:
		Look.PLAYER:
			return {"top": 0x262b33, "top2": 0x1f232a, "legs": 0x2b3341, "shoe": 0x2e2219, "skin": 0xd2a98c,
				"hair": 0x3b2a20, "accent": 0xd0752a, "strap": 0x6b4a2e, "pack": 0x4a4e3c}
		Look.ENEMY_A:
			return {"top": 0xb5afa2, "top2": 0x8f897c, "legs": 0x48484a, "shoe": 0x2a2624, "skin": 0xc3beb4,
				"hair": 0x2a2522, "stain": 0x4a3328}
		Look.ENEMY_B:
			return {"top": 0x4c5b6c, "top2": 0x3d4958, "legs": 0x3a4251, "shoe": 0xb7b2a8, "skin": 0xbfb9ad,
				"hair": 0x6e6a63, "stain": 0x3e2c26}
		Look.ENEMY_C:
			return {"top": 0x6b3535, "top2": 0x552a2a, "legs": 0x776b55, "shoe": 0x2c2420, "skin": 0xc8c1b3,
				"hair": 0x1f1b19, "stain": 0x3a2721}
		_:
			return {"top": 0x9c8f72, "top2": 0x82765d, "legs": 0x2f3035, "shoe": 0xc3beb4, "skin": 0xcbc6ba,
				"hair": 0x4a3a2c, "stain": 0x40302a}


static func _mesh(which: Look, part: String) -> ArrayMesh:
	var key := "%d/%s" % [which, part]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var box := _bounds(part)
	var lo: Vector3 = box[0]
	var hi: Vector3 = box[1]
	var size := Vector3i(((hi - lo) / VS).ceil()) + Vector3i(2, 2, 2)
	var g := VoxelGrid.new(size, VS, lo - Vector3.ONE * VS)
	var pal := _palette(which)
	for y in range(1, size.y - 1):
		for z in range(1, size.z - 1):
			for x in range(1, size.x - 1):
				var p := g.center(Vector3i(x, y, z))
				var c := _sculpt(which, part, p, pal, x, y, z)
				if c >= 0:
					g.set_voxel(x, y, z, VoxelMat.FABRIC, c)
	var mesh := VoxelMesher.build_mesh(g, shared_material())
	_mesh_cache[key] = mesh
	return mesh


static func _bounds(part: String) -> Array:
	match part:
		"torso": return [Vector3(-0.26, -0.12, -0.16), Vector3(0.26, 0.62, 0.3)]
		"head": return [Vector3(-0.14, -0.04, -0.15), Vector3(0.14, 0.3, 0.14)]
		"arm_l", "arm_r": return [Vector3(-0.08, -0.7, -0.08), Vector3(0.08, 0.06, 0.08)]
		"leg_l", "leg_r": return [Vector3(-0.09, -0.92, -0.16), Vector3(0.09, 0.04, 0.1)]
		"gun": return [Vector3(-0.04, -0.3, -0.06), Vector3(0.04, 0.06, 0.16)]
	return [Vector3(-0.1, -0.1, -0.1), Vector3(0.1, 0.1, 0.1)]


static func _h(x: int, y: int, z: int, s: int) -> float:
	return VoxelArt.hash3(x, y, z, s)


static func _sculpt(which: Look, part: String, p: Vector3, pal: Dictionary, x: int, y: int, z: int) -> int:
	var enemy := which != Look.PLAYER
	var n := _h(x, y, z, 3)
	match part:
		"torso":
			# pelvis/belt 0..0.12, chest up to 0.55, tapering to shoulders
			var t := clampf(p.y / 0.55, 0.0, 1.0)
			var half_w := lerpf(0.16, 0.22, smoothstep(0.1, 0.8, t))
			var half_d := lerpf(0.1, 0.12, t)
			if p.y > 0.5:
				half_w = lerpf(0.22, 0.12, (p.y - 0.5) / 0.08)
			if absf(p.x) < half_w and absf(p.z - 0.0) < half_d and p.y > -0.1 and p.y < 0.58:
				if p.y < 0.0:
					return pal["legs"]
				if not enemy:
					# scarf at the collar, strap diagonal across the chest
					if p.y > 0.46 and absf(p.x) < 0.14:
						return VoxelArt.jitter(pal["accent"], x, y, z, 0.06)
					if p.z < -0.06 and absf(p.x + (p.y - 0.25) * 0.75) < 0.04:
						return pal["strap"]
					if absf(p.x) < 0.02 and p.z < -0.08 and p.y < 0.45:
						return pal["top2"]
					return VoxelArt.jitter(pal["top"], x, y, z, 0.05)
				# torn shirt: ragged holes show skin, dark stains
				if n > 0.9 and p.y > 0.05:
					return pal["skin"]
				if _h(x / 2, y / 2, z, 9) > 0.88:
					return pal["stain"]
				return VoxelArt.jitter(pal["top"] if p.y > 0.08 or n > 0.3 else pal["top2"], x, y, z, 0.07)
			if not enemy and p.z > 0.1 and p.z < 0.26 and absf(p.x) < 0.15 and p.y > 0.14 and p.y < 0.5:
				return VoxelArt.jitter(pal["pack"], x, y, z, 0.05) if p.y < 0.46 else pal["strap"]
			return -1
		"head":
			var q := Vector3(p.x / 0.105, (p.y - 0.12) / 0.14, p.z / 0.115)
			if q.length() > 1.0:
				if p.y > -0.03 and p.y < 0.06 and absf(p.x) < 0.05 and absf(p.z) < 0.05:
					return pal["skin"]   # neck
				return -1
			if not enemy and p.y > 0.14 and (p.y > 0.2 or q.length() > 0.8):
				return VoxelArt.jitter(pal["accent"], x, y, z, 0.05)   # beanie
			if p.y > 0.16 or (p.z > 0.02 and p.y > 0.0) or (enemy and q.length() > 0.85 and p.y > 0.06 and n > 0.25):
				return VoxelArt.jitter(pal["hair"], x, y, z, 0.08)
			if p.z < -0.07 and absf(absf(p.x) - 0.045) < 0.02 and absf(p.y - 0.13) < 0.02:
				return 0x111111 if not enemy else 0x2a2020
			return VoxelArt.jitter(pal["skin"], x, y, z, 0.03)
		"arm_l", "arm_r":
			var len := 0.66 if enemy else 0.6
			if p.y < -len or Vector2(p.x, p.z).length() > 0.065:
				return -1
			if p.y < -len + 0.1:
				return pal["skin"]
			if enemy and p.y < -0.3 and n > 0.5:
				return pal["skin"]   # bare, ragged forearms
			return VoxelArt.jitter(pal["top"], x, y, z, 0.05)
		"leg_l", "leg_r":
			if p.y < -0.84:
				if p.z < 0.08 and p.z > -0.14 and absf(p.x) < 0.07:
					return pal["shoe"]
				return -1
			var r := lerpf(0.06, 0.08, clampf((p.y + 0.84) / 0.84, 0.0, 1.0))
			if Vector2(p.x, p.z).length() < r:
				if enemy and p.y < -0.6 and n > 0.85:
					return pal["skin"]
				return VoxelArt.jitter(pal["legs"], x, y, z, 0.05)
			return -1
		"gun":
			# arm space: barrel along -Y past the hand, grip along +Z (down when aiming)
			if absf(p.x) < 0.025 and p.y > -0.26 and p.y < 0.04 and p.z > -0.04 and p.z < 0.03:
				return 0x1b1c1e if p.y > -0.24 else 0x34363a
			if absf(p.x) < 0.025 and p.y > -0.06 and p.y < 0.03 and p.z >= 0.03 and p.z < 0.13:
				return 0x2a2420
			return -1
	return -1
