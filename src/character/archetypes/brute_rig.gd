extends HumanoidRig
## Experiment 011: how a brute moves (src/character/archetypes/brute.gd).
## On top of the shared gait (HumanoidRig): a slow, heavy, lumbering walk
## whose weight rolls from foot to foot (the pelvis shifts over the stance
## leg, the upper body rolls with it, every footfall sinks in); a run that
## is a ponderous charge (leaning in, the club coming up); idle heavy
## breathing with the shoulders rising; turns that the head leads and the
## bulk follows; a big overhead (or sweeping) blow with a long wind-up; hits
## that barely rock him; a collapse onto the knees, a sway, then a heavy
## fall forward onto his face.
##
## Doorways: he stands ~2.4 m, a door leaves 2.1 m. He is always stooped
## (style "hunch"), and ducks lower when a lintel is right ahead or above
## (a lookup in the parent enemy's HouseWorld grid, so it works at home and
## in POIs; nothing without a world, e.g. in the showroom).
##
## The club (attach_club, from the archetype's extras()) is a small voxel
## model at the people's 1.5 cm voxel size: a nailed plank or a taped pipe.

const E := preload("res://src/character/eli_sculpt.gd")
const CVS := 0.015

static var _club_meshes := {}
static var _mat: ShaderMaterial
static var _mat_frame := -1

var duck := 0.0                       ## 0 .. 1: ducking under a lintel
var duck_hold := -1.0                 ## >= 0: forced duck amount (showroom, tests)
var club: Node3D
var _duck_goal := 0.0
var _probe_t := 0.0
var vscale := 1.0                     ## the look's "voxel_scale": the rig's own uniform scale

var _club_free := false
var _club_rest := Transform3D.IDENTITY
var _club_from := Transform3D.IDENTITY
var _club_to := Transform3D.IDENTITY
var _club_t0 := 0.0

const KNEE_H := 0.075            ## kneeling: knee pivot height (m at k = 1)
const FALL_ANGLE := 1.5          ## how far he pitches forward (rad)
const TORSO_LIE := -0.05         ## torso against the thighs when lying
const LIE_LIFT := 0.05           ## lying: body lifted (m at k = 1) so the belly rests on the ground


func _ready() -> void:
	vscale = float(look_data.get("voxel_scale", 1.0))
	scale = Vector3.ONE * vscale
	super()
	_after_bones()


## His material on every part; Exp 012: also once his own look replaces a
## stand-in (the scale, and the club of his look).
func _after_bones() -> void:
	vscale = float(look_data.get("voxel_scale", 1.0))
	if not dead:
		scale = Vector3.ONE * vscale
	for p in parts:
		p.material_override = brute_material()
	if club != null and is_instance_valid(club):
		var mi := club.get_node_or_null("Mesh") as MeshInstance3D
		if mi != null:
			mi.mesh = club_mesh(str(look_data.get("club", "plank")), material_for(look_data))


## The people's material with a deeper x-ray self-occlusion depth: a brute is
## over a metre deep with his arms and club in front of him, which the shared
## 0.55 m would light up through his own body. Its `night` follows the shared
## enemy material.
static func brute_material() -> ShaderMaterial:
	if _mat == null:
		_mat = HumanoidRig.enemy_material().duplicate() as ShaderMaterial
		var x := ShaderMaterial.new()
		x.shader = EnemyLooks.XRAY_SHADER
		x.set_shader_parameter("tint", Color(0.95, 0.5, 0.45, 0.32))
		x.set_shader_parameter("self_depth", 1.15)
		_mat.next_pass = x
	var f := Engine.get_process_frames()
	if f != _mat_frame:
		_mat_frame = f
		var n: Variant = HumanoidRig.enemy_material().get_shader_parameter("night")
		_mat.set_shader_parameter("night", float(n) if n != null else 0.0)
	return _mat


# --- the club ----------------------------------------------------------------------------

