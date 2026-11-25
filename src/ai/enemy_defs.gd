class_name EnemyDefs
extends RefCounted
## Enemy archetypes as data (SPEC-003 §5). One body (AIEnemy) and one shared
## behaviour core read these; the only per-type code is a small behaviour hook
## ("chase" or "bomber", see enemy_behaviour.gd). Docs: docs/experiment-003/ai.md.
##
## Fields:
##   name, cost (threat budget), behaviour ("chase" | "bomber")
##   speed (m/s), hp, radius (collision m)
##   bash_weight   path cost per wall/door cell (GridNav.BASH_WEIGHT = 12 is the
##                 shared nav): higher = detours to openings, lower = bashes through
##   wall_strikes  world.enemy_strike calls per wall/door/barricade swing
##   player_damage multiplier on GameState.enemy_damage() per player hit
##   attack_range, attack_interval (s), reach (m to a wall cell it can hit)
##   knockback, stagger  multipliers on the Tuning hit reaction (0 = immovable)
##   looks (VoxelRig.Look values), scale (rig), tint (Color, a = mix), shade
##   (brightness), xray (silhouette tint through walls), hunch (rad)
## Bomber only: fuse (s), blast_radius (voxel carve m), blast_power (object
## damage at the centre), blast_reach (m, characters take 0 beyond),
## blast_damage (character damage at the centre, before difficulty),
## blast_enemy_hits (hits dealt to other enemies at the centre),
## small_* (the weak pop when killed while the fuse burns).
## Exp 006 (B), "more dangerous enemies" (data-driven first pass; the old
## numbers are in docs/experiment-006 and the B report):
##   windup        s from a swing's start to its impact (AIEnemy; was 0.28,
##                 x1.4 for the brute, hard-coded)
##   repath        s between path refreshes (PursuitBrain; was Tuning's 0.6)
##   stuck, progress  the brain's two stuck rules (were 0.5 s and 2.5 s)
## All four are optional; missing ones fall back to the old behaviour.

const KINDS := ["psycho", "runner", "brute", "bomber"]
const SPECIALS := ["runner", "brute"]

const DEFS := {
	# Exp 006 (B): speed 1.4 -> 1.85, swings 1.1 -> 0.85 s, wind-up 0.28 -> 0.22 s,
	# reach 0.85 -> 0.95 m, damage x1.0 -> x1.2, repath 0.6 -> 0.35 s
	"psycho": {
		"name": "Psycho", "cost": 1.0, "behaviour": "chase",
		"speed": 1.85, "hp": 3, "radius": 0.25,
		"bash_weight": 12.0, "wall_strikes": 1, "player_damage": 1.2,
		"attack_range": 0.95, "attack_interval": 0.85, "reach": 0.8,
		"windup": 0.22, "repath": 0.35, "stuck": 0.35, "progress": 1.6,
		"knockback": 1.0, "stagger": 1.0,
		"looks": [1, 2, 3, 4], "scale": Vector3(1.0, 1.0, 1.0), "tint": Color(1, 1, 1, 0.0), "shade": 1.0,
		"xray": Color(0.95, 0.5, 0.45, 0.32), "hunch": 0.38, "moan": true,
	},
	# Exp 006 (B): speed 2.6 -> 3.3 (still under the player's 4.0 walk), swings 0.75 -> 0.6 s,
	# damage x0.6 -> x0.7, wind-up 0.28 -> 0.18 s
	"runner": {
		"name": "Runner", "cost": 1.5, "behaviour": "chase",
		"speed": 3.3, "hp": 2, "radius": 0.22,
		"bash_weight": 60.0, "wall_strikes": 1, "player_damage": 0.7,
		"attack_range": 0.95, "attack_interval": 0.6, "reach": 0.8,
		"windup": 0.18, "repath": 0.3, "stuck": 0.3, "progress": 1.4,
		"knockback": 1.4, "stagger": 1.2,
		"looks": [2], "scale": Vector3(0.8, 1.04, 0.8), "tint": Color(0.86, 0.9, 0.95, 0.6), "shade": 1.18,
		"xray": Color(0.8, 0.9, 1.0, 0.34), "hunch": 0.55, "moan": true,
	},
	# Exp 006 (B): speed 1.0 -> 1.25 (slowest), swings 1.6 -> 1.35 s, damage x1.8 -> x2.2,
	# wind-up 0.39 -> 0.34 s
	"brute": {
		"name": "Brute", "cost": 3.0, "behaviour": "chase",
		"speed": 1.25, "hp": 8, "radius": 0.29,
		"bash_weight": 4.0, "wall_strikes": 3, "player_damage": 2.2,
		"attack_range": 1.05, "attack_interval": 1.35, "reach": 0.95,
		"windup": 0.34, "repath": 0.45, "stuck": 0.4, "progress": 1.8,
		"knockback": 0.12, "stagger": 0.3,
		"looks": [3], "scale": Vector3(1.4, 1.28, 1.4), "tint": Color(0.34, 0.31, 0.3, 0.82), "shade": 0.78,
		"xray": Color(0.95, 0.32, 0.25, 0.42), "hunch": 0.48, "moan": true,
	},
	# Exp 006 (B): speed 1.6 -> 2.0, fuse 2.5 -> 2.2 s; targeting unchanged
	"bomber": {
		"name": "Bomber", "cost": 4.0, "behaviour": "bomber",
		"speed": 2.0, "hp": 2, "radius": 0.25,
		"bash_weight": 40.0, "wall_strikes": 0, "player_damage": 0.0,
		"attack_range": 0.0, "attack_interval": 1.1, "reach": 0.8,
		"repath": 0.4, "stuck": 0.4, "progress": 1.8,
		"knockback": 0.8, "stagger": 0.8,
		"looks": [4], "scale": Vector3(1.0, 1.0, 1.0), "tint": Color(0.75, 0.72, 0.35, 0.3), "shade": 0.95,
		"xray": Color(1.0, 0.6, 0.15, 0.55), "hunch": 0.2, "moan": false,
		"fuse": 2.2, "blast_radius": 1.6, "blast_power": 24.0, "blast_reach": 4.0,
		"blast_damage": 60.0, "blast_enemy_hits": 8,
		"small_reach": 1.6, "small_damage": 15.0, "small_enemy_hits": 2,
	},
}

