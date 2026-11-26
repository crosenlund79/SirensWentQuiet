extends HumanoidArchetype
## Experiment 011: ordinary psychos, former ordinary people. Ten people, each
## in three variations (colours, hair, accessories, small differences of
## body and face): 30 looks. Look i is person i % 10, variation i / 10.
## Disturbed, not monstrous: wide or pinprick stares, slack or clenched
## mouths, grime, torn and dirty clothes from the lives they had.

const SKINS := [0xe4b8a0, 0xd8a184, 0xc78a68, 0xa8714f, 0x87573a, 0x5f3d29]
const IRIS := [0x3a4a5c, 0x4a3626, 0x2a2420, 0x4a5a3a, 0x5c6c7c, 0x3a2a1e]
const HAIR_YOUNG := [0x1c1816, 0x3a2a20, 0x5a4030, 0x7a3e24, 0xa8844c, 0x2a201a]
const HAIR_OLD := [0x6a645c, 0x8a8680, 0xb4b0a8, 0x4a4038]

const PEOPLE := ["Mechanic", "Office clerk", "Shop assistant", "Labourer", "Pensioner in a parka",
	"Hooded youth", "Neighbour in a cardigan", "Retired man", "Jogger", "Security guard"]


func variety() -> int:
	return PEOPLE.size() * 3


func make_look(i: int) -> Dictionary:
	var who := i % PEOPLE.size()
	var v := i / PEOPLE.size()
	var r := HumanoidArchetype.rng_for("psycho", i)
	var l: Dictionary = call("_p%d" % who, v, r)
	l["name"] = "%s (%s)" % [PEOPLE[who], ["a", "b", "c"][v]]
	l["body"] = HumanoidArchetype.jitter_body(r, l["body"], 0.035)
	var f: Dictionary = l["face"]
	f["iris"] = f.get("iris", pick(r, IRIS))
	f["pallor"] = f.get("pallor", r.randf_range(0.15, 0.35))
	f["circles"] = f.get("circles", r.randf_range(0.4, 0.9))
	f["grime"] = f.get("grime", r.randf_range(0.2, 0.6))
	f["bloodshot"] = f.get("bloodshot", r.randf_range(0.1, 0.4))
	f["look_dir"] = 1 if r.randf() < 0.5 else -1
	var s: Dictionary = l["style"]
	s["twitch"] = float(s.get("twitch", 0.3)) * r.randf_range(0.8, 1.25)
	s["tilt"] = float(s.get("tilt", 0.0)) + r.randf_range(-0.08, 0.08)
	return l


static func skin(r: RandomNumberGenerator, lo: int, hi: int) -> int:
	return SKINS[r.randi_range(lo, hi)]


# --- the people ---------------------------------------------------------------------------

## A mechanic in a grease-stained coverall, sleeves rolled, cap, a rag in the back pocket.
func _p0(v: int, r: RandomNumberGenerator) -> Dictionary:
	var cov: int = [0x2f3b55, 0x4a4c36, 0x5a2c2a][v]
	return {
		"body": {"height": 1.76, "weight": 0.45, "muscle": 0.7, "age": 0.5, "shoulders": 1.06, "head_w": 1.06,
			"jaw": 1.15, "nose": 1.12, "brow": 1.25, "hands": 1.1, "neck": 0.85},
		"outfit": {"top": {"type": "tshirt", "col": [0x8a8a86, 0x3a3a3c, 0xb8b2a4][v], "sleeve": 0.4},
			"mid": {"type": "coverall", "col": cov, "col2": VoxelArt.scale(cov, 0.75), "sleeve": 0.55, "rolled": true},
			"feet": [{"type": "boots", "col": 0x2e2620}, {"type": "boots", "col": 0x2e2620}],
			"hat": {"type": "cap", "col": [0x2a2a2c, 0x8a2a22, 0x2a3a5a][v], "back": v != 1} if v != 2 else {},
			"acc": ["rag", "watch_l"] + (["glove_r"] if v == 1 else []), "dirt": 0.75, "tears": 0.25},
		"face": {"skin": skin(r, 0, 3), "eyes": "squint", "brows": "knit", "mouth": "grimace", "lines": 0.5},
		"hair": {"style": ["short", "buzz", "balding"][v], "col": pick(r, HAIR_YOUNG), "grey": 0.25,
			"beard": ["moustache", "stubble", "short"][v]},
		"style": {"hunch": 0.3, "swing": 0.7, "arm_l": "swing", "arm_r": "hang", "attack": "overhead", "tempo": 0.9,
			"stride": 1.0, "sway": 0.45, "twitch": 0.25, "claw": 0.7, "spread": 0.06},
	}


