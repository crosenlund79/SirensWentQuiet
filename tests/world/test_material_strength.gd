extends "res://tests/test_case.gd"
## Experiment 003: measured strength of the wall materials (shots, enemy
## bites and blasts to open a walk-through breach) and the explosion API on
## each. The numbers are printed for docs/experiment-003/construction.md.

const LINE := 11
const SEGS := [Vector3i(0, LINE, 0), Vector3i(0, LINE, 1), Vector3i(0, LINE, 2)]
const HOLE := Vector2(1.5, LINE)


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


## A 3 m wall in the open yard on y = 11 (the outside is +y, away from the bed).
func _wall(kind: String) -> HouseWorld:
	var w: HouseWorld = await _world()
	match kind:
		"wood":
			w.build_walls(SEGS)
		"stone":
			w.build_foundation(SEGS)
			w.build_walls(SEGS, "stone")
		"wood+iron":
			w.build_walls(SEGS)
			for s in SEGS:
				w.upgrade_section(s)
		"stone+iron":
			w.build_foundation(SEGS)
			w.build_walls(SEGS, "stone")
			for s in SEGS:
				w.upgrade_section(s)
	await physics_frames(1)
	return w


func _breached(w: HouseWorld) -> bool:
	return w.nav.is_walkable(w.nav.cell_of(HOLE))


## Shots from 1.8 m out at random points of the hole area (x ± 0.45 m,
## 0.05-1.65 m high), as a player keeps shooting at what still stands.
func _shots(w: HouseWorld, hole: Vector2, outward: Vector2, limit: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var o := Vector3(hole.x + outward.x * 1.8, Tuning.MUZZLE_HEIGHT, hole.y + outward.y * 1.8)
	var n := 0
	while n < limit and not w.nav.is_walkable(w.nav.cell_of(hole)):
		var t := Vector3(hole.x + rng.randf_range(-0.45, 0.45), rng.randf_range(0.05, 1.65), hole.y)
		w.shoot(o, t - o, [])
		n += 1
	return n if w.nav.is_walkable(w.nav.cell_of(hole)) else -1


func _bites(w: HouseWorld, limit: int, strength := 1.0) -> int:
	var n := 0
	var at := Vector3(HOLE.x, 0, LINE + 0.6)
	while n < limit and not _breached(w):
		w.enemy_strike(at, HOLE, strength)
		n += 1
	return n if _breached(w) else -1


func _blasts(w: HouseWorld, limit: int) -> Array:
	var n := 0
	var first := {}
	while n < limit and not _breached(w):
		var r := w.explode(Vector3(HOLE.x, 1.0, LINE + 0.55), 1.6, 24.0)
		if first.is_empty():
			first = r
		n += 1
	return [n if _breached(w) else -1, first]


func test_strength_by_material() -> void:
	var rows := {}
	for kind in ["frame", "wood", "wood+iron", "stone", "stone+iron"]:
		var row := {}
		if kind == "frame":
			# the original south wall (living room), a plain stretch at x = 8.5
			row["shots"] = _shots(await _world(), Vector2(8.5, 9.0), Vector2(0, 1), 400)
			var w2: HouseWorld = await _world()
			var b := 0
			while b < 600 and not w2.nav.is_walkable(w2.nav.cell_of(Vector2(8.5, 9.0))):
				w2.enemy_strike(Vector3(8.5, 0, 9.6), Vector2(8.5, 9.0))
				b += 1
			row["bites"] = b if w2.nav.is_walkable(w2.nav.cell_of(Vector2(8.5, 9.0))) else -1
			var w4: HouseWorld = await _world()
			b = 0
			while b < 600 and not w4.nav.is_walkable(w4.nav.cell_of(Vector2(8.5, 9.0))):
				w4.enemy_strike(Vector3(8.5, 0, 9.6), Vector2(8.5, 9.0), 3.0)
				b += 1
			row["brute_bites"] = b if w4.nav.is_walkable(w4.nav.cell_of(Vector2(8.5, 9.0))) else -1
			var w3: HouseWorld = await _world()
			var x := 0
			var first := {}
			while x < 5 and not w3.nav.is_walkable(w3.nav.cell_of(Vector2(8.5, 9.0))):
				var r := w3.explode(Vector3(8.5, 1.0, 9.7), 1.6, 24.0)
				if first.is_empty():
					first = r
				x += 1
			row["blasts"] = x if w3.nav.is_walkable(w3.nav.cell_of(Vector2(8.5, 9.0))) else -1
			row["blast_voxels"] = first.get("voxels", 0)
			row["blast_ms"] = first.get("ms", 0.0)
			print("      blast timing: ", w3.stats["blast"], " carve split ", VoxelCarver.last_blast_ms)
		else:
			row["shots"] = _shots(await _wall(kind), HOLE, Vector2(0, 1), 400)
			row["bites"] = _bites(await _wall(kind), 1500)
			row["brute_bites"] = _bites(await _wall(kind), 1500, 3.0)
			var bl := _blasts(await _wall(kind), 5)
			row["blasts"] = bl[0]
			row["blast_voxels"] = bl[1].get("voxels", 0)
			row["blast_ms"] = bl[1].get("ms", 0.0)
		rows[kind] = row
		print("    %-10s shots %4d · bites %4d · brute bites %4s · blasts %2d (first: %d voxels, %.0f ms)" % [kind, row["shots"], row["bites"],
			str(row.get("brute_bites", "-")), row["blasts"], row["blast_voxels"], row["blast_ms"]])
	check(rows["wood"]["shots"] > 0 and rows["stone"]["shots"] > rows["wood"]["shots"] * 2.5, "stone takes far more shots than wood")
	check(rows["wood+iron"]["shots"] > rows["wood"]["shots"] * 1.5, "iron plating takes more shots than bare wood")
	check(rows["stone"]["bites"] > rows["wood"]["bites"] * 2.5, "stone takes far more bites than wood")
	check(rows["wood"]["blasts"] == 1, "one blast breaches a wooden wall")
	check(rows["stone"]["blasts"] >= 2 or rows["stone"]["blasts"] == -1, "a stone wall survives one blast")
