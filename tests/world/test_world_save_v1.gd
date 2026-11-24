extends "res://tests/test_case.gd"
## Experiment 003: a real Experiment 002 world save (format version 1, made
## by the Experiment 002 code: tests/world/fixtures/exp002_world_v1.bin)
## loads with the version 2 defaults and re-saves as version 2.

const FIXTURE := "res://tests/world/fixtures/exp002_world_v1.bin"


func _fixture() -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = f.get_var()
	return d if d is Dictionary else {}


func test_experiment_002_world_save_loads() -> void:
	var d := _fixture()
	check_eq(d.get("version"), 1, "the fixture is a version 1 save")
	check(not d.has("stone") and not d.has("foundations") and not d.has("scars"), "without the version 2 fields")
	var w := HouseWorld.new()
	add(w)
	check(w.load_data(d), "an Experiment 002 world save loads")
	await physics_frames(2)
	if w.grid == null:
		return
	# what the fixture holds (see the commit that added it)
	check_eq(w.count_objects("door"), 3, "front, back and a built door")
	check_eq(w.count_objects("barricade"), 1, "a barricade")
	check_eq(w.count_objects("crate"), 1, "a crate")
	check_eq(w.count_objects("rain_collector"), 1, "a rain collector")
	for o in w.objects:
		check_eq(o.mat, "wood", "%s loads as wood" % o.kind)
	check_eq(w.built.size(), 4, "4 m of built wall")
	for s in w.built:
		check_eq(w.sections[s]["material"], "wood", "built section %s is wooden" % s)
	check(w.upgraded.has(Vector3i(0, 0, 3)), "the sheathed section (now iron plating)")
	check_eq(w.section_strength(Vector3i(0, 0, 3)), HouseWorld.PLATED_FACTOR, "and counts as plated")
	check(w.foundations.is_empty() and w.scars.is_empty(), "no foundations or scars")
	var dmg := w.damage_summary()
	check_eq(dmg["missing_voxels"], 711, "the damage as saved")
	check_eq(dmg["damaged_objects"], 1, "the damaged front door")
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(8.5, 9.0))), "the shot-open hole is walkable")
	check(w.is_blocked(Vector2(0.5, 11.0)), "the built wall blocks")
	check(w.exit_path_exists(), "a way out")
	# the new systems work on a loaded old house
	var r := w.explode(Vector3(1.5, 1.0, 11.55), 1.6, 24.0)
	check(r["voxels"] > 0, "a blast works on it")
	check(not w.weak_points(Vector2(4.5, 14.0)).is_empty(), "and weak_points")
	# re-saved as version 2, and that loads identically
	var d2 := w.save_data()
	check_eq(d2["version"], HouseWorld.SAVE_VERSION, "re-saved as version 2")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(bytes_to_var(var_to_bytes(d2))), "the version 2 save loads")
	if w2.grid != null:
		check(w2.grid.mat == w.grid.mat and w2.design.mat == w.design.mat, "identical grids")
		check_eq(w2.scars, w.scars, "with the new scar")


func test_version_1_with_bad_data_is_still_refused() -> void:
	var d := _fixture()
	for patch in [{"version": 0}, {"objects": [{"kind": "door", "x": 4.5, "y": 9.0, "rot": 2, "hp": 30}]}, {"built": "x"}]:
		var dd := d.duplicate(true)
		dd.merge(patch, true)
		var w := HouseWorld.new()
		add(w)
		check(not w.load_data(dd), "refused: %s" % str(patch))
		check(w.grid == null, "nothing built")