## An office clerk: white shirt and tie under an open overcoat, slacks, a
## lanyard, cracked glasses; one shoe lost somewhere.
func _p1(v: int, r: RandomNumberGenerator) -> Dictionary:
	var coat: int = [0x34373e, 0x8a6a48, 0x283246][v]
	var shoe := {"type": "shoes", "col": 0x1c1a1a, "sole": 0x141212}
	return {
		"body": {"height": 1.85, "weight": 0.18, "muscle": 0.3, "age": 0.35, "head_h": 1.07, "jaw": 0.95, "chin": 0.75,
			"nose": 1.08, "neck": 1.15, "shoulders": 0.98},
		"outfit": {"top": {"type": "shirt", "col": [0xdedcd4, 0xb8c8d8, 0xdcc8c4][v], "tie": [0x8a2228, 0x22305a, 0x2e5a3a][v], "tucked": true},
			"outer": {"type": "coat", "col": coat, "col2": VoxelArt.scale(coat, 0.7), "open": true},
			"legs": {"type": "trousers", "col": [0x2c2e32, 0x3a3630, 0x26282e][v], "belt": 0x1a1616},
			"feet": [shoe if v != 1 else {"type": "sock", "sock": 0x2a2a30}, shoe],
			"acc": ["lanyard"] + (["glasses_cracked"] if v != 1 else ["glasses"]), "dirt": 0.4, "tears": 0.3},
		"face": {"skin": skin(r, 0, 4), "eyes": "wide", "brows": "raised", "mouth": "slack", "bloodshot": 0.45},
		"hair": {"style": "combed", "col": [0x1c1816, 0x3a2a20, 0x6a5440][v], "front": 0.205},
		"style": {"hunch": 0.12, "head_up": 1.05, "arm_l": "tight", "arm_r": "hang", "attack": "lunge", "swing": 0.4,
			"irregular": 0.55, "twitch": 0.55, "stride": 1.05, "sway": 0.2, "claw": 0.6},
	}


## A shop assistant: fleece and work apron with a name tag, jeans, sneakers, a ponytail.
func _p2(v: int, r: RandomNumberGenerator) -> Dictionary:
	var fleece: int = [0x2e5a3c, 0x2a5a66, 0x8a2c2c][v]
	var apron: int = [0x1e2a24, 0x5a3e2c, 0x30283a][v]
	return {
		"body": {"height": 1.65, "sex": 1.0, "weight": 0.25, "muscle": 0.25, "age": 0.15, "head_w": 0.96, "chin": 0.4,
			"nose": 0.92, "eyes": 1.05},
		"outfit": {"top": {"type": "tshirt", "col": 0xd8d4cc},
			"mid": {"type": "fleece", "col": fleece, "col2": VoxelArt.scale(fleece, 1.25)},
			"over": {"type": "apron", "col": apron, "col2": VoxelArt.scale(apron, 0.7)},
			"legs": {"type": "jeans", "col": [0x2c3a58, 0x3a4660, 0x1e2026][v]},
			"feet": [{"type": "sneakers", "col": 0xcfcbc2, "col2": [0x2a4a8a, 0x8a2a2a, 0x2a2a2a][v]}, {"type": "sneakers", "col": 0xcfcbc2, "col2": [0x2a4a8a, 0x8a2a2a, 0x2a2a2a][v]}],
			"acc": ["bandage_r"] if v == 2 else [], "dirt": 0.35, "tears": 0.2},
		"face": {"skin": skin(r, 0, 5), "eyes": "vacant", "brows": "worried", "mouth": "mutter"},
		"hair": {"style": "ponytail", "col": [0x5a4030, 0xa8844c, 0x1c1816][v], "tie": [0xa02a3a, 0x2a5aa0, 0xd0c040][v]},
		"style": {"hunch": 0.18, "arm_l": "fidget", "arm_r": "fidget", "attack": "flail", "swing": 0.4, "twitch": 0.7,
			"sway": 0.55, "tilt": 0.22, "cadence": 1.2, "irregular": 0.4, "claw": 0.45},
	}


