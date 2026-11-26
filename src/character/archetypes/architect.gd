extends HumanoidArchetype
## Experiment 011: "the Architect" (an internal development name, never shown
## to the player; see ArchitectIdentity). A calm, stoic, high-functioning
## man: tall but ordinary proportions, a well-kept dark overcoat buttoned
## over a pressed shirt and tie (or a black jumper), dark trousers, polished
## shoes, black leather gloves, neat greying hair, a composed, clean face.
## Unsettling through stillness and order, not gore: no dirt, no tears, no
## tics. Not an EnemyDefs kind: nothing spawns him; only the showroom and
## the F10 developer menu make his figure (ArchitectRig).
##
## Looks: 0 overcoat, shirt and tie; 1 overcoat over a black jumper.

const LOOKS := ["Overcoat and tie", "Overcoat and black jumper"]


func variety() -> int:
	return LOOKS.size()


func make_look(i: int) -> Dictionary:
	var coat: int = [0x1d1f24, 0x18181a][i]
	var shoe := {"type": "shoes", "col": 0x101012, "sole": 0x0a0a0a}
	var inner: Dictionary = {"type": "shirt", "col": 0xcfccc4, "tie": 0x1a1a20, "hem": 0.04} if i == 0 \
		else {"type": "sweater", "col": 0x161618, "col2": 0x111113, "hem": 0.04}
	return {
		"name": LOOKS[i],
		"body": {"height": 1.9, "weight": 0.22, "muscle": 0.45, "age": 0.55, "shoulders": 1.03, "head_h": 1.05,
			"head_w": 0.97, "jaw": 1.08, "chin": 0.62, "cheeks": 0.28, "nose": 1.06, "nose_w": 0.92, "brow": 1.05,
			"neck": 1.04, "ears": 0.95, "hands": 1.02},
		"outfit": {"top" if i == 0 else "mid": inner,
			"outer": {"type": "coat", "col": coat, "col2": VoxelArt.scale(coat, 0.7), "open": true, "shut": 0.24},
			"legs": {"type": "trousers", "col": 0x1a1b1f, "belt": 0x0e0e10},
			"feet": [shoe, shoe],
			"acc": ["glove_l", "glove_r"], "glove_col": 0x141416, "dirt": 0.0, "tears": 0.0},
		"face": {"skin": 0xdab8a2, "iris": 0x7a8a96, "eyes": "calm", "brows": "flat", "mouth": "set",
			"circles": 0.12, "pallor": 0.4, "grime": 0.0, "lines": 0.25, "bloodshot": 0.02},
		"hair": {"style": "combed", "col": 0x2a2622, "grey": 0.12, "neat": true, "front": 0.21},
		# stillness: upright, slow, symmetric, no tics
		"style": {"hunch": -0.02, "head_up": 1.0, "tilt": 0.0, "crouch": 0.0, "stride": 0.92, "cadence": 0.85,
			"swing": 0.22, "arm_l": "hang", "arm_r": "hang", "spread": 0.0, "bob": 0.35, "sway": 0.04,
			"limp": 0.0, "irregular": 0.0, "twitch": 0.0, "tempo": 0.6, "attack": "lunge", "walk_top": 2.6,
			"claw": 0.25},
	}


func new_rig(l: Dictionary) -> HumanoidRig:
	return ArchitectRig.new(l)
