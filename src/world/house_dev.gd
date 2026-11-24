extends RefCounted
## Experiment 004 developer tools for the house (F10 "House (Exp. 004)"):
## furniture, doors, the fuse box and a destruction stress test. Each
## returns a status line for the menu.

const BLASTS := 10
const BLAST_GAP := 0.12        ## s between the stress test's blasts


static func run(w: HouseWorld, what: String) -> String:
	if w == null or w.grid == null:
		return "No house."
	match what:
		"destroy_furniture":
			return destroy_random_furniture(w)
		"damage_doors":
			return damage_doors(w)
		"toggle_fuse":
			var fb := w.fuse_box()
			if fb == null:
				return "There is no fuse box."
			w.toggle_mains(fb)
			return "Main power %s." % ("on" if fb.mains_on else "off")
		"destroy_fuse":
			var fb := w.fuse_box()
			if fb == null:
				return "There is no fuse box."
			w.damage_object(fb, fb.hp + 1, Vector3(fb.pos.x - 1.0, 1.2, fb.pos.y))
			return "Fuse box destroyed."
		"blasts":
			return debris_blasts(w)
	return "Unknown tool %s." % what


static func destroy_random_furniture(w: HouseWorld) -> String:
	if w.furniture == null:
		return "No furniture system (Version A house)."
	var ids := []
	for id in w.furniture.pieces:
		if w.furniture.ok(id):
			ids.append(id)
	if ids.is_empty():
		return "No furniture left standing."
	var id: String = ids[randi() % ids.size()]
	w.furniture.destroy(id)
	return "Destroyed the %s (%d pieces left)." % [w.furniture.display_name(id).to_lower(), ids.size() - 1]


static func damage_doors(w: HouseWorld) -> String:
	var n := 0
	for o in w.objects.duplicate():
		if o.kind == "door":
			w.damage_object(o, maxi(1, o.max_hp / 2), Vector3(o.pos.x, 1.0, o.pos.y - 1.0))
			n += 1
	return "Damaged %d door%s by half their HP." % [n, "" if n == 1 else "s"]


## Ten blasts in and around the house, one every BLAST_GAP s (a stress test
## of the destruction lifecycle; the player isn't hurt).
static func debris_blasts(w: HouseWorld) -> String:
	if not w.is_inside_tree():
		return "Not in the scene."
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var area := HousePlan.FOOTPRINT.grow(1.0)
	for k in BLASTS:
		var at := Vector3(rng.randf_range(area.position.x, area.end.x), 1.0, rng.randf_range(area.position.y, area.end.y))
		var radius := rng.randf_range(1.1, 1.6)
		var t := w.get_tree().create_timer(BLAST_GAP * k)
		t.timeout.connect(func() -> void:
			if is_instance_valid(w) and w.grid != null:
				w.explode(at, radius, 24.0))
	return "%d blasts on the way." % BLASTS
