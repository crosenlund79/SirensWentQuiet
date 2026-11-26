extends HumanoidArchetype
## Experiment 011: the brutes, huge men (about 1.35 x Eli's height, twice
## his breadth): massive shoulders and chest, a thick short neck, heavy arms
## and hands, a gut, a head small for the body. Real proportions from the
## body parameters (height, shoulders, weight, muscle, "bulk", "traps"),
## not a scaled person. Four former lives, two variations each (8 looks):
## a bouncer, a butcher in a stained apron, a lumberjack, a furniture mover.
## Disturbed but human faces. They carry an improvised club (extras()) and
## move like it (BruteRig: lumbering, stooped, ducking under lintels).

const BruteRig := preload("res://src/character/archetypes/brute_rig.gd")

const SKINS := [0xe0b49c, 0xd29c80, 0xbf8564, 0x9c6a4a, 0x7a4f35, 0x5a3a28]
const IRIS := [0x3a4a5c, 0x4a3626, 0x2a2420, 0x4a5a3a, 0x5c6c7c]
const HAIR := [0x1c1816, 0x3a2a20, 0x5a4030, 0x7a3e24, 0x8a6a48]

const PEOPLE := ["Bouncer", "Butcher", "Lumberjack", "Mover"]
## A brute is ~2.4 m and twice Eli's breadth: at the people's 1.5 cm voxels
## that is ~200k vertices. He is sculpted at 1 / VOXEL_SCALE and his rig is
## scaled back up: 2 cm voxels, ~120k vertices (see HUMANOIDS.md).
const VOXEL_SCALE := 1.33


func variety() -> int:
	return PEOPLE.size() * 2


func new_rig(l: Dictionary) -> HumanoidRig:
	return BruteRig.new(l)


## The club in his right hand (AIEnemy.extras["club"]).
func extras(rig: HumanoidRig) -> Dictionary:
	if rig.has_method("attach_club"):
		return {"club": rig.call("attach_club")}
	return {}


func make_look(i: int) -> Dictionary:
	var who := i % PEOPLE.size()
	var v := i / PEOPLE.size()
	var r := HumanoidArchetype.rng_for("brute", i)
	var l: Dictionary = call("_p%d" % who, v, r)
	l["name"] = "%s (%s)" % [PEOPLE[who], ["a", "b"][v]]
	var bd := HumanoidArchetype.jitter_body(r, l["body"], 0.03)
	# sculpted at 1 / VOXEL_SCALE and shown at VOXEL_SCALE (BruteRig): the same
	# proportions in coarser voxels; the head parameter compensates its
	# non-linear size (HumanoidBody: head ~ k^0.45)
	bd["height"] = float(bd["height"]) / VOXEL_SCALE
	bd["head"] = float(bd.get("head", 1.0)) * pow(VOXEL_SCALE, -0.55)
	l["body"] = bd
	l["voxel_scale"] = VOXEL_SCALE
	var o: Dictionary = l["outfit"]
	for slot in ["top", "mid", "outer", "over", "hat"]:
		if o.has(slot) and (o[slot] as Dictionary).is_empty():
			o.erase(slot)                                       # no garment in that slot
	l["club"] = ["pipe", "plank", "plank", "pipe"][who] if v == 0 else ["plank", "pipe", "plank", "plank"][who]
	var f: Dictionary = l["face"]
	f["iris"] = f.get("iris", pick(r, IRIS))
	f["pallor"] = f.get("pallor", r.randf_range(0.15, 0.3))
	f["circles"] = f.get("circles", r.randf_range(0.5, 0.9))
	f["grime"] = f.get("grime", r.randf_range(0.3, 0.6))
	f["bloodshot"] = f.get("bloodshot", r.randf_range(0.2, 0.45))
	f["look_dir"] = 1 if r.randf() < 0.5 else -1
	var s: Dictionary = l["style"]
	s["tilt"] = float(s.get("tilt", 0.0)) + r.randf_range(-0.06, 0.06)
	return l


