class_name Inventory
extends RefCounted
## One shared household inventory (SPEC §7.1). Owner: S. Counts are always
## non-negative ints; removal is all-or-nothing; materials are capped
## (storage crates raise the caps).

signal changed

var counts := {}
var storage_crates := 0:
	set(v):
		storage_crates = maxi(v, 0)


func count(id: String) -> int:
	return int(counts.get(id, 0))


## 0 = uncapped.
func cap(id: String) -> int:
	var d: Dictionary = Items.DEFS.get(id, {})
	if not d.has("cap"):
		return 0
	return int(d["cap"]) + int(d.get("cap_per_crate", 0)) * storage_crates


func space_for(id: String) -> int:
	var c := cap(id)
	return 1 << 30 if c == 0 else maxi(c - count(id), 0)


## Adds up to n (respecting the cap); returns how many were added.
func add(id: String, n: int) -> int:
	if n <= 0 or not Items.has(id):
		return 0
	var k := mini(n, space_for(id))
	if k > 0:
		counts[id] = count(id) + k
		changed.emit()
	return k


## All-or-nothing.
func remove(id: String, n: int) -> bool:
	if n < 0:
		return false
	if n == 0:
		return true
	if count(id) < n:
		return false
	var left := count(id) - n
	if left == 0:
		counts.erase(id)
	else:
		counts[id] = left
	changed.emit()
	return true


func has_all(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < int(cost[id]):
			return false
	return true


## Removes a whole cost atomically.
func remove_all(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id in cost:
		var n := int(cost[id])
		if n > 0:
			var left := count(id) - n
			if left == 0:
				counts.erase(id)
			else:
				counts[id] = left
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"counts": counts.duplicate(), "storage_crates": storage_crates}


func from_dict(d: Dictionary) -> void:
	counts.clear()
	var c: Dictionary = d.get("counts", {})
	for id in c:
		var n := int(c[id])
		if Items.has(str(id)) and n > 0:
			counts[str(id)] = n
	storage_crates = int(d.get("storage_crates", 0))
	changed.emit()
