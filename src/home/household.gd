class_name Household
extends RefCounted
## Experiment 004 household survival rules (pure, on GameState): drinking at
## the kitchen sink and eating from the fridge. The kitchen interactables in
## game_home.gd call these and show the returned text.
## Each returns {"ok": bool, "text": String}.

const SINK_WATER := 30.0          ## hydration per drink: one bottle's worth
const SINK_MINUTES := 1.0         ## game time a drink takes
const FULL := 99.5


static func drink_from_sink(state: GameState, works := true) -> Dictionary:
	if state == null or state.dead:
		return {"ok": false, "text": ""}
	if not works:
		return {"ok": false, "text": "The tap only coughs. The sink is wrecked."}
	if state.hydration >= FULL:
		return {"ok": false, "text": "You're not thirsty."}
	var before := state.hydration
	state.hydration += SINK_WATER
	state.changed.emit()
	return {"ok": true, "text": "You drink from the tap: water +%d" % roundi(state.hydration - before)}


## The food in the household inventory that fills the most (id, or "").
static func best_food(state: GameState) -> String:
	var best := ""
	var best_v := -1.0
	for id in Items.ids("food"):
		if state.inventory.count(id) <= 0:
			continue
		var v := float(Items.DEFS[id].get("hunger", 0.0))
		if v > best_v:
			best = id
			best_v = v
	return best


static func eat_from_fridge(state: GameState, works := true) -> Dictionary:
	if state == null or state.dead:
		return {"ok": false, "text": ""}
	if not works:
		return {"ok": false, "text": "The fridge is wrecked."}
	var id := best_food(state)
	if id == "":
		return {"ok": false, "text": "The fridge is empty."}
	if state.hunger >= FULL:
		return {"ok": false, "text": "You couldn't eat another bite."}
	var text := state.use_item(id)
	if text == "":
		return {"ok": false, "text": state.can_use(id)}
	return {"ok": true, "text": text}
