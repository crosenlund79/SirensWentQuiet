extends "res://tests/test_case.gd"
## FogBoundary (E): prompt only at the edge, explicit exit, player-only walls,
## sensible return points, fog setup.

const LOT := FogBoundary.LOT


## Note: the first test of a run starts inside SceneTree._initialize, before the
## root is in the tree; each test here awaits a frame first.
func _boundary(player: Node3D, env: Environment = null) -> FogBoundary:
	var b := FogBoundary.new()
	b.setup(player, env)
	add(b)
	return b


func _marker(at: Vector2) -> Node3D:
	var n := Node3D.new()
	add(n)
	n.global_position = Vector3(at.x, 0, at.y)
	return n


func test_prompt_only_at_the_edge() -> void:
	await frames(1)
	var p := _marker(Vector2(6.5, 7.8))
	var b := _boundary(p)
	check_eq(b.prompt_text(), "", "no prompt in the middle of the lot")
	for at in [Vector2(4.5, LOT.end.y - 0.3), Vector2(LOT.position.x + 0.3, 5.0), Vector2(10.0, LOT.position.y + 0.25), Vector2(LOT.end.x - 0.5, 2.0)]:
		p.global_position = Vector3(at.x, 0, at.y)
		check(b.prompt_text() != "", "prompt at the edge %s" % at)
		check(b.prompt_text().contains("[E]"), "prompt names the key")
	for at in [Vector2(4.5, LOT.end.y - 1.0), Vector2(LOT.position.x + 0.9, 5.0), Vector2(2.0, 2.0)]:
		p.global_position = Vector3(at.x, 0, at.y)
		check_eq(b.prompt_text(), "", "no prompt %s from the edge" % at)


func test_exit_only_on_request_and_only_at_the_edge() -> void:
	await frames(1)
	var p := _marker(Vector2(6.5, 7.8))
	var b := _boundary(p)
	var got := []
	b.exit_requested.connect(func(at: Vector3): got.append(at))
	b.request_exit()
	check_eq(got.size(), 0, "no exit away from the edge")
	p.global_position = Vector3(4.5, 0, LOT.end.y - 0.3)
	await frames(5)
	check_eq(got.size(), 0, "standing at the edge opens nothing by itself")
	b.request_exit()
	check_eq(got.size(), 1, "interact at the edge requests the exit")
	if got.size() == 1:
		check(got[0].distance_to(p.global_position) < 0.01, "with the player's position")


func _body(at: Vector2, layer: int, mask: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = layer
	body.collision_mask = mask
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Tuning.PLAYER_RADIUS
	cyl.height = 1.4
	cs.shape = cyl
	cs.position.y = 0.85
	body.add_child(cs)
	add(body)
	body.global_position = Vector3(at.x, 0, at.y)
	return body


func _push(body: CharacterBody3D, dir: Vector3, frames_n: int) -> void:
	for i in frames_n:
		await tree.physics_frame
		body.velocity = dir * Tuning.PLAYER_SPEED
		body.move_and_slide()


func test_walls_block_the_player_but_not_enemies() -> void:
	await frames(1)
	var b := _boundary(null)
	for w in b.walls:
		check_eq(w.collision_layer, 32, "walls on layer 6")
		check_eq(w.collision_mask, 0, "walls collide with nothing themselves")
	var player := _body(Vector2(LOT.end.x - 1.5, 5.0), 1 << 2, 1 | 2 | 16 | 32)
	var enemy := _body(Vector2(LOT.end.x - 1.5, 6.5), 1 << 3, 1 | 2 | 8 | 16)
	var south := _body(Vector2(10.0, LOT.end.y - 1.5), 1 << 2, 32)
	await physics_frames(2)
	await _push(player, Vector3.RIGHT, 45)
	# Exp 012 (V): the safety walls stand past the slowing fog band (FogBand), not at the lot edge.
	var edge := LOT.end.x + FogBoundary.WALL_OUTSET
	check(player.global_position.x <= edge - Tuning.PLAYER_RADIUS + 0.05, "player stopped at the safety wall past the band (x %.2f)" % player.global_position.x)
	check(player.global_position.x > LOT.end.x, "a bare body (no FogBand) gets past the lot edge into the band (x %.2f)" % player.global_position.x)
	await _push(enemy, Vector3.RIGHT, 45)
	check(enemy.global_position.x > LOT.end.x + 1.0, "enemies walk through the lot boundary (x %.2f)" % enemy.global_position.x)
	await _push(south, Vector3.BACK, 45)
	check(south.global_position.z <= LOT.end.y + FogBoundary.WALL_OUTSET - Tuning.PLAYER_RADIUS + 0.05, "a body with only mask 32 stops at the south safety wall (z %.2f)" % south.global_position.z)


func test_return_point_is_free_and_near() -> void:
	await frames(1)
	var b := _boundary(null)
	await physics_frames(2)
	var car := Rect2()
	for pr in HousePlan.PROPS:
		if pr["id"] == "car":
			car = pr["rect"]
	var cases := [Vector2(4.5, LOT.end.y - 0.3), Vector2(17.0, LOT.end.y - 0.3), Vector2(LOT.end.x - 0.3, 10.0),
		Vector2(LOT.position.x + 0.3, 1.5), Vector2(LOT.end.x - 0.3, LOT.position.y + 0.3), Vector2(6.0, LOT.position.y + 0.3)]
	for c in cases:
		var r := b.return_point(Vector3(c.x, 0, c.y))
		var q := Vector2(r.x, r.z)
		check(LOT.grow(-1.0).has_point(q), "return point %s well inside the lot (%s)" % [c, q])
		check(not HousePlan.FOOTPRINT.has_point(q), "not inside the house (%s)" % q)
		check(not car.grow(0.3).has_point(q), "not inside the car (%s)" % q)
		check(q.distance_to(c) < 6.0, "near where you left (%s -> %s)" % [c, q])
		for pr in HousePlan.PROPS:
			if pr["blocks"]:
				check(not (pr["rect"] as Rect2).grow(0.2).has_point(q), "clear of %s (%s)" % [pr["id"], q])


func test_fog_layers_and_night_tint() -> void:
	await frames(1)
	var env := Environment.new()
	var p := _marker(Vector2(6.5, 7.8))
	var b := _boundary(p, env)
	check(env.volumetric_fog_enabled, "volumetric fog enabled on the given environment")
	check_eq(env.volumetric_fog_density, 0.0, "no global volumetric fog: only the bank")
	check(b.volume != null and b.volume.material != null, "a fog volume with its shader")
	check_eq(b.cards.size(), FogBoundary.LAYERS.size(), "one slice per layer")
	b.set_night_amount(1.0)
	check_eq(b.card_materials[0].get_shader_parameter("night"), 1.0, "slices tinted for night")
	check_eq(b.volume_material.get_shader_parameter("night"), 1.0, "volume tinted for night")
	check(env.volumetric_fog_ambient_inject > FogBoundary.VOLUMETRIC["volumetric_fog_ambient_inject"], "more moonlight scatter at night")
	b.set_volumetric(false)
	check(not env.volumetric_fog_enabled and not b.volume.visible, "volumetric part can be switched off")
	var plain := FogBoundary.new()
	plain.use_volumetric = false
	var env2 := Environment.new()
	plain.setup(p, env2)
	add(plain)
	check(not env2.volumetric_fog_enabled and plain.volume == null, "slices-only mode leaves the environment alone")
