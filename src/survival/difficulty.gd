class_name Difficulty
extends RefCounted
## Easy / Normal / Hard (SPEC-003 §5). Owner: K; read by the enemy director
## (AI), the expedition system (X) and the game. Multipliers apply to the
## Experiment 002 baseline numbers. GameState applies the survival-core ones:
##   start_rounds                 new_run: rounds in the handgun's magazine (no reserve)
##   enemy_damage                 GameState.enemy_damage() (before the vest)
##   enemy_count, enemy_hp        GameState.invasion_size() / invasion_enemy_hp() (the
##                                Experiment 002 director); enemy_hp_scale() for archetypes
##   first_invasion_day,
##   invasion_interval_days       the invasion grid (GameState._invasion_slot_after)
## The rest (threat budget, bombers, specials, loot, scavenge_danger) is read by
## AI and X directly.

const LEVELS := ["easy", "normal", "hard"]
const DEFAULT := "normal"

const DEFS := {
	"easy": {
		"name": "Easy", "desc": "More supplies, gentler invasions. Room to learn.",
		"enemy_count": 0.75, "enemy_hp": 0.8, "enemy_damage": 0.7,
		"invasion_interval_days": 4, "first_invasion_day": 4,
		"threat_budget": 3.0, "threat_budget_step": 1.5,
		"bomber_from_invasion": 4,      ## never in the opening days on Easy
		"special_from_invasion": 2,     ## runners / brutes from this invasion
		"loot": 1.25, "scavenge_danger": 0.8, "start_rounds": 12,
	},
	"normal": {
		"name": "Normal", "desc": "The intended experience.",
		"enemy_count": 1.0, "enemy_hp": 1.0, "enemy_damage": 1.0,
		"invasion_interval_days": 3, "first_invasion_day": 3,
		"threat_budget": 4.0, "threat_budget_step": 2.5,
		"bomber_from_invasion": 3,
		"special_from_invasion": 1,
		"loot": 1.0, "scavenge_danger": 1.0, "start_rounds": 9,
	},
	"hard": {
		"name": "Hard", "desc": "Scarce supplies, frequent and mixed invasions, bombers early.",
		"enemy_count": 1.3, "enemy_hp": 1.25, "enemy_damage": 1.3,
		"invasion_interval_days": 2, "first_invasion_day": 2,
		"threat_budget": 5.0, "threat_budget_step": 3.5,
		"bomber_from_invasion": 2,
		"special_from_invasion": 1,
		"loot": 0.8, "scavenge_danger": 1.25, "start_rounds": 9,
	},
}


static func valid(level: String) -> String:
	return level if DEFS.has(level) else DEFAULT


static func get_value(level: String, key: String) -> Variant:
	return DEFS[valid(level)].get(key)


static func name_of(level: String) -> String:
	return DEFS[valid(level)]["name"]


static func desc_of(level: String) -> String:
	return DEFS[valid(level)]["desc"]


static func start_rounds(level: String) -> int:
	return int(get_value(level, "start_rounds"))