## A labourer: work jacket and hi-vis vest, cargo trousers, boots, a beanie, a heavy beard.
func _p3(v: int, r: RandomNumberGenerator) -> Dictionary:
	var jacket: int = [0x6a5038, 0x7a7350, 0x34402e][v]
	return {
		"body": {"height": 1.83, "weight": 0.62, "muscle": 0.6, "age": 0.62, "head_w": 1.1, "jaw": 1.2, "nose": 1.15,
			"brow": 1.3, "neck": 0.8, "hands": 1.12, "shoulders": 1.05},
		"outfit": {"top": {"type": "tshirt", "col": 0x5a5a58},
			"outer": {"type": "work_jacket", "col": jacket, "col2": VoxelArt.scale(jacket, 0.7)},
			"over": {"type": "hivis", "col": [0xc6d02a, 0xd8701e, 0xc6d02a][v], "open": v == 1},
			"legs": {"type": "cargo", "col": [0x3a3a3c, 0x6a6048, 0x2c2e30][v], "belt": 0x2a221c},
			"feet": [{"type": "boots", "col": 0x6a4a2c}, {"type": "boots", "col": 0x6a4a2c}],
			"hat": {"type": "beanie", "col": [0xd06a1e, 0x26282c, 0x5a5e62][v]},
			"acc": ["glove_l", "glove_r"] if v == 0 else (["torn_r"] if v == 2 else []), "dirt": 0.7, "tears": 0.3},
		"face": {"skin": skin(r, 0, 3), "eyes": "squint", "brows": "knit", "mouth": "thin", "lines": 0.7},
		"hair": {"style": "short", "col": pick(r, HAIR_YOUNG), "grey": 0.45, "beard": ["full", "full", "short"][v]},
		"style": {"hunch": 0.32, "swing": 0.5, "stride": 0.9, "cadence": 0.85, "attack": "overhead", "sway": 0.5,
			"tempo": 0.8, "arm_l": "swing", "arm_r": "swing", "spread": 0.1, "twitch": 0.2, "claw": 0.75},
	}


## A pensioner in a heavy winter parka, hood down with fur trim; slippers.
func _p4(v: int, r: RandomNumberGenerator) -> Dictionary:
	var parka: int = [0x6a2a34, 0x2a3448, 0x9a7a2a][v]
	var slipper := {"type": "slippers", "col": [0xa88a8a, 0x6a5a7a, 0x8a7a62][v]}
	return {
		"body": {"height": 1.6, "sex": 1.0, "weight": 0.5, "muscle": 0.1, "age": 0.85, "head_w": 1.0, "nose": 1.05,
			"chin": 0.3, "ears": 1.05},
		"outfit": {"mid": {"type": "sweater", "col": [0x8a8278, 0x6a3a3a, 0x3a4a5a][v]},
			"outer": {"type": "parka", "col": parka, "col2": VoxelArt.scale(parka, 0.72), "fur": 0xbcae94, "open": v == 2},
			"legs": {"type": "trousers", "col": [0x3a3836, 0x4a4438, 0x2a2c30][v]},
			"feet": [slipper, slipper] if v == 0 else ([slipper, {"type": "sock", "sock": 0x8a8478}] if v == 1 else
				[{"type": "boots", "col": 0x3a2a22}, {"type": "boots", "col": 0x3a2a22}]),
			"acc": ["glasses"] if v != 1 else [], "dirt": 0.45, "tears": 0.15},
		"face": {"skin": skin(r, 0, 2), "eyes": "uneven", "brows": "worried", "mouth": "mutter", "lines": 0.9},
		"hair": {"style": ["bun", "bob", "bun"][v], "col": pick(r, HAIR_OLD), "grey": 0.6},
		"style": {"hunch": 0.45, "head_up": 1.1, "crouch": 0.04, "stride": 0.55, "cadence": 1.3, "limp": 0.45,
			"limp_side": -1.0, "arm_l": "tight", "arm_r": "hang", "swing": 0.3, "twitch": 0.3, "tempo": 0.7,
			"attack": "swipe", "sway": 0.5, "claw": 0.8},
	}


