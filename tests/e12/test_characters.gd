extends "res://tests/test_case.gd"
## Experiment 012 (C): characters, the flashlight, graphics presets, the font.
##   - the humanoid stress harness (every kind, every state, lag spikes,
##     deaths mid-animation, background looks landing) finds no detached
##     part, NaN or stretched bone; an idle runner's arms stay on;
##   - Eli's collar leaves the neck room; in a running game a person whose
##     look isn't built wears a stand-in and never builds on the spot;
##   - one flashlight beam at night: none without it, one in hand, none
##     after switching away, one after save and load;
##   - presets persist and apply; the UI font is Inter.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_e12_characters.dat"
const SETTINGS := "user://test_e12_settings.cfg"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	if GameSettings.path_override == SETTINGS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
		GameSettings.path_override = ""
		GameSettings.reset()
	await super.cleanup()


func test_stress_harness_finds_no_separation() -> void:
	var rigs := []
	for k in ["psycho", "runner", "brute", "bomber"]:
		for i in 2:
			var r: HumanoidRig = add(HumanoidLooks.make_rig(k, i * 5))
			r.position = Vector3(rigs.size() * 2.5, 0.0, 0.0)
			rigs.append(r)
	await frames(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var res := RigIntegrity.stress(rigs, 900, rng)
	print("    stress: ", res)
	check(int(res["deaths"]) > 0 and int(res["attacks"]) > 0 and int(res["hits"]) > 0 and int(res["spikes"]) > 0,
		"the run covered deaths, attacks, hits and lag spikes")
	check_eq(int(res["bad"]), 0, "no broken rig in any frame (worst %s)" % str(res["worst"]))
	check(not bool(res["worst"]["nan"]), "no NaN")


func test_idle_runner_and_shoulder_tics_keep_the_arms_on() -> void:
	var r: HumanoidRig = add(HumanoidLooks.make_rig("runner", 2))
	var p: HumanoidRig = add(HumanoidLooks.make_rig("psycho", 4))
	p.position.x = 3.0
	await frames(1)
	for f in 600:                         # 10 s idle; the psycho shrugs every 30 frames
		if f % 30 == 0:
			p._tic = "shoulder"
			p._tic_t = 0.0
			p._tic_k = 1.0
			p._tic_next = 99.0
		r.animate(1.0 / 60.0)
		p.animate(1.0 / 60.0)
	var mr := RigIntegrity.measure(r)
	var mp := RigIntegrity.measure(p)
	check(float(mr["sep"]) < 0.05, "an idle runner's arms stay on (%.3f m off)" % float(mr["sep"]))
	check(float(mp["sep"]) < 0.05, "20 shoulder tics leave the arms on (%.3f m off)" % float(mp["sep"]))
	# and a corpse keeps them too
	for f in 90:
		p.collapse(1.0 / 60.0, f / 60.0, Vector3.RIGHT, 0.0)
	check(RigIntegrity.intact(RigIntegrity.measure(p)), "the collapsed body holds together")


func test_eli_collar_leaves_the_neck_room() -> void:
	var g: Dictionary = EliSculpt._voxelize("chest", 0.0, EliSculpt.VARIANTS[2])
	var n: Vector3i = g["n"]
	var i0: Vector3i = g["i0"]
	var col: PackedInt32Array = g["col"]
	var inside := 0
	for y in n.y:
		for z in n.z:
			for x in n.x:
				if col[(y * n.z + z) * n.x + x] < 0:
					continue
				var p := Vector3(i0 + Vector3i(x, y, z)) * EliSculpt.VS
				if p.y > EliSculpt.NECK_HOLE_Y + 0.02 and p.y < 0.5 and Vector2(p.x, p.z - 0.015).length() < 0.035:
					inside += 1
	check_eq(inside, 0, "nothing of the chest stands inside the neck opening")
	# the head's neck below the collar top is thinner than the opening
	var h: Dictionary = EliSculpt._voxelize("head", 0.0, EliSculpt.VARIANTS[2])
	var hn: Vector3i = h["n"]
	var h0: Vector3i = h["i0"]
	var hc: PackedInt32Array = h["col"]
	var widest := 0.0
	for y in hn.y:
		for z in hn.z:
			for x in hn.x:
				if hc[(y * hn.z + z) * hn.x + x] < 0:
					continue
				var p := Vector3(h0 + Vector3i(x, y, z)) * EliSculpt.VS
				if p.y < 0.005 and p.y > -0.05:
					widest = maxf(widest, Vector2(p.x, p.z - 0.016).length())
	check(widest < 0.05, "the tucked neck fits the opening with room to turn (%.3f m)" % widest)


func test_unbuilt_look_never_builds_on_the_spot() -> void:
	var host: Node3D = add(Node3D.new())
	HumanoidLooks.warm("bomber", host, 1)         # a running game (its roster warms looks)
	check(HumanoidLooks.defer_builds(), "a running game defers builds")
	var a := HumanoidLooks.archetype("bomber")
	HumanoidSculpt.meshes(a.look(0), HumanoidRig.material_for(a.look(0)))   # one ready look
	var want := -1
	for i in a.variety():
		if not HumanoidSculpt.is_ready(str(a.look(i)["key"])):
			want = i
			break
	if want < 0:
		skip("every bomber look is already built")
		return
	var before := HumanoidSculpt.sync_builds
	var r: HumanoidRig = add(HumanoidLooks.make_rig("bomber", want))
	await frames(1)
	check_eq(HumanoidSculpt.sync_builds, before, "nothing built on the spot")
	check(not r.pending_look.is_empty() and str(r.look_data["key"]) != str(a.look(want)["key"]), "it wears a stand-in")
	HumanoidSculpt.finish_background()            # the urgent background build lands
	await frames(1)
	r.animate(1.0 / 60.0)
	check_eq(str(r.look_data["key"]), str(a.look(want)["key"]), "then its own look")
	check(RigIntegrity.intact(RigIntegrity.measure(r)), "and holds together")
	check(r.get("pack_extras") != null and is_instance_valid(r.pack_extras.get("pack")), "the pack moved onto the new body")


func test_one_flashlight_beam() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	s.total_minutes = 23.0 * 60.0
	await frames(4)
	var bar: Node = g.bar
	check(not g.player.auto_beam, "the game hands the beam to the flashlight")
	check_eq(int(bar.beams()["count"]), 0, "night, no flashlight in hand: no cone")
	check(g.player.self_light.visible, "the ambient night light stays")
	s.inventory.add("flashlight", 1)
	Hotbar.fill(bar.bar(), s)
	var slot := Hotbar.slot_of(bar.bar(), "flashlight")
	check(slot >= 0, "the flashlight is on the bar")
	bar.select(slot)
	await frames(2)
	check_eq(int(bar.beams()["count"]), 1, "flashlight in hand: one beam")
	check(g.player.rig.carry, "held out")
	var aim: Vector3 = g.player.aim_point
	var fwd := -(bar.light as SpotLight3D).global_transform.basis.z
	check(fwd.length() > 0.9, "the beam points somewhere (%s, aim %s)" % [str(fwd), str(aim)])
	bar.select(0)
	await frames(2)
	check_eq(int(bar.beams()["count"]), 0, "another item: no beam")
	bar.select(slot)
	await frames(2)
	check_eq(int(bar.beams()["count"]), 1, "back in hand: one beam")
	bar.use("flashlight")
	check_eq(int(bar.beams()["count"]), 0, "switched off")
	bar.use("flashlight")
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(3)
	var h: Node = await _boot("continue")
	h.debug_state().total_minutes = 23.0 * 60.0
	await frames(4)
	check_eq(h.bar.in_hand(), "flashlight", "the flashlight is still in hand after loading")
	check_eq(int(h.bar.beams()["count"]), 1, "one beam after loading")


func test_presets_persist_and_apply() -> void:
	GameSettings.path_override = SETTINGS
	GameSettings.reset()
	check_eq(GraphicsQuality.preset(), "high", "High by default")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ssao_enabled = true
	env.environment.glow_enabled = true
	add(env)
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = true
	add(lamp)
	GraphicsQuality.set_preset("low")
	await frames(2)
	var vp := tree.root
	check_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "Low: no MSAA")
	check(absf(vp.scaling_3d_scale - 0.75) < 0.01, "Low: 75 % render scale")
	check(not env.environment.ssao_enabled and not env.environment.glow_enabled, "Low: no SSAO or glow")
	check(not lamp.shadow_enabled, "Low: lamps without shadows")
	GameSettings.reset()                       # read back from the file
	check_eq(GraphicsQuality.preset(), "low", "the choice persists")
	GraphicsQuality.set_preset("ultra")
	check_eq(vp.msaa_3d, Viewport.MSAA_8X, "Ultra: 8x MSAA")
	check(env.environment.ssao_enabled and lamp.shadow_enabled, "Ultra: SSAO and lamp shadows back")
	var late := OmniLight3D.new()
	late.shadow_enabled = true
	GraphicsQuality.set_preset("low")
	add(late)
	await frames(2)
	check(not late.shadow_enabled, "a light added later gets the preset too")
	GraphicsQuality.set_show_fps(true)
	await frames(2)
	var rt := tree.root.get_node_or_null("GraphicsRuntime")
	check(rt != null and (rt.get_node("Fps") as Control).visible, "the frame-rate overlay shows")
	GraphicsQuality.set_show_fps(false)
	GraphicsQuality.set_preset("high")
	check_eq(vp.msaa_3d, Viewport.MSAA_4X, "High: the project's 4x MSAA")


func test_the_ui_font_is_inter() -> void:
	var f := UiTheme.font("regular")
	check(f is FontFile and (f as FontFile).resource_path.ends_with("Inter-Regular.woff2"), "Inter Regular")
	check(f.get_font_name().begins_with("Inter"), "named Inter (%s)" % f.get_font_name())
	check(FileAccess.file_exists("res://assets/fonts/inter/LICENSE.txt"), "with its licence")
	check(FileAccess.file_exists("res://assets/fonts/pixel_operator/PixelOperator.ttf"), "the pixel font stays in the project")
	var l := UiTheme.make_label("Supplies")
	check((l.get_theme_font("font") as Font).get_font_name().begins_with("Inter"), "labels use it")


func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 120
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g
