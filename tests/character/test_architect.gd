extends "res://tests/test_case.gd"
## Exp 011: "the Architect" (an internal development name). His figure builds
## and animates (still, walk, controlled turn, observe, collapse); he stays
## hidden: not an EnemyDefs kind, never chosen by the invasion director or
## the roster, never named outside the developer tools; the F10 figure is
## not an enemy and makes no sound.

const Director := preload("res://src/game/invasion_director.gd")
const Roster := preload("res://src/game/enemy_roster.gd")

## The only source files that may name him: his own files, the showroom, the
## sculpt (comments on his components) and the F10 developer menu.
const ALLOWED := ["res://src/character/archetypes/architect.gd", "res://src/character/architect_identity.gd",
	"res://src/character/architect_rig.gd", "res://src/character/architect_figure.gd",
	"res://src/character/eli_showroom.gd", "res://src/character/humanoid_sculpt.gd", "res://src/ui/dev_menu.gd",
	"res://src/audio/audio_inbox.gd"]   # holds the recordings for him back (not player-facing)


func test_identity_and_look() -> void:
	var f := ArchitectIdentity.flags()
	check(f["hidden"] and not f["spawnable"] and f["silent"] and not f["hostile"], "hidden, not spawnable, silent, not hostile")
	check("observe" in ArchitectIdentity.ANIMATIONS and "turn" in ArchitectIdentity.ANIMATIONS, "his animation states")
	check(HumanoidLooks.has_humanoid(ArchitectIdentity.ID), "an archetype file")
	for i in HumanoidLooks.variety(ArchitectIdentity.ID):
		var l := HumanoidLooks.look(ArchitectIdentity.ID, i)
		check(not str(l["name"]).to_lower().contains("architect"), "the look's name doesn't carry the internal name")
		var m := HumanoidSculpt.meshes(l, HumanoidRig.material_for(l))
		check(m.size() == HumanoidSculpt.PARTS.size(), "look %d builds every part" % i)
		print("    %s: %d vertices, %.0f ms" % [l["name"], HumanoidSculpt.stats[l["key"]]["verts"], HumanoidSculpt.stats[l["key"]]["ms"]])


func test_rig_still_turn_observe() -> void:
	var r: ArchitectRig = add(HumanoidLooks.make_rig(ArchitectIdentity.ID, 0)) as ArchitectRig
	check(r != null, "his own rig")
	await frames(1)
	# stillness: the head barely moves over 6 s of idle
	var h0 := r.head.global_transform.basis.get_euler()
	var drift := 0.0
	for i in 180:
		r.animate(1.0 / 30.0)
		drift = maxf(drift, (r.head.global_transform.basis.get_euler() - h0).length())
	check(drift < 0.06, "still: no glances, no tics (head drift %.3f rad)" % drift)
	# a controlled turn: the head leads, then the body follows
	r.face_yaw = 1.5
	for i in 7:
		r.animate(1.0 / 30.0)
	var head_yaw := r.head.global_rotation.y
	check(head_yaw > 0.3 and r.rotation.y < 0.02, "the head leads (head %.2f, body %.2f)" % [head_yaw, r.rotation.y])
	for i in 150:
		r.animate(1.0 / 30.0)
	check(absf(r.rotation.y - 1.5) < 0.05, "then the body comes round (%.2f)" % r.rotation.y)
	# observe: the hands go behind the back
	r.observe = true
	for i in 90:
		r.animate(1.0 / 30.0)
	var back := r.global_transform.basis.z
	var hand := r.hand_l.global_position - r.global_position
	check(hand.dot(back) > 0.05, "observing: the hands are behind his back (%.2f m)" % hand.dot(back))
	r.speed = 1.2
	for i in 30:
		r.animate(1.0 / 30.0)
	for i in 40:
		r.collapse(1.0 / 30.0, i / 30.0, Vector3.RIGHT, 0.3)
	check(r.dead, "collapses")


class FakeGame extends Node3D:
	var player: Node3D


## F10 > Character: "Show Architect (internal)" places the figure near Eli,
## "Remove Architect" takes it away.
func test_dev_menu_entries() -> void:
	var game: FakeGame = add(FakeGame.new())
	game.player = Node3D.new()
	game.add_child(game.player)
	game.player.position = Vector3(2.0, 0.0, 3.0)
	var m: DevMenu = add(DevMenu.new())
	m.setup(GameState.new_run(2), game)
	m.set_open(true)
	await frames(1)
	var show := m.button("Show Architect (internal)")
	var hide := m.button("Remove Architect")
	if check(show != null and hide != null, "the two entries exist"):
		show.pressed.emit()
		await frames(2)
		var f := ArchitectFigure.find(game)
		check(f != null and f.global_position.distance_to(game.player.global_position) < 4.0, "the figure stands near Eli")
		hide.pressed.emit()
		await frames(1)
		check(ArchitectFigure.find(game) == null, "and is removed")