## A hooded youth: hoodie (hood up), sweatpants or jeans, dirty sneakers, messy hair.
func _p5(v: int, r: RandomNumberGenerator) -> Dictionary:
	var hood: int = [0x6a6a6e, 0x242428, 0x7a2426][v]
	return {
		"body": {"height": 1.84, "weight": 0.1, "muscle": 0.3, "age": 0.05, "head_w": 0.97, "jaw": 0.92, "chin": 0.35,
			"cheeks": 0.7, "neck": 1.1, "arms": 1.04},
		"outfit": {"top": {"type": "tshirt", "col": 0xc8c4bc},
			"mid": {"type": "hoodie", "col": hood, "col2": VoxelArt.scale(hood, 0.75), "hood": "down" if v == 2 else "up",
				"print": [0xc8c0a0, 0x8a2a2a, 0xd8d4c8][v]},
			"legs": {"type": "sweatpants" if v != 1 else "jeans", "col": [0x3a3a3e, 0x3a4a6a, 0x5a5a5c][v]},
			"feet": [{"type": "sneakers", "col": [0xd8d8d4, 0x2a2a2a, 0xd8d8d4][v], "col2": 0x2a2a2a}, {"type": "sneakers", "col": [0xd8d8d4, 0x2a2a2a, 0xd8d8d4][v], "col2": 0x2a2a2a}],
			"acc": ["torn_l"] if v == 1 else [], "dirt": 0.5, "tears": 0.35},
		"face": {"skin": skin(r, 0, 5), "eyes": "dart", "brows": "flat", "mouth": "grin"},
		"hair": {"style": "messy", "col": pick(r, HAIR_YOUNG), "beard": "stubble" if v == 2 else ""},
		"style": {"hunch": 0.32, "head_up": 1.2, "twitch": 0.85, "arm_l": "fidget", "arm_r": "swing", "stride": 1.15,
			"sway": 0.25, "irregular": 0.6, "attack": "flail", "swing": 0.7, "claw": 0.55, "walk_top": 2.0},
	}


## A neighbour in a cardigan over a blouse, knee skirt and tights, low shoes, a bob.
func _p6(v: int, r: RandomNumberGenerator) -> Dictionary:
	var card: int = [0xa8842e, 0x2e6a6a, 0x9a5a62][v]
	var shoe := {"type": "shoes", "col": [0x4a3020, 0x1c1a1a, 0x5a3a2a][v]}
	return {
		"body": {"height": 1.68, "sex": 1.0, "weight": 0.55, "muscle": 0.2, "age": 0.5, "head_w": 1.04, "chin": 0.45,
			"cheeks": 0.7, "hips": 1.05},
		"outfit": {"top": {"type": "blouse", "col": [0xe2ddd2, 0xd8cfc0, 0xc8d0d8][v]},
			"mid": {"type": "cardigan", "col": card, "col2": VoxelArt.scale(card, 0.75)},
			"legs": {"type": "skirt", "col": [0x2a3248, 0x4a4a4e, 0x4a3a2e][v], "col2": 0x2a2224},
			"feet": [shoe, shoe],
			"acc": (["bandage_l"] if v != 1 else []) + (["glasses"] if v == 1 else []), "dirt": 0.3, "tears": 0.25},
		"face": {"skin": skin(r, 0, 4), "eyes": "wide", "brows": "raised", "mouth": "slack"},
		"hair": {"style": "bob", "col": [0x7a3e24, 0x3a2a20, 0x9a8a6a][v], "grey": 0.15},
		"style": {"hunch": 0.16, "arm_l": "hang", "arm_r": "reach", "attack": "swipe", "twitch": 0.35, "sway": 0.45,
			"swing": 0.4, "tilt": -0.15, "claw": 0.65},
	}