## Shared brute build: tall, broad, heavy, small-headed.
static func _build(over: Dictionary) -> Dictionary:
	var b := {"height": 2.44, "weight": 0.72, "muscle": 1.0, "age": 0.45, "shoulders": 1.28, "hips": 1.12,
		"arms": 1.04, "hands": 1.2, "feet": 1.12, "neck": 0.55, "head": 0.84, "head_w": 1.12, "head_h": 0.96,
		"jaw": 1.28, "chin": 0.6, "brow": 1.45, "nose": 1.12, "nose_w": 1.2, "ears": 0.95,
		"bulk": 1.3, "traps": 1.0}
	b.merge(over, true)
	return b


static func _style(over: Dictionary) -> Dictionary:
	var s := {"hunch": 0.42, "head_up": 1.05, "crouch": 0.05, "stride": 0.8, "cadence": 0.78, "swing": 0.45,
		"arm_l": "swing", "arm_r": "swing", "spread": 0.16, "bob": 1.3, "sway": 0.7, "irregular": 0.15,
		"twitch": 0.12, "tempo": 0.7, "attack": "overhead", "walk_top": 2.6, "claw": 0.75}
	s.merge(over, true)
	return s


# --- the people ---------------------------------------------------------------------------

## A doorman: black T-shirt stretched over the chest, black trousers, boots, a
## shaved head, a goatee, a lanyard with a laminated pass.
func _p0(v: int, r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": _build({"height": 2.46, "weight": 0.62, "shoulders": 1.32, "head_w": 1.08, "jaw": 1.32}),
		"outfit": {"top": {"type": "tshirt", "col": [0x1e1e20, 0x2a2c30][v], "sleeve": 0.3},
			"mid": {"type": "sport", "col": 0x1c1c1e, "col2": 0x3a3a3e} if v == 1 else {},
			"legs": {"type": "trousers", "col": 0x1a1a1c, "belt": 0x101010},
			"feet": [{"type": "boots", "col": 0x161414}, {"type": "boots", "col": 0x161414}],
			"acc": ["lanyard", "watch_l"] + (["torn_r"] if v == 0 else []), "dirt": 0.35, "tears": 0.3},
		"face": {"skin": SKINS[[4, 2][v]], "eyes": "stare", "brows": "knit", "mouth": "thin", "lines": 0.3},
		"hair": {"style": "bald" if v == 0 else "buzz", "col": 0x1a1614, "beard": ["goatee", "stubble"][v]},
		"style": _style({"hunch": 0.36, "arm_l": "hang", "arm_r": "swing", "attack": "overhead", "spread": 0.2}),
	}


## A butcher: white shirt, sleeves rolled to the elbow, a long apron streaked
## brown-red from the counter, a paper cap; heavy jowls, a broken nose.
func _p1(v: int, r: RandomNumberGenerator) -> Dictionary:
	var apron: int = [0xdcd8cc, 0x3a4a5a][v]
	return {
		"body": _build({"height": 2.4, "weight": 0.9, "muscle": 0.8, "age": 0.62, "head_w": 1.16, "cheeks": 0.85,
			"nose": 1.25, "nose_w": 1.35, "chin": 0.3}),
		"outfit": {"top": {"type": "shirt", "col": [0xe4e2da, 0xd8dcd8][v], "sleeve": 0.48, "rolled": true, "tucked": true},
			"over": {"type": "apron", "col": apron, "col2": VoxelArt.scale(apron, 0.75), "stain": 0x5a3a26},
			"legs": {"type": "trousers", "col": [0x5a5a5c, 0x2c2e32][v], "belt": 0x2a221c},
			"feet": [{"type": "boots", "col": 0x2a2a2a}, {"type": "boots", "col": 0x2a2a2a}],
			"hat": {"type": "cap", "col": 0xe6e4dc} if v == 0 else {},
			"acc": ["watch_r"], "dirt": 0.45, "tears": 0.15},
		"face": {"skin": SKINS[r.randi_range(0, 2)], "eyes": "uneven", "brows": "flat", "mouth": "slack", "lines": 0.75},
		"hair": {"style": ["short", "balding"][v], "col": pick(r, HAIR), "grey": 0.4, "beard": ["", "moustache"][v]},
		"style": _style({"hunch": 0.46, "sway": 0.85, "arm_l": "hang", "arm_r": "swing", "attack": "swipe",
			"stride": 0.72, "tempo": 0.6}),
	}