## Speed multiplier per difficulty (fallback; Exp 006 (B): Difficulty's
## `enemy_speed` takes precedence: Easy 0.85, Normal 1, Hard 1.12).
const DIFFICULTY_SPEED := {"easy": 0.85, "normal": 1.0, "hard": 1.12}
const HP_STEP := 0.25            ## +25 % hp every second invasion (Exp. 002: psycho 3, 3, 4, 4, 5 ...)
const SPEED_STEP := 0.04         ## +4 % speed per invasion (Exp 006 (B): was 5 %, the base is faster) ...
const SPEED_STEP_MAX := 0.2      ## ... up to +20 % (was 30 %: a late Hard runner stays under the player's sprint)


static func has(kind: String) -> bool:
	return DEFS.has(kind)


static func get_def(kind: String) -> Dictionary:
	return DEFS.get(kind, DEFS["psycho"])


static func value(kind: String, key: String, fallback: Variant = null) -> Variant:
	return get_def(kind).get(key, fallback)


static func cost(kind: String) -> float:
	return float(get_def(kind)["cost"])


static func _difficulty(level: String, key: String, fallback: float) -> float:
	var v: Variant = Difficulty.get_value(level, key)
	return float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else fallback


## The numbers one enemy of `kind` gets in invasion `invasion` (1-based) on
## `level`: {"hp": int, "speed_scale": float (x the archetype speed),
## "damage_scale": float (x GameState.enemy_damage() per player hit),
## "attack_scale": float (x the archetype's attack_interval; Exp 006 (B)),
## "blast_damage": float (bomber, at the centre), "small_damage": float}.
## Difficulty scales hp (enemy_hp), speed (DIFFICULTY_SPEED) and the blast
## (enemy_damage). Melee damage per difficulty and invasion is
## GameState.enemy_damage() (owner K), so damage_scale is the archetype's only.
static func stats(kind: String, level := "normal", invasion := 1) -> Dictionary:
	var d := get_def(kind)
	var lv := Difficulty.valid(level)
	var inv := maxi(invasion, 1)
	var hp_mul := _difficulty(lv, "enemy_hp", 1.0) * (1.0 + HP_STEP * floorf((inv - 1) / 2.0))
	var spd := _difficulty(lv, "enemy_speed", DIFFICULTY_SPEED.get(lv, 1.0))
	spd *= 1.0 + minf(SPEED_STEP * float(inv - 1), SPEED_STEP_MAX)
	var dmg := _difficulty(lv, "enemy_damage", 1.0)
	return {
		"hp": maxi(1, roundi(float(d["hp"]) * hp_mul)),
		"speed_scale": spd,
		"damage_scale": float(d["player_damage"]),
		# Exp 006 (B): swing pace by difficulty (Easy slower, Hard quicker)
		"attack_scale": _difficulty(lv, "enemy_attack_interval", 1.0),
		"blast_damage": float(d.get("blast_damage", 0.0)) * dmg,
		"small_damage": float(d.get("small_damage", 0.0)) * dmg,
	}


## Linear fall-off of a blast: `peak` at the centre, 0 at `reach` and beyond.
static func blast_falloff(dist: float, reach: float) -> float:
	if reach <= 0.0:
		return 0.0
	return clampf(1.0 - dist / reach, 0.0, 1.0)


static func blast_damage_at(dist: float, peak: float, reach: float) -> float:
	return peak * blast_falloff(dist, reach)
