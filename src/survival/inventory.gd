class_name Inventory
extends RefCounted
## One shared household inventory (SPEC §7.1). Owner: S. Counts are always
## non-negative ints of known items; removal is all-or-nothing; materials and
## tools are capped (storage crates raise the material caps). A count above its
## cap (a crate was destroyed) is kept; it only blocks further adds.

signal changed

const MAX_COUNT := 99999          ## sanity bound for uncapped items
const MAX_CRATES := 100

var counts := {}
var storage_crates := 0:
	set(v):
		storage_crates = clampi(to_count(v), 0, MAX_CRATES)


## Sanitises an untrusted amount: ints pass, finite floats round, numeric
## strings parse; anything else (null, NaN, arrays, bools...) returns `invalid`.
## The result is clamped to ±MAX_COUNT.
static func to_count(v, invalid := 0) -> int:
	match typeof(v):
		TYPE_INT:
			return clampi(v, -MAX_COUNT, MAX_COUNT)
		TYPE_FLOAT:
			return clampi(roundi(v), -MAX_COUNT, MAX_COUNT) if is_finite(v) else invalid
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v).strip_edges()
			if s.is_valid_int():
				return clampi(s.to_int(), -MAX_COUNT, MAX_COUNT)
			if s.is_valid_float() and is_finite(s.to_float()):
				return clampi(roundi(s.to_float()), -MAX_COUNT, MAX_COUNT)
	return invalid


func count(id) -> int:
	return maxi(to_count(counts.get(str(id), 0)), 0) if Items.has(id) else 0


## 0 = uncapped.
func cap(id) -> int:
	if not Items.has(id):
		return 0
	var d: Dictionary = Items.DEFS[str(id)]
	if not d.has("cap"):
		return 0
	return int(d["cap"]) + int(d.get("cap_per_crate", 0)) * storage_crates


## How many more of `id` fit (0 for unknown items).
func space_for(id) -> int:
	if not Items.has(id):
		return 0
	var c := cap(id)
	return maxi((MAX_COUNT if c == 0 else c) - count(id), 0)


## Adds up to n (respecting the cap); returns how many were added.
func add(id, n) -> int:
	var k := mini(to_count(n), space_for(id))
	if k <= 0:
		return 0
	counts[str(id)] = count(id) + k
	changed.emit()
	return k


## All-or-nothing. Negative or invalid amounts fail; 0 succeeds and changes nothing.
func remove(id, n) -> bool:
	var k := to_count(n, -1)
	if k < 0:
		return false
	if k == 0:
		return true
	if count(id) < k:
		return false
	_take(str(id), k)
	changed.emit()
	return true


## True if every positive amount in `cost` is owned. An invalid amount (not a
## number) can't be paid; zero and negative amounts are ignored.
func has_all(cost: Dictionary) -> bool:
	var c = _clean_cost(cost)
	if c == null:
		return false
	for id in c:
		if count(id) < c[id]:
			return false
	return true


## Removes a whole cost atomically.
func remove_all(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	var c: Dictionary = _clean_cost(cost)
	for id in c:
		_take(id, c[id])
	if not c.is_empty():
		changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"counts": counts.duplicate(), "storage_crates": storage_crates}


## Restores from untrusted data: unknown items, non-numbers and non-positive
## counts are dropped; counts are bounded by MAX_COUNT (not by caps).
func from_dict(d) -> void:
	counts.clear()
	if typeof(d) == TYPE_DICTIONARY:
		storage_crates = maxi(to_count(d.get("storage_crates", 0)), 0)
		var c = d.get("counts", {})
		if typeof(c) == TYPE_DICTIONARY:
			for id in c:
				var n := to_count(c[id])
				if Items.has(id) and n > 0:
					counts[str(id)] = n
	else:
		storage_crates = 0
	changed.emit()


func _take(id: String, n: int) -> void:
	var left := count(id) - n
	if left <= 0:
		counts.erase(id)
	else:
		counts[id] = left


## {id: positive int}; unknown ids keep their amount (so they can't be paid);
## null if any amount is not a number.
func _clean_cost(cost: Dictionary):
	var out := {}
	for id in cost:
		var n := to_count(cost[id], -MAX_COUNT - 1)
		if n == -MAX_COUNT - 1:
			return null
		if n > 0:
			out[str(id)] = int(out.get(str(id), 0)) + n
	return out