## Builds the club in the right hand (once) and returns it.
func attach_club() -> Node3D:
	if club != null and is_instance_valid(club):
		return club
	if hand_r == null:
		return null
	var kind := str(look_data.get("club", "plank"))
	club = Node3D.new()
	club.name = "Club"
	var hs: float = float(body.get("hand", 1.0))
	# through the fist, across the fingers; the head end forward and down
	club.position = Vector3(-0.018, -0.1, 0.0) * hs
	club.rotation = Vector3(-0.62, 0.0, 0.12)
	club.scale = Vector3.ONE * 0.82            # ~1 m once the rig's scale is applied
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = club_mesh(kind, material_for(look_data))
	mi.material_override = brute_material()
	club.add_child(mi)
	hand_r.add_child(club)
	_club_rest = club.transform
	parts.append(mi)                  # flashes, fades and follows the night like the body
	return club


## The club's voxel mesh (cached per kind): its grip at the origin, the
## head end toward -Z.
static func club_mesh(kind: String, material: Material) -> ArrayMesh:
	if _club_meshes.has(kind):
		return _club_meshes[kind]
	var lo := Vector3(-0.07, -0.07, -1.02)
	var hi := Vector3(0.07, 0.07, 0.14)
	var i0 := Vector3i(floori(lo.x / CVS) - 1, floori(lo.y / CVS) - 1, floori(lo.z / CVS) - 1)
	var i1 := Vector3i(ceili(hi.x / CVS) + 1, ceili(hi.y / CVS) + 1, ceili(hi.z / CVS) + 1)
	var n := i1 - i0 + Vector3i.ONE
	var col := PackedInt32Array()
	col.resize(n.x * n.y * n.z)
	col.fill(-1)
	for y in range(1, n.y - 1):
		for z in range(1, n.z - 1):
			for x in range(1, n.x - 1):
				var ix := i0.x + x
				var iy := i0.y + y
				var iz := i0.z + z
				var c := _club_voxel(kind, Vector3(ix, iy, iz) * CVS, ix, iy, iz)
				col[(y * n.z + z) * n.x + x] = c
	var g := {"n": n, "i0": i0, "col": col, "verts": 0}
	E._shade(g)
	var m := E.arrays_to_mesh(E.grid_arrays(g), material)
	_club_meshes[kind] = m
	return m


## Colour of the club voxel at p (-1: empty).
static func _club_voxel(kind: String, p: Vector3, x: int, y: int, z: int) -> int:
	var along := -p.z                                   # 0 at the grip, ~1 at the head
	if kind == "pipe":
		# a length of steel pipe with a heavy elbow fitting, the grip taped
		var r := Vector2(p.x, p.y).length()
		var shaft := r < 0.028 and along > -0.1 and along < 0.86
		var fit := r < 0.046 and along > 0.8 and along < 0.95
		var cap := r < 0.04 and along >= 0.95 and along < 0.99
		if not (shaft or fit or cap):
			return -1
		if shaft and r < 0.015 and (along < -0.08 or along > 0.84):
			return -1                                   # the bore
		if along < 0.2 and shaft:
			var tape := 0x2a2a2c if posmod(z, 3) != 0 else 0x3a3a3e
			return E._j(tape, x, y, z, 0.05)
		var steel := E._mix(0x6a6e72, 0x5a4434, E._vn(x, y, z, 3, 13) * 0.6)    # rust in patches
		if fit or cap:
			steel = E._sc(0x50545a, 0.95 if posmod(z, 2) == 0 else 1.05)
			if absf(along - 0.875) < 0.01:
				return 0x3a3c40                                                 # thread
		return E._j(steel, x, y, z, 0.05)
	# a 2x4 plank, nails through the far end, a rag wrapped round the grip
	var ax := absf(p.x)
	var ay := absf(p.y)
	var head := smoothstep(0.55, 0.75, along)            # it thickens toward the end (a block nailed on)
	var hw := 0.024 + 0.012 * head
	var hh := 0.038 + 0.01 * head
	var plank := ax < hw and ay < hh and along > -0.09 and along < 0.98
	var nail := false
	if along > 0.72 and along < 0.95 and posmod(z, 4) == 0:
		var h := E._h(x / 3, 0, z, 41)
		if h > 0.45 and ax < 0.006 + 0.004 * float(h > 0.7) and ay < hh + 0.035 and ay >= hh:
			nail = true                                  # through and out the sides
		var h2 := E._h(z, y / 3, 0, 43)
		if h2 > 0.55 and ay < 0.006 and ax < hw + 0.03 and ax >= hw:
			nail = true
	var rag := along > -0.05 and along < 0.2 and ax < 0.034 and ay < 0.048
	if not (plank or nail or rag):
		return -1
	if nail:
		return 0x9a9ca0 if (ax > hw + 0.02 or ay > hh + 0.025) else 0x6a6c70
	if rag and not plank or rag and (ax > 0.024 - CVS or ay > 0.038 - CVS):
		var cloth := E._mix(0x8a7a5c, 0x3a3026, E._vn(x, y, z, 2, 17) * 0.6)
		return E._j(cloth if posmod(z + y, 4) != 0 else E._sc(cloth, 0.8), x, y, z, 0.05)
	# wood: grain along the plank, darker end grain, grime toward the head
	var w := E._mix(0x8a6440, 0x6a4a30, E._vn(x, y, z / 4, 2, 19))
	if posmod(x + roundi(E._h(0, y, z / 6, 23) * 2.0), 3) == 0:
		w = E._sc(w, 0.9)
	if along > 0.95 or along < -0.08:
		w = E._sc(w, 0.75)
	w = E._mix(w, 0x3a2a22, smoothstep(0.6, 1.0, along) * 0.35 * E._vn(x, y, z, 3, 29))
	return E._j(w, x, y, z, 0.04)


