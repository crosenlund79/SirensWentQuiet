extends "res://tests/test_case.gd"
## The 0.2 m question (docs/experiment-002/VOXEL_RESOLUTION.md): the same walls,
## shots and bites with 0.1 m damage (quantum 1, Experiment 001) and 0.2 m
## damage blocks (quantum 2) inside the same 0.1 m storage. Prints the numbers.

const PATTERN := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
	Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]
## [from, hole, vertical wall]
const HOLES := [[Vector2(3.6, 1.2), Vector2(4.0, 0.0), false], [Vector2(11.0, 7.4), Vector2(11.0, 9.0), false], [Vector2(1.6, 3.0), Vector2(0.0, 3.0), true]]


func _world(q: int) -> HouseWorld:
	var w := HouseWorld.new()
	w.damage_quantum = q
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _shots_to_open(w: HouseWorld, from: Vector2, hole: Vector2, vertical: bool, stats: Dictionary) -> int:
	var shots := 0
	var o := Vector3(from.x, Tuning.MUZZLE_HEIGHT, from.y)
	while shots < 60 and not w.nav.is_walkable(w.nav.cell_of(hole)):
		var k: Vector2 = PATTERN[shots % PATTERN.size()]
		var t := Vector3(hole.x, k.y, hole.y + k.x) if vertical else Vector3(hole.x + k.x, k.y, hole.y)
		var t0 := Time.get_ticks_usec()
		w.shoot(o, t - o, [])
		var t1 := Time.get_ticks_usec()
		w.chunks.flush(100000.0)
		var t2 := Time.get_ticks_usec()
		stats["shot_ms"].append((t1 - t0) / 1000.0)
		stats["carve_ms"].append(w.stats["carve_ms"])
		stats["coll_ms"].append(w.chunks.last_collision_ms)
		stats["mesh_ms"].append((t2 - t1) / 1000.0)
		shots += 1
	return shots if w.nav.is_walkable(w.nav.cell_of(hole)) else 99


func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(1.0, a.size())


func _max(a: Array) -> float:
	var m := 0.0
	for x in a:
		m = maxf(m, x)
	return m


## Experiment 001's Version A demo under the same load, for reference.
func _demo_baseline() -> Dictionary:
	var v: Node = (load("res://src/voxel/voxel_demo.tscn") as PackedScene).instantiate()
	add(v)
	tree.current_scene = v
	await frames(3)
	v.debug_set_spawning(false)
	var carve := []
	var coll := []
	var mesh := []
	for h in HOLES:
		v.debug_teleport_player(h[0])
		await physics_frames(1)
		for k in 12:
			var o: Vector2 = PATTERN[k]
			v.debug_fire_at(h[1] + (Vector2(0, o.x) if h[2] else Vector2(o.x, 0)), o.y)
			carve.append(v.last_carve_ms)
			coll.append(v.world.last_collision_ms)
			var t0 := Time.get_ticks_usec()
			v.world.flush(100000.0)
			mesh.append((Time.get_ticks_usec() - t0) / 1000.0)
	var out := {"carve": _avg(carve), "carve_max": _max(carve), "coll": _avg(coll), "mesh": _avg(mesh), "mesh_max": _max(mesh)}
	print("    Experiment 001 demo (0.1 m, voxel furniture): carve+crumble %.1f ms avg / %.1f max; collision %.1f ms avg; mesh %.1f ms avg / %.1f max" % [out["carve"], out["carve_max"], out["coll"], out["mesh"], out["mesh_max"]])
	return out


func test_damage_resolution_0_1_vs_0_2() -> void:
	await _demo_baseline()
	var rows := {}
	for q in [1, 2]:
		var w: HouseWorld = await _world(q)
		var stats := {"shot_ms": [], "mesh_ms": [], "carve_ms": [], "coll_ms": []}
		var faces0 := w.chunks.face_count
		var solid0 := w.grid.solid_count
		var shots := []
		for h in HOLES:
			shots.append(_shots_to_open(w, h[0], h[1], h[2], stats))
		var removed := solid0 - w.grid.solid_count
		var faces := w.chunks.face_count - faces0
		# 40 shots spread over a plain stretch of the south wall (craters, few holes)
		var w2: HouseWorld = await _world(q)
		var f0 := w2.chunks.face_count
		var o := Vector3(9.0, 1.3, 12.0)
		for k in 40:
			var t := Vector3(8.15 + (k % 10) * 0.19, 0.35 + (k / 10) * 0.4, 9.0)
			w2.shoot(o, t - o, [])
		w2.chunks.flush(100000.0)
		var spread_faces := w2.chunks.face_count - f0
		rows[q] = {"faces_total": w2.chunks.face_count}
		# enemy bites to open the bedroom's north wall from outside
		var bites := 0
		while bites < 200 and not w2.nav.is_walkable(w2.nav.cell_of(Vector2(4.0, 0.0))):
			w2.enemy_strike(Vector3(4.0, 0, -0.65), Vector2(4.0, 0.0))
			bites += 1
		rows[q].merge({"shots": shots, "removed": removed, "faces": faces, "spread_faces": spread_faces, "bites": bites,
			"shot_avg": _avg(stats["shot_ms"]), "shot_max": _max(stats["shot_ms"]), "mesh_avg": _avg(stats["mesh_ms"]), "mesh_max": _max(stats["mesh_ms"]),
			"carve_avg": _avg(stats["carve_ms"]), "carve_max": _max(stats["carve_ms"]), "coll_avg": _avg(stats["coll_ms"])})
		print("    quantum %d (%.1f m): holes %s shots, %d voxels removed, %+d faces; 40 spread shots %+d faces (total %d); %d bites to open; carve+crumble %.1f ms avg / %.1f max; collision %.1f ms avg; whole shot %.1f ms avg / %.1f max; mesh %.1f ms avg / %.1f max" % [
			q, q * 0.1, str(shots), removed, faces, spread_faces, rows[q]["faces_total"], bites, rows[q]["carve_avg"], rows[q]["carve_max"], rows[q]["coll_avg"], rows[q]["shot_avg"], rows[q]["shot_max"], rows[q]["mesh_avg"], rows[q]["mesh_max"]])
		for n in shots:
			check(n >= 6 and n <= 30, "quantum %d opens walk-through holes in a reasonable number of shots (%s)" % [q, str(shots)])
		check(bites < 200, "quantum %d: bites open the wall" % q)
	check(rows[2]["spread_faces"] < rows[1]["spread_faces"], "0.2 m damage leaves fewer faces (%d vs %d)" % [rows[2]["spread_faces"], rows[1]["spread_faces"]])
