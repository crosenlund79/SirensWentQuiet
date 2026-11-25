class_name HouseSupply
extends RefCounted
## Exp 006 (B): construction materials from the household pool plus the
## house's storage furniture (SPEC §3, the user's §13).
##
## Building, repairing, upgrading and reinforcing (everything BuildMode
## charges) pay from what you carry first, then from the eligible containers
## in the house: every storage piece of furniture on every storey (original
## pieces that stand and placed ones; HouseWorld.containers()), never loot
## piles. Eating, the quick bar, crafting and expeditions still use only
## what you carry (FurnitureStorage's rule stays for them).
##
##   available(item) -> int        carried + stored
##   stored(item) -> int           in the house's containers
##   can_pay(cost) -> bool
##   pay(cost) -> bool             atomic: the pool first, then the containers
##                                 in a fixed order; nothing is taken when the
##                                 whole cost isn't there. `last_paid` says what
##                                 came from where.
##   give(refund) -> {"inv", "stored"}   refunds go to the pool (its caps);
##                                 what doesn't fit goes into a container that
##                                 takes it, else it is lost as before
## The unlimited cheat pays nothing (and creates nothing), as GameState.pay.
## `worlds_fn` returns the storeys' HouseWorlds (anything with containers()).

const SKIP_TYPES := ["loot_pile"]

var state: GameState
var worlds_fn: Callable
## What the last pay() took: {"inventory": {item: n}, "stored": {item: n}}.
var last_paid := {"inventory": {}, "stored": {}}


func _init(s: GameState = null, fn := Callable()) -> void:
	state = s
	worlds_fn = fn


func worlds() -> Array:
	if worlds_fn.is_valid():
		var w: Variant = worlds_fn.call()
		if w is Array:
			return w
	return []


## The eligible containers, in payment order (storey by storey as worlds()
## lists them, then each world's own order): [{"id", "type", "items" (live)}].
func containers() -> Array:
	var out := []
	for w in worlds():
		if w == null or not is_instance_valid(w) or not w.has_method("containers"):
			continue
		for c in w.call("containers"):
			var t := str(c.get("type", ""))
			if t in SKIP_TYPES or not FurnitureStorage.is_storage(t) or not (c.get("items") is Dictionary):
				continue
			out.append(c)
	return out


func _unlimited() -> bool:
	return state != null and state.cheats.get("unlimited", false)


func carried(item: String) -> int:
	return state.inventory.count(item) if state != null else 0


func stored(item: String) -> int:
	var n := 0
	for c in containers():
		n += maxi(int(c["items"].get(item, 0)), 0)
	return n


func available(item: String) -> int:
	return carried(item) + stored(item)


## {item: stored count} for every item in the house's containers.
func stored_all() -> Dictionary:
	var out := {}
	for c in containers():
		for id in c["items"]:
			out[id] = int(out.get(id, 0)) + maxi(int(c["items"][id]), 0)
	return out


func can_pay(cost: Dictionary) -> bool:
	if cost.is_empty() or _unlimited():
		return true
	if state == null:
		return false
	var all := stored_all()
	for k in cost:
		var need := int(cost[k])
		if need < 0:
			return false
		if need > 0 and carried(k) + int(all.get(k, 0)) < need:
			return false
	return true


## The split of `cost` without taking anything: {"inventory": {item: n},
## "stored": [[container, item, n], ...]} or {} if it can't be paid.
func plan(cost: Dictionary) -> Dictionary:
	if not can_pay(cost):
		return {}
	var inv := {}
	var from := []
	var conts := containers()
	for k in cost:
		var need := int(cost[k])
		if need <= 0:
			continue
		var mine := mini(need, carried(k))
		if mine > 0:
			inv[k] = mine
		need -= mine
		for c in conts:
			if need <= 0:
				break
			var have := maxi(int(c["items"].get(k, 0)), 0)
			var take := mini(have, need)
			if take > 0:
				from.append([c, k, take])
				need -= take
		if need > 0:
			return {}
	return {"inventory": inv, "stored": from}


## Pays `cost` atomically: the carried part first (all or nothing), then the
## containers. Returns false, having taken nothing, if it can't be paid.
func pay(cost: Dictionary) -> bool:
	last_paid = {"inventory": {}, "stored": {}}
	if cost.is_empty() or _unlimited():
		return true
	var p := plan(cost)
	if p.is_empty():
		return false
	if not p["inventory"].is_empty() and not state.inventory.remove_all(p["inventory"]):
		return false
	for e in p["stored"]:
		var items: Dictionary = e[0]["items"]
		var left := int(items.get(e[1], 0)) - int(e[2])
		if left <= 0:
			items.erase(e[1])
		else:
			items[e[1]] = left
		last_paid["stored"][e[1]] = int(last_paid["stored"].get(e[1], 0)) + int(e[2])
	last_paid["inventory"] = p["inventory"].duplicate()
	if not p["stored"].is_empty():
		state.changed.emit()
	return true


## Gives a refund back: into the pool as far as its caps allow, the rest into
## the first container that takes it. Returns {"inv": {..}, "stored": {..}}.
func give(refund: Dictionary) -> Dictionary:
	var got := {}
	var put := {}
	if refund.is_empty() or state == null or _unlimited():
		return {"inv": got, "stored": put}
	var conts := []
	for k in refund:
		var n := int(refund[k])
		if n <= 0:
			continue
		var a := state.inventory.add(k, n)
		if a > 0:
			got[k] = a
		var rest := n - a
		if rest <= 0:
			continue
		if conts.is_empty():
			conts = containers()
		for c in conts:
			if rest <= 0:
				break
			var t := str(c["type"])
			if not FurnitureStorage.accepts(t, k):
				continue
			var room := mini(rest, FurnitureStorage.space_left(t, c["items"]))
			if room > 0:
				c["items"][k] = int(c["items"].get(k, 0)) + room
				put[k] = int(put.get(k, 0)) + room
				rest -= room
	return {"inv": got, "stored": put}


## "12" or "12 + 30 stored" for the build menu.
func count_text(item: String) -> String:
	var c := carried(item)
	var s := stored(item)
	return "%d + %d stored" % [c, s] if s > 0 else str(c)