# --- posture and gait ----------------------------------------------------------------------

func _style_pose(delta: float) -> void:
	brute_material()                  # keeps its night in step
	if _club_free:
		_club_back()
	var idle := 1.0 - _move
	var top := st("walk_top")
	var run := smoothstep(top, top + 1.5, maxf(speed, 0.0))
	var ph := TAU * _phase
	# weight transfer: the pelvis shifts over the stance leg, the upper body rolls with it
	var roll := sin(ph) * _move * (1.0 - 0.5 * run)
	pelvis.position.x -= 0.03 * _k * roll
	pelvis.rotation.z += 0.05 * roll
	torso.rotation.z += 0.1 * roll
	head.rotation.z -= 0.06 * roll
	# every footfall sinks in (just after each heel strike)
	var f := fposmod(_phase * 2.0, 1.0)
	var thud := exp(-f * 7.0) * minf(f * 30.0, 1.0) * _move
	pelvis.position.y -= 0.035 * _k * thud
	torso.rotation.x -= 0.05 * thud
	head.rotation.x += 0.035 * thud
	# the charge: leaning in, head up to see, the club coming up, the free arm pumping wide
	if run > 0.0:
		torso.rotation.x -= 0.22 * run
		head.rotation.x += 0.18 * run
		arm_r.rotation = arm_r.rotation.lerp(Vector3(0.9 + 0.15 * sin(ph), 0.0, 0.3), run * 0.7)
		forearm_r.rotation.x = lerpf(forearm_r.rotation.x, 1.1, run * 0.7)
		arm_l.rotation.z -= 0.25 * run
	# turns: the head leads, the bulk follows (the body lags the rig's yaw)
	var tr := clampf(_yaw_rate * 0.1, -0.4, 0.4)
	torso.rotation.y -= tr
	pelvis.rotation.y -= tr * 0.4
	head.rotation.y += tr * 1.2
	# breathing: slow and heavy, the shoulders rise and fall
	var b := sin(_t * 1.3) * 0.5 + 0.5
	var bk := 0.4 + 0.6 * idle
	arm_l.position = _mx(_shoulder, -1.0) + Vector3(0.0, 0.016 * _k * b * bk, 0.0)
	arm_r.position = _shoulder + Vector3(0.0, 0.016 * _k * b * bk, 0.0)
	torso.rotation.x += 0.035 * b * idle
	head.rotation.x -= 0.03 * b * idle
	breathe_chest(Vector3(1.0 + 0.018 * b * bk, 1.0, 1.0 + 0.03 * b * bk))     # Exp 012: the mesh, not the bone
	# under a lintel: stoop lower, knees bent
	_door_probe(delta)
	if duck_hold >= 0.0:
		duck = duck_hold
	else:
		duck = move_toward(duck, _duck_goal, delta * 2.5)
	if duck > 0.0:
		var e := duck * duck * (3.0 - 2.0 * duck)
		torso.rotation.x -= 0.38 * e
		head.rotation.x += 0.3 * e
		pelvis.position.y -= 0.12 * _k * e
		pelvis.position.z += 0.06 * _k * e