## A retired man: knitted sweater over a shirt, belted slacks, slippers; a grey
## fringe round a bald crown, bushy brows, big ears and nose; stooped.
func _p7(v: int, r: RandomNumberGenerator) -> Dictionary:
	var sw: int = [0x3a5038, 0x6a4a32, 0x6a2a30][v]
	return {
		"body": {"height": 1.72, "weight": 0.22, "muscle": 0.15, "age": 0.95, "head_w": 0.98, "head_h": 1.04,
			"nose": 1.22, "ears": 1.15, "brow": 1.35, "jaw": 0.92, "cheeks": 0.25},
		"outfit": {"top": {"type": "shirt", "col": [0xd8d0c0, 0xc8ccd4, 0xe0dcd0][v], "tucked": true},
			"mid": {"type": "sweater", "col": sw, "col2": VoxelArt.scale(sw, 0.75), "band": 0xc8c0a8 if v == 1 else -1},
			"legs": {"type": "trousers", "col": [0x8a7a5e, 0x5a5a5c, 0x6a5e4a][v], "belt": 0x3a2a1e},
			"feet": [{"type": "slippers", "col": 0x5a4030}, {"type": "slippers", "col": 0x5a4030}] if v != 2 else [{"type": "shoes", "col": 0x3a2a1e}, {"type": "shoes", "col": 0x3a2a1e}],
			"acc": ["glasses"] if v == 2 else [], "dirt": 0.35, "tears": 0.15},
		"face": {"skin": skin(r, 0, 3), "eyes": "stare", "brows": "flat", "mouth": ["mutter", "thin", "slack"][v], "lines": 1.0},
		"hair": {"style": "balding", "col": pick(r, HAIR_OLD), "grey": 0.85, "beard": "stubble" if v == 1 else ""},
		"style": {"hunch": 0.5, "head_up": 1.15, "crouch": 0.05, "stride": 0.5, "cadence": 1.4, "arm_l": "hang",
			"arm_r": "tight", "swing": 0.25, "tempo": 0.65, "twitch": 0.4, "attack": "lunge", "sway": 0.35, "claw": 0.85},
	}


## A jogger: zipped sports jacket, leggings, bright sneakers, a ponytail or a bun.
func _p8(v: int, r: RandomNumberGenerator) -> Dictionary:
	var jk: int = [0xa8487a, 0x2a8a9a, 0x5a3a8a][v]
	var sn := {"type": "sneakers", "col": [0xe0dcd8, 0x3a3a3e, 0xd8e0e4][v], "col2": [0xd04a2a, 0x2ab0a0, 0xb0c030][v]}
	return {
		"body": {"height": 1.7, "sex": 1.0, "weight": 0.12, "muscle": 0.55, "age": 0.25, "chin": 0.55, "cheeks": 0.6,
			"legs": 1.03},
		"outfit": {"mid": {"type": "sport", "col": jk, "col2": 0xd8d4d0 if v != 1 else 0x2a2a2e},
			"legs": {"type": "leggings", "col": 0x1e1e22, "col2": [jk, 0x6a6a70, -1][v]},
			"feet": [sn, sn],
			"hat": {"type": "headband", "col": [0xe0dcd8, 0x2a8a9a, 0xb0c030][v]} if v != 2 else {},
			"acc": ["watch_l"], "dirt": 0.3, "tears": 0.2},
		"face": {"skin": skin(r, 1, 5), "eyes": "wide", "brows": "knit", "mouth": "grimace"},
		"hair": {"style": "ponytail" if v != 1 else "bun", "col": pick(r, HAIR_YOUNG), "tie": 0x2a2a2a},
		"style": {"hunch": 0.25, "stride": 1.2, "swing": 0.9, "twitch": 0.6, "attack": "swipe", "walk_top": 1.9,
			"sway": 0.2, "irregular": 0.45, "claw": 0.5},
	}


## A security guard: pale-blue shirt and dark tie under a navy jumper, black
## cargo trousers, boots, a lanyard; a big man with a buzz cut.
func _p9(v: int, r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.88, "weight": 0.6, "muscle": 0.75, "age": 0.4, "head_w": 1.04, "jaw": 1.12, "neck": 0.8,
			"shoulders": 1.08, "hands": 1.1},
		"outfit": {"top": {"type": "shirt", "col": [0x8aa0b8, 0xd0d0cc, 0x8aa0b8][v], "tie": 0x1a1e2a, "tucked": true},
			"mid": {"type": "sweater", "col": [0x262e40, 0x2a2a2c, 0x262e40][v]},
			"legs": {"type": "cargo", "col": 0x1e1e20, "belt": 0x141414},
			"feet": [{"type": "boots", "col": 0x1c1a18}, {"type": "boots", "col": 0x1c1a18}],
			"acc": ["lanyard", "watch_r"], "dirt": 0.35, "tears": 0.2},
		"face": {"skin": skin(r, 3, 5), "eyes": "stare", "brows": "knit", "mouth": "thin"},
		"hair": {"style": "buzz", "col": 0x1a1614, "beard": ["stubble", "short", ""][v]},
		"style": {"hunch": 0.1, "head_up": 1.0, "arm_l": "hang", "arm_r": "hang", "stride": 1.0, "irregular": 0.2,
			"twitch": 0.3, "attack": "overhead", "sway": 0.15, "swing": 0.35, "spread": 0.08, "claw": 0.6},
	}
