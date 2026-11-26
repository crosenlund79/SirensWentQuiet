extends "res://tests/test_case.gd"
## Exp 010: Eli builds, animates every pose without errors, swaps in for the
## original figure at runtime, and the showroom loads.


func test_rig_builds_and_animates() -> void:
	var r: EliRig = add(EliRig.new(0))
	await frames(1)
	check(r.parts.size() >= 16, "one mesh per body part (%d)" % r.parts.size())
	for mi in r.parts:
		check((mi as MeshInstance3D).mesh.get_surface_count() == 1, "%s has a mesh" % mi.get_parent().name)
	check(r.gun != null and r.gun.get_child(0) is MeshInstance3D, "the pistol is the gun node's first child")
	for sp in [0.0, 1.4, 4.0, 6.4]:
		r.speed = sp
		for i in 20:
			r.animate(1.0 / 30.0)
	r.speed = 0.0
	r.aiming = true
	for i in 15:
		r.animate(1.0 / 30.0)
	var m := r.muzzle_global()
	check(m.y > 1.0 and m.y < 1.7, "the muzzle is at chest height (%s)" % m)
	check(Vector2(m.x, m.z).length() > 0.3, "and out in front")
	var sg := WeaponHandler.shotgun_model()
	r.gun.add_child(sg)
	(r.gun.get_child(0) as Node3D).visible = false
	for i in 15:
		r.animate(1.0 / 30.0)
	check(r.two_handed(), "two-handed with the long gun")
	r.aiming = false
	r.set_held("hammer")
	r.carry = true
	r.use_t = 1.0
	for i in 10:
		r.animate(1.0 / 30.0)
	check(r.hand_global().y > 0.5, "hand position")
	r.set_variant(1)
	r.animate(0.1)


func test_player_swaps_the_rig_live() -> void:
	var keep: Variant = GameSettings.get_value("character")
	GameSettings.set_value("character", "eli")
	var p: VoxelPlayer = add(VoxelPlayer.new())
	await physics_frames(2)
	check(p.rig is EliRig, "Eli by default")
	p.rig.rotation.y = 1.2
	p.rig.set_held("food")
	GameSettings.set_value("character", "original")
	await physics_frames(2)
	check(not (p.rig is EliRig) and p.rig is VoxelRig, "the original figure after the switch")
	check(absf(p.rig.rotation.y - 1.2) < 0.01 and p.rig.held == "food", "facing and held item kept")
	GameSettings.set_value("character", "eli")
	await physics_frames(2)
	check(p.rig is EliRig, "and back to Eli")
	GameSettings.set_value("character", keep)


func test_showroom_loads() -> void:
	var s: EliShowroom = add((load(EliShowroom.SCENE) as PackedScene).instantiate())
	await frames(2)
	check(s.rigs().size() == 1, "Eli on the stage")
	for a in EliShowroom.ANIMS:
		s._set_anim(a[0])
		await frames(2)
	s._apply_view("sheet")
	await frames(1)
	check(s.rigs().size() == 4, "the turnaround sheet")
	s._apply_view("gameplay")
	s._set_variant(2)
	await frames(1)


func test_showroom_overlay_opens_and_closes() -> void:
	var s := EliShowroom.open_overlay(tree)
	await frames(2)
	check(tree.paused, "the game pauses under the showroom")
	check(s.rigs().size() == 1, "Eli on the overlay stage")
	s.close()
	await frames(2)
	check(not tree.paused, "closing restores the game")
	check(tree.root.get_node_or_null("EliShowroomLayer") == null, "the overlay is gone")