## Looks for a lintel ahead or overhead in the enemy's world grid (a solid
## voxel at head height with an opening under it), ~10 times a second.
func _door_probe(delta: float) -> void:
	_probe_t -= delta
	if _probe_t > 0.0:
		return
	_probe_t = 0.1
	_duck_goal = 0.0
	if not is_inside_tree():
		return
	var host := get_parent()
	var w: Variant = host.get("world") if host != null else null
	if not (w is HouseWorld) or (w as HouseWorld).grid == null:
		return
	var hw := w as HouseWorld
	var g: VoxelGrid = hw.grid
	var gt := global_transform
	var fwd := -gt.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var base := hw.to_local(gt.origin)
	var lf := hw.global_transform.basis.inverse() * fwd
	for i in 11:
		var d := -0.3 + 0.1 * i                         # from just behind him to ahead of his head (walls are 0.2 m)
		var at := base + lf * d
		var lintel := false
		for hgt in [2.0, 2.2, 2.35]:
			var c := g.cell_of(at + Vector3(0.0, hgt, 0.0))
			if g.get_mat(c.x, c.y, c.z) != VoxelMat.AIR:
				lintel = true
				break
		if not lintel:
			continue
		var lc := g.cell_of(at + Vector3(0.0, 1.3, 0.0))
		if g.get_mat(lc.x, lc.y, lc.z) == VoxelMat.AIR:
			_duck_goal = maxf(_duck_goal, 1.0 - 0.6 * clampf(d - 0.3, 0.0, 1.0))


# --- attack, hit, death --------------------------------------------------------------------

## A big blow with a long wind-up: overhead (rears back, the club high over
## the shoulder, then slams down with his whole weight) or a sweep (twists
## away, then swings the club across). Impact near p 0.45 .. 0.5.
func _attack_pose(p: float) -> void:
	var up := smoothstep(0.0, 0.4, p)
	var hit := smoothstep(0.38, 0.5, p)
	var back := smoothstep(0.62, 1.0, p)
	var w := 1.0 - back
	if club != null and not _club_free:
		# the club swings in line with the arm (at rest it hangs forward from the fist)
		club.rotation.x = lerpf(_club_rest.basis.get_euler().x, -1.3, smoothstep(0.0, 0.25, p) * w)
	if str(style.get("attack", "overhead")) == "swipe":
		arm_r.rotation = arm_r.rotation.lerp(Vector3(lerpf(lerpf(0.2, 0.6, up), 1.6, hit), 0.0,
			lerpf(lerpf(0.2, 1.35, up), -0.35, hit)), w)
		forearm_r.rotation = forearm_r.rotation.lerp(Vector3(lerpf(lerpf(0.2, 0.9, up), 0.25, hit), 0.0, 0.0), w)
		arm_l.rotation = arm_l.rotation.lerp(Vector3(lerpf(0.5 * up, 0.2, hit), 0.0, lerpf(-0.6 * up, -0.3, hit)), w)
		torso.rotation.y += (-0.6 * up + 1.25 * hit) * w
		pelvis.rotation.y += (-0.2 * up + 0.4 * hit) * w
		torso.rotation.x += (0.12 * up - 0.4 * hit) * w
		head.rotation.y += (0.4 * up - 0.7 * hit) * w          # keeps his eyes on the target
		pelvis.position.y -= (0.03 * up + 0.08 * hit) * _k * w
		return
	var ux := lerpf(lerpf(0.2, 3.05, up), 2.2, hit)
	var fx := lerpf(lerpf(0.3, 1.25, up), 0.15, hit)
	arm_r.rotation = arm_r.rotation.lerp(Vector3(ux, 0.0, lerpf(lerpf(0.2, 0.42, up), 0.12, hit)), w)
	forearm_r.rotation = forearm_r.rotation.lerp(Vector3(fx, 0.0, 0.0), w)
	# the free arm comes up for balance, then swings down and back with the blow
	arm_l.rotation = arm_l.rotation.lerp(Vector3(lerpf(lerpf(0.1, 1.1, up), -0.35, hit), 0.0, -0.3), w)
	forearm_l.rotation.x = lerpf(forearm_l.rotation.x, lerpf(0.9 * up, 0.3, hit), w)
	torso.rotation.x += (0.42 * up - 0.75 * hit) * w
	torso.rotation.y += (-0.3 * up + 0.25 * hit) * w
	torso.rotation.z += (0.08 * up - 0.06 * hit) * w
	head.rotation.x += (-0.25 * up + 0.55 * hit) * w
	pelvis.position.y -= (0.02 * up + 0.13 * hit) * _k * w
	pelvis.position.z += (0.04 * up - 0.08 * hit) * _k * w


