class_name Crafting
extends RefCounted
## Processing raw materials (SPEC-003 §2): one example, no crafting tree.
## Owner: K. A workbench (C's world object) calls `convert_scrap(state, n)`.
##
## Rules: every unit is all-or-nothing (3 scrap -> 1 iron); as many units as
## asked are made, limited by the scrap owned and the iron cap (crates raise
## it). The unlimited cheat makes the input free (like GameState.pay); the
## output still respects the cap. A dead player makes nothing.

const RECIPES := {
	"iron": {"name": "Work scrap into iron", "station": "workbench", "in": {"scrap": 3}, "out": {"iron": 1}},
}


static func has(recipe) -> bool:
	return typeof(recipe) == TYPE_STRING and RECIPES.has(recipe)


## How many units of `recipe` could be made right now (inputs and output room).
static func max_units(state: GameState, recipe: String) -> int:
	if state == null or state.dead or not has(recipe):
		return 0
	var r: Dictionary = RECIPES[recipe]
	var n := Inventory.MAX_COUNT
	if not state.cheats.get("unlimited", false):
		for id in r["in"]:
			n = mini(n, state.inventory.count(id) / int(r["in"][id]))
	for id in r["out"]:
		n = mini(n, state.inventory.space_for(id) / int(r["out"][id]))
	return maxi(n, 0)


## Why `recipe` can't be made once ("" = it can).
static func can_process(state: GameState, recipe: String) -> String:
	if state == null or not has(recipe):
		return "Nothing to make."
	if state.dead:
		return "You're dead."
	var r: Dictionary = RECIPES[recipe]
	for id in r["out"]:
		if state.inventory.space_for(id) < int(r["out"][id]):
			return "No room for more %s." % Items.name_of(id).to_lower()
	if not state.can_pay(r["in"]):
		var parts := []
		for id in r["in"]:
			parts.append("%d %s" % [int(r["in"][id]), Items.name_of(id).to_lower()])
		return "You need %s." % ", ".join(parts)
	return ""


## Makes up to `units` of `recipe`. Returns {"ok": bool, "units": int made,
## "used": {id: n}, "made": {id: n}, "reason": String ("" when ok)}.
static func process(state: GameState, recipe: String, units := 1) -> Dictionary:
	var out := {"ok": false, "units": 0, "used": {}, "made": {}, "reason": ""}
	var why := can_process(state, recipe)
	if why != "":
		out["reason"] = why
		return out
	if units <= 0:
		out["reason"] = "Nothing to make."
		return out
	var k := mini(units, max_units(state, recipe))
	var r: Dictionary = RECIPES[recipe]
	var cost := {}
	for id in r["in"]:
		cost[id] = int(r["in"][id]) * k
	if k <= 0 or not state.pay(cost):
		out["reason"] = "Nothing to make."
		return out
	if not state.cheats.get("unlimited", false):
		out["used"] = cost
	for id in r["out"]:
		out["made"][id] = state.inventory.add(id, int(r["out"][id]) * k)
	out["ok"] = true
	out["units"] = k
	return out


## The workbench example: turns 3 * n scrap into n iron (as many as possible).
static func convert_scrap(state: GameState, n := 1) -> Dictionary:
	return process(state, "iron", n)