## A lumberjack: plaid flannel shirt open over a henley, work jacket in the
## second variation, jeans, boots, a beanie, a great beard.
func _p2(v: int, r: RandomNumberGenerator) -> Dictionary:
	var plaid: int = [0x8a2a24, 0x2a4a3a][v]
	return {
		"body": _build({"height": 2.5, "weight": 0.6, "muscle": 1.0, "age": 0.4, "shoulders": 1.3, "arms": 1.07,
			"head_h": 1.02, "jaw": 1.2}),
		"outfit": {"top": {"type": "tshirt", "col": [0x8a8478, 0x4a4a48][v]},
			"mid": {"type": "shirt", "col": plaid, "plaid": 0x1c1a1a, "sleeve": 0.85 if v == 0 else 1.0, "rolled": v == 0},
			"outer": {"type": "work_jacket", "col": 0x6a5a3a, "col2": 0x4a3e28} if v == 1 else {},
			"legs": {"type": "jeans", "col": [0x2c3a58, 0x3a4660][v], "belt": 0x3a2a1c},
			"feet": [{"type": "boots", "col": 0x6a4a2c}, {"type": "boots", "col": 0x6a4a2c}],
			"hat": {"type": "beanie", "col": [0xb0601e, 0x2a2a2c][v]},
			"acc": ["glove_l"] if v == 1 else ["torn_l"], "dirt": 0.6, "tears": 0.3},
		"face": {"skin": SKINS[r.randi_range(0, 2)], "eyes": "wide", "brows": "raised", "mouth": "grin", "lines": 0.4},
		"hair": {"style": "messy", "col": [0x7a3e24, 0x3a2a20][v], "beard": "full", "grey": 0.15},
		"style": _style({"hunch": 0.4, "arm_l": "swing", "arm_r": "swing", "attack": "overhead", "swing": 0.55}),
	}


## A furniture mover: grey hoodie with a hi-vis vest, cargo trousers, work
## gloves, a back-to-front cap; a heavy brow, a vacant stare.
func _p3(v: int, r: RandomNumberGenerator) -> Dictionary:
	var hood: int = [0x5a5a5e, 0x2a3448][v]
	return {
		"body": _build({"height": 2.42, "weight": 0.8, "muscle": 0.95, "age": 0.3, "shoulders": 1.24, "neck": 0.5,
			"head": 0.82, "brow": 1.6}),
		"outfit": {"mid": {"type": "hoodie", "col": hood, "col2": VoxelArt.scale(hood, 0.75), "hood": "down"},
			"over": {"type": "hivis", "col": [0xd8701e, 0xc6d02a][v], "open": v == 1},
			"legs": {"type": "cargo", "col": [0x3a3a3c, 0x4a4a3a][v], "belt": 0x2a221c},
			"feet": [{"type": "boots", "col": 0x3a2e24}, {"type": "boots", "col": 0x3a2e24}],
			"hat": {"type": "cap", "col": [0x2a2a2c, 0x8a2a22][v], "back": true},
			"acc": ["glove_l", "glove_r"], "dirt": 0.55, "tears": 0.25},
		"face": {"skin": SKINS[r.randi_range(1, 5)], "eyes": "vacant", "brows": "worried", "mouth": "mutter"},
		"hair": {"style": "short", "col": pick(r, HAIR), "beard": ["stubble", "short"][v]},
		"style": _style({"hunch": 0.44, "arm_l": "swing", "arm_r": "hang", "attack": "overhead", "sway": 0.6}),
	}