## A hit barely rocks him: a grunt, the head snaps a little, a half step of sway.
func _hit_pose(k: float) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	var s := _hit_side
	torso.rotation.x += 0.13 * e
	torso.rotation.z += 0.07 * s * e
	torso.rotation.y += 0.06 * s * e
	head.rotation.x += 0.2 * e
	head.rotation.z += 0.12 * s * e
	pelvis.position.y -= 0.02 * e * _k
	arm_l.rotation.z -= 0.1 * e
	arm_r.rotation.z += 0.1 * e


## The collapse: the knees give and he drops onto them with a thud (t < 0.4 s),
## letting go of the club; sways there with his head hanging (0.4 .. 0.7),
## then falls forward onto his face, pivoting on the knees (0.7 .. 1.15),
## and lies still. Always forward (the shot's `axis` only tips him a little
## sideways).
func collapse(delta: float, t: float, axis: Vector3, yaw: float) -> void:
	if pelvis == null:
		return
	if not dead:
		dead = true
		_coll_bend = -1.0 if _rng.randf() < 0.5 else 1.0
		duck = 0.0
		_club_back()
	_coll_t = t
	_sync_night()
	_rest_pose()                    # Exp 012: every bone at its rest offset first
	breathe_chest(Vector3.ONE)
	brute_material()
	var drop := clampf(t / 0.38, 0.0, 1.0)
	drop = drop * drop
	var tb := maxf(t - 0.38, 0.0)
	var bounce := 0.05 * sin(tb * 16.0) * exp(-tb * 9.0) * float(t > 0.38)
	var hold := smoothstep(0.38, 0.7, t)
	var fall := clampf((t - 0.7) / 0.45, 0.0, 1.0)
	fall = fall * fall
	var tl := maxf(t - 1.15, 0.0)
	var settle := 0.05 * sin(tl * 14.0) * exp(-tl * 10.0) * float(t > 1.15)
	# kneeling: the knee on the ground a little ahead, the thigh near upright,
	# the shin flat behind; the pelvis drops straight down onto it
	var kh := KNEE_H * _k
	var a := 0.18                                       # thigh forward of vertical
	var zp := -0.1 * _k
	var y_kneel := kh - _hip.y + cos(a) * _th
	var py := lerpf(_pelvis_y, y_kneel, drop) - bounce * _k
	pelvis.position = Vector3(0.0, py, zp * drop)
	var prx := 0.12 * drop * (1.0 - fall)
	pelvis.rotation = Vector3(prx, 0.0, 0.05 * _coll_bend * hold * (1.0 - fall))
	var ang := (FALL_ANGLE + settle) * fall
	for s: float in [-1.0, 1.0]:
		var th := leg_l if s < 0.0 else leg_r
		var sh := shin_l if s < 0.0 else shin_r
		var ft := foot_l if s < 0.0 else foot_r
		var ta := a * drop
		th.rotation = Vector3(ta - prx, 0.0, s * 0.06 * drop)
		# the shin folds back flat; while he topples it stays on the ground (counter-rotated)
		sh.rotation = Vector3((-PI * 0.5 - ta) * drop + ang, 0.0, 0.0)
		ft.rotation = Vector3(-1.25 * drop, 0.0, s * 0.3 * drop)
	# upper body: sags on the knees, head hanging; flattens out as he goes down
	var sway := sin(t * 5.0) * 0.06 * hold * (1.0 - fall)
	torso.rotation = Vector3(lerpf(-0.45 * drop - 0.15 * hold, TORSO_LIE, fall), 0.0, sway + 0.1 * _coll_bend * hold * (1.0 - fall))
	head.rotation = Vector3(lerpf(-0.25 * drop - 0.35 * hold, 0.25, fall), 1.1 * _coll_bend * fall, 0.3 * _coll_bend * fall)
	# arms hang, then fling out ahead and to the sides as he falls
	for s: float in [-1.0, 1.0]:
		var u := arm_l if s < 0.0 else arm_r
		var f := forearm_l if s < 0.0 else forearm_r
		var hd := hand_l if s < 0.0 else hand_r
		var lead := s == _coll_bend
		u.position = _mx(_shoulder, s)
		# one arm flung out past his head, the other trapped along his side
		u.rotation = Vector3(lerpf(0.05 + 0.1 * hold, 2.8 if lead else 0.15, fall), 0.0, s * lerpf(0.12, 0.5 if lead else 0.3, fall))
		f.rotation = Vector3(lerpf(0.15, 0.2 if lead else 0.1, fall), 0.0, 0.0)
		hd.rotation = Vector3(-0.1, 0.0, 0.0)
	# the whole body pivots forward over the knees
	var b0 := Basis(Vector3.UP, yaw)
	var side := b0.inverse() * axis
	var tip := clampf(side.x, -1.0, 1.0) * 0.1 * fall
	var bas := Basis(b0 * Vector3.RIGHT, -ang) * Basis(b0 * Vector3.FORWARD, tip) * b0
	var pivot := Vector3(0.0, kh, zp * drop - sin(a * drop) * _th)
	transform.basis = bas.scaled(Vector3.ONE * vscale)
	# (the pivot's offset goes into the pelvis: the rig's own position is the caller's)
	pelvis.position += bas.inverse() * (b0 * pivot - bas * pivot)
	position.y = LIE_LIFT * _k * fall * vscale
	_club_fall(t, yaw)
	if _flash > 0.0:
		set_flash(maxf(_flash - delta * 7.0, 0.0))


