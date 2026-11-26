extends Node3D
## Exp 011: a capture stage for comparing figures side by side (Eli and
## humanoid archetypes), for tools/capture.sh. Args:
##   --who=eli,brute:0,brute:3,psycho:9   figures left to right (kind:seed)
##   --anim=idle|walk|run|attack|hit|die   --pose=x (freeze attack/hit at
##   progress x, die at seconds x)   --dormant=bang|tap|sway|stare
##   --yaw=deg --pitch=deg --dist=m --ty=m --gap=m --duck=0..1 --night

var rigs: Array = []
var anim := "idle"
var pose := -1.0
var dormant := ""
var _t := 0.0
var _dorm := []


func _ready() -> void:
	var who := "eli,brute:0"
	var yaw := 30.0
	var pitch := 8.0
	var dist := 6.5
	var ty := 1.2
	var gap := 0.25
	var duck := -1.0
	var night := false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"who": who = v
			"anim": anim = v
			"pose": pose = float(v)
			"dormant": dormant = v
			"yaw": yaw = float(v)
			"pitch": pitch = float(v)
			"dist": dist = float(v)
			"ty": ty = float(v)
			"gap": gap = float(v)
			"duck": duck = float(v)
			"night": night = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.215, 0.235) if not night else Color(0.035, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84) if not night else Color(0.3, 0.38, 0.6)
	env.ambient_light_energy = 0.55 if not night else 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	VoxelRig.look_material(false).set_shader_parameter("night", 1.0 if night else 0.0)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(28.0), 0.0)
	key.shadow_enabled = true
	key.light_energy = 1.15 if not night else 0.18
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-120.0), 0.0)
	fill.light_color = Color(0.62, 0.72, 0.9)
	fill.light_energy = 0.35
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 40.0
	disc.bottom_radius = 40.0
	disc.height = 0.02
	floor_mi.mesh = disc
	floor_mi.position.y = -0.01
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.38, 0.41)
	floor_mi.material_override = fm
	add_child(floor_mi)
	# a 2.1 m door frame marker behind the figures (a height reference)
	var widths := []
	for w in who.split(","):
		var r: VoxelRig
		if w == "eli":
			r = EliRig.new(0)
			widths.append(0.55)
		else:
			var p := w.split(":")
			r = HumanoidLooks.make_rig(p[0], int(p[1]) if p.size() > 1 else 0)
			widths.append(1.1 if p[0] == "brute" else 0.6)
		add_child(r)
		var a := HumanoidLooks.archetype(w.split(":")[0])
		if a != null and r is HumanoidRig:
			a.extras(r)
			if duck >= 0.0 and "duck_hold" in r:
				r.set("duck_hold", duck)
		rigs.append(r)
	var total := 0.0
	for w in widths:
		total += float(w) + gap
	var x := -total * 0.5
	for i in rigs.size():
		x += (float(widths[i]) + gap) * 0.5
		(rigs[i] as Node3D).position.x = x
		(rigs[i] as Node3D).set_meta("yaw", 0.0)
		x += (float(widths[i]) + gap) * 0.5
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var target := Vector3(0.0, ty, 0.0)
	cam.position = target + Vector3(sin(yr) * cos(pr), sin(pr), -cos(yr) * cos(pr)) * dist
	cam.look_at(target, Vector3.UP)
	cam.current = true


func _process(delta: float) -> void:
	_t += delta
	var sp: float = {"idle": 0.0, "walk": 1.25, "run": 3.3}.get(anim, 0.0)
	for r: VoxelRig in rigs:
		r.speed = sp
		if r is HumanoidRig:
			var h := r as HumanoidRig
			h.preview_dir = Vector2(0.0, -1.0)
			if anim == "die":
				h.collapse(delta, pose if pose >= 0.0 else fmod(_t, 4.0), Vector3.LEFT, 0.0)
				continue
			if anim == "attack":
				h.swing = 1.0 - pose if pose >= 0.0 else 1.0 - fmod(_t, 1.4) / 0.7
				h.swing = clampf(h.swing, 0.0, 1.0)
			if anim == "hit":
				h.stagger = 1.0 - pose if pose >= 0.0 else maxf(1.0 - fmod(_t, 1.6) * 3.5, 0.0)
			h.animate(delta)
			if dormant != "":
				_pose_dormant(h, delta)
		else:
			r.animate(delta)


func _pose_dormant(h: HumanoidRig, delta: float) -> void:
	var i := rigs.find(h)
	while _dorm.size() <= i:
		_dorm.append([DormantMind.new(), AIEnemy.new()])
	var m: DormantMind = _dorm[i][0]
	var e: AIEnemy = _dorm[i][1]
	e.rig = h
	m.state = dormant
	m.set("_lean", 0.5 + 0.5 * sin(_t * 2.4))
	m.set("_flick", maxf(sin(_t * 5.0), 0.0))
	m.set("_t", _t)
	m.pose(e, delta)


func _exit_tree() -> void:
	for d in _dorm:
		(d[1] as Node).free()