func test_never_spawned() -> void:
	check(not EnemyDefs.has(ArchitectIdentity.ID) and not ArchitectIdentity.ID in EnemyDefs.KINDS, "not an EnemyDefs kind")
	for lv in Difficulty.LEVELS:
		for inv in range(1, 15):
			check(not ArchitectIdentity.ID in Director.allowed(lv, inv), "the director never allows him")
			for seed in 3:
				check(not ArchitectIdentity.ID in Director.compose(lv, inv, seed), "nor composes a wave with him")
	var world := HouseWorld.new()
	add(world)
	world.build_new()
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(6, 0, 14)
	var roster: Node3D = Roster.new()
	roster.setup(world, player, 5)
	add(roster)
	await physics_frames(2)
	var e: AIEnemy = roster.spawn_type(ArchitectIdentity.ID, Vector2(6, 11), {"mode": "hidden"})
	check(e.kind != ArchitectIdentity.ID and not (e.rig is ArchitectRig), "asking the roster for him gives an ordinary psycho")
	# the F10 figure: not an enemy, silent, removable
	var host: Node3D = add(Node3D.new())
	var f := ArchitectFigure.show_near(host, player)
	check(f != null and f.rig is ArchitectRig, "the developer figure stands near Eli")
	check(f.global_position.distance_to(player.global_position) < 4.0, "a few metres away")
	await frames(30)
	check(not f in roster.enemies and not f.rig in roster.enemies and roster.living() == 1, "not in the roster")
	check(f.find_children("*", "AudioStreamPlayer3D", true, false).is_empty() and f.find_children("*", "AudioStreamPlayer", true, false).is_empty(), "silent")
	check(ArchitectFigure.remove(host) and ArchitectFigure.find(host) == null, "removed")


## No player-facing source names him (HUD, menus, encounters, map, settings,
## saves, the director ...): only the files in ALLOWED.
func test_name_stays_internal() -> void:
	var re := RegEx.new()
	re.compile("(?i)\\barchitect\\b")
	var bad: Array = []
	for path in _files("res://src"):
		if path in ALLOWED:
			continue
		if re.search(FileAccess.get_file_as_string(path)) != null:
			bad.append(path)
	check(bad.is_empty(), "the internal name appears only in developer files (found in %s)" % [bad])


func _files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres") or f.ends_with(".json") or f.ends_with(".cfg"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir + "/" + d))
	return out


## The showroom (Exp 011): every character, the comparison beside Eli with
## the ruler, every animation, the dormant poses, the lights.
func test_showroom_characters_and_comparison() -> void:
	var s: EliShowroom = add((load(EliShowroom.SCENE) as PackedScene).instantiate())
	await frames(2)
	for c in EliShowroom.CHARACTERS:
		s._set_people(c[0], 0)
		await frames(1)
		check(s.rigs().size() == 1 and s.people == c[0], "%s on the stage" % c[1])
	s._set_compare(true, "architect")
	await frames(2)
	check(s.rigs()[0] is ArchitectRig and s.beside() is EliRig, "the Architect beside Eli")
	check(s._ruler.visible and s._marks.get_child_count() >= 4, "with the ruler and both heights")
	for a in EliShowroom.ARCHITECT_ANIMS:
		s._set_anim(a[0])
		await frames(3)
	for k in ["psycho", "runner", "brute", "bomber"]:
		s._set_compare(true, k)
		await frames(1)
		check(s.rigs().size() == 1 and s.beside() is EliRig, "Eli beside the %s" % k)
	for a in EliShowroom.PEOPLE_ANIMS:
		s._set_anim(a[0])
		await frames(2)
	for d in EliShowroom.DORMANT:
		s._set_dormant(d[0])
		await frames(2)
	for l in EliShowroom.LIGHTS:
		s._set_light(l[0])
		await frames(1)
	s._set_compare(false, "psycho")
	s._step_look(1)
	await frames(1)
	check(s.beside() == null and s.people_seed == 1, "comparison off; the next look")
	s._set_compare(true, "")
	await frames(1)
	check(s.rigs()[0] is EliRig and s.beside() != null and not (s.beside() is EliRig), "Eli beside the original figure")