## The club leaves his hand as he goes down and drops beside him (it stays
## with the enemy: reparented next to the rig, freed and faded with it).
func _club_fall(t: float, yaw: float) -> void:
	if club == null or not is_instance_valid(club) or get_parent() == null:
		return
	if not _club_free:
		if t < 0.28:
			return
		_club_free = true
		var g := club.global_transform
		club.get_parent().remove_child(club)
		get_parent().add_child(club)
		club.global_transform = g
		_club_from = club.transform
		var sc := _club_from.basis.get_scale()
		var ry := yaw + _coll_bend * 0.9 + _rng.randf_range(-0.3, 0.3)
		var to_b := Basis(Vector3.UP, ry) * Basis(Vector3.FORWARD, _rng.randf_range(-0.4, 0.4))
		var o := _club_from.origin
		_club_to = Transform3D(to_b.scaled(sc), Vector3(o.x, 0.05 * vscale, o.z) + to_b * Vector3(0.0, 0.0, 0.12))
		_club_t0 = t
	var u := clampf((t - _club_t0) / 0.32, 0.0, 1.0)
	var e := u * u
	var bnc := 0.04 * absf(sin(maxf(t - _club_t0 - 0.32, 0.0) * 12.0)) * exp(-maxf(t - _club_t0 - 0.32, 0.0) * 8.0) * float(u >= 1.0)
	var sc2 := _club_from.basis.get_scale()
	var qb := Quaternion(_club_from.basis.orthonormalized()).slerp(Quaternion(_club_to.basis.orthonormalized()), minf(u * 1.3, 1.0))
	club.transform = Transform3D(Basis(qb).scaled(sc2), _club_from.origin.lerp(_club_to.origin, e) + Vector3(0.0, bnc, 0.0))


## Puts a dropped club back in his hand (the showroom replays the collapse).
func _club_back() -> void:
	if not _club_free or club == null or not is_instance_valid(club) or hand_r == null:
		_club_free = false
		return
	_club_free = false
	club.get_parent().remove_child(club)
	hand_r.add_child(club)
	club.transform = _club_rest
