class_name Hotbar
extends RefCounted
## The quick-access bar (Experiment 004, E): eight slots of item ids at the
## bottom of the screen, selected with 1-8. Pure rules on a small Dictionary
## that GameState keeps (`GameState.hotbar`, saved as an optional field):
##   {"slots": [8 item ids or ""], "selected": 0..7, "holstered": bool,
##    "known": [ids the bar has placed once]}
## The slots hold ids, not counts: a consumable that runs out keeps its place
## (shown empty) and comes back to it when more is found. Filling is automatic
## and stable: the two equipped weapons go to 1 and 2, then newly owned items
## from Items.BAR_AUTO take the first free slot; an item the bar placed once is
## never put back by itself after the player removed it ("known").
## The game helper src/game/game_hotbar.gd does the input, the use and the
## weapon in hand; docs: docs/experiment-004/e_bar_car_menu.md.

const SIZE := 8
const HOLDABLE := ["weapon", "tool", "utility", "protective", "food", "water", "medical"]


static func new_bar() -> Dictionary:
	var slots := []
	slots.resize(SIZE)
	slots.fill("")
	return {"slots": slots, "selected": 0, "holstered": false, "known": []}


## A bar from untrusted (saved) data: unknown ids dropped, each id once.
static func clean(v) -> Dictionary:
	var b := new_bar()
	if typeof(v) != TYPE_DICTIONARY:
		return b
	var s = v.get("slots", [])
	if typeof(s) == TYPE_ARRAY:
		for i in mini(s.size(), SIZE):
			var id = s[i]
			if typeof(id) == TYPE_STRING and can_hold(id) and not id in b["slots"]:
				b["slots"][i] = id
	var sel = v.get("selected", 0)
	b["selected"] = clampi(int(sel) if typeof(sel) in [TYPE_INT, TYPE_FLOAT] else 0, 0, SIZE - 1)
	b["holstered"] = typeof(v.get("holstered")) == TYPE_BOOL and v["holstered"]
	var k = v.get("known", [])
	if typeof(k) == TYPE_ARRAY:
		for id in k:
			if typeof(id) == TYPE_STRING and Items.has(id) and not id in b["known"]:
				b["known"].append(id)
	return b


## Items that can sit on the bar: weapons, tools, gear and consumables.
static func can_hold(id) -> bool:
	return Items.has(id) and Items.category(id) in HOLDABLE


## What using `id` does: "weapon", "consume", "hammer", "flashlight",
## "shovel", "crowbar", "gear" (equip / unequip), or "" (nothing).
static func use_kind(id) -> String:
	if not Items.has(id):
		return ""
	if WeaponDefs.has(id):
		return "weapon"
	if Items.is_consumable(id):
		return "consume"
	if id in ["hammer", "flashlight", "shovel", "crowbar"]:
		return str(id)
	if Equipment.is_equippable(id):
		return "gear"
	return ""


## Places the equipped weapons (1 = primary, 2 = secondary) and newly owned
## Items.BAR_AUTO items in free slots, keeping everything else where it is.
## Returns true when the bar changed.
static func fill(bar: Dictionary, s: GameState) -> bool:
	var slots: Array = bar["slots"]
	var known: Array = bar["known"]
	var changed := false
	var wanted := []
	for ws in Equipment.WEAPON_SLOTS:
		var w := s.equipped(ws)
		if w != "":
			wanted.append(w)
	for id in WeaponDefs.ids():
		if s.inventory.count(id) > 0 and not id in wanted:
			wanted.append(id)
	for id in Items.BAR_AUTO:
		if s.inventory.count(id) > 0:
			wanted.append(id)
	for id in wanted:
		if id in slots or id in known:
			continue
		var at := -1
		if WeaponDefs.has(id):
			for i in [0, 1]:
				if slots[i] == "":
					at = i
					break
		if at < 0:
			for i in range(2, SIZE):
				if slots[i] == "":
					at = i
					break
		if at < 0:
			for i in SIZE:
				if slots[i] == "":
					at = i
					break
		if at < 0:
			break
		slots[at] = id
		known.append(id)
		changed = true
	return changed


## Puts `id` in slot `i` (the item leaves the slot it was in; the item in `i`
## moves there, so nothing is lost). "" clears the slot. Returns "" or a reason.
static func assign(bar: Dictionary, i: int, id: String) -> String:
	if i < 0 or i >= SIZE:
		return "No such slot."
	if id != "" and not can_hold(id):
		return "%s can't go on the bar." % Items.name_of(id)
	var slots: Array = bar["slots"]
	var prev: String = slots[i]
	var from := slots.find(id) if id != "" else -1
	slots[i] = id
	if from >= 0 and from != i:
		slots[from] = prev
	if id != "" and not id in bar["known"]:
		bar["known"].append(id)
	return ""


## The id in slot `i` ("" for an empty or unknown slot).
static func at(bar: Dictionary, i: int) -> String:
	return str(bar["slots"][i]) if i >= 0 and i < SIZE else ""


## The slot holding `id`, or -1.
static func slot_of(bar: Dictionary, id: String) -> int:
	return (bar["slots"] as Array).find(id) if id != "" else -1


## The item in hand: the selected slot's item when owned and not holstered.
static func in_hand(bar: Dictionary, s: GameState) -> String:
	if bar.get("holstered", false):
		return ""
	var id := at(bar, int(bar.get("selected", 0)))
	return id if id != "" and s.inventory.count(id) > 0 else ""


## How many the slot shows: the count for consumables, the rounds in the
## magazine for weapons, -1 for gear (no number).
static func count_for(id: String, s: GameState) -> int:
	if id == "" or not Items.has(id):
		return -1
	if WeaponDefs.has(id):
		return s.magazine(id) if s.inventory.count(id) > 0 else -1
	if Items.is_unique(id):
		return -1
	return s.inventory.count(id)


## The next slot after `from` holding an owned weapon, or -1.
static func next_weapon_slot(bar: Dictionary, s: GameState, from: int) -> int:
	for k in range(1, SIZE + 1):
		var i := (from + k) % SIZE
		var id := at(bar, i)
		if WeaponDefs.has(id) and s.inventory.count(id) > 0:
			return i
	return -1
