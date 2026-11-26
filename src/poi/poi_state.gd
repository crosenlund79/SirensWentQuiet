class_name PoiState
extends RefCounted
## Experiment 007 (P): what a POI remembers between visits, what its
## containers hold, and how much Eli can carry while away. Pure rules on the
## run's GameState; no nodes.
##
## The record: state.region.poi[id] (RegionState, saved with the run):
##   c        cid -> {"items": {item: n}, "searched": bool, "day": int}
##            every container's contents, generated on the first visit
##   taken    pickup id -> day taken
##   chop     fallen tree id -> chops used
##   forced   door id -> true (a locked door Eli forced stays open)
##   found    one-of-a-kind item -> day Eli took it here (Exp 008 (L): such an
##            item is never generated again anywhere, even once it is stored
##            at home or in the car's boot)
##   visits, last_day, stock0 (the place's stock when the visit began),
##   total (the load of everything left when the visit began)
##   visit    the visit in progress (only while Eli is there): {"day", "car",
##            "pack": {item: n} taken here (counts toward the pack limit),
##            "cargo": {item: n} in the car's boot}
##
## Loot: on the first visit the location's main loot table (ExpeditionData,
## the same profile and rules as the simulated expeditions: difficulty loot
## factor, today's stock, one-of-a-kind items only when not owned, skill
## books only when not known) is rolled ONCE for the whole site, seeded by
## the run seed and the place, and shared out over its containers by what
## each holds; containers marked "locked" share the locked table. So a site
## holds about one expedition's worth; many containers end up empty.
## Revisits: nothing is regenerated. Each searched container may get a
## small refill with chance regen x days x 2 (at most 70 %; the location's
## ExpeditionData regen), taken pickups come back with the same chance, and
## chopped trees regrow (regen x 10 chops a day). Leaving sets the region
## stock (the map) to what is left. What Eli leaves in a container stays
## there (a refill only adds).
## One-of-a-kind items (tools, weapons, gear, books; Items.is_unique) exist
## once in the region (Exp 008 (L), may_find): never generated, refilled or
## put back as a pickup while Eli owns one, has learned the book, has ever
## taken one at a POI (`found`), or one is lying in any POI's container,
## lying as an untaken pickup, or riding in a car's boot.
##
## Carrying while away: what Eli takes at a POI goes into the household pool
## (the inventory and its caps) AND counts toward a pack limit (PACK_BASE
## weight units, x the backpack's carry multiplier when it is equipped). The
## car's boot (CARGO_CAP) is the only other space. Weights: WEIGHTS.

const PACK_BASE := 30.0
const CARGO_CAP := 60.0
const REFILL_MAX := 0.7
const REFILL_MULT := 0.35
const WEIGHTS := {"ammo": 0.1, "shells": 0.2, "nails": 0.05, "snacks": 0.5, "bandage": 0.3, "medkit": 1.0,
	"stone": 2.0, "iron": 1.5, "scrap": 1.0, "wood": 1.0, "fuel": 3.0, "car_battery": 5.0}
const GEAR_WEIGHT := 2.0          ## weapons, tools, gear
const BOOK_WEIGHT := 1.0


# --- the record --------------------------------------------------------------------------

## The live record of POI `id` (created if missing; types cleaned).
static func record(state: GameState, id: String) -> Dictionary:
	if state == null or state.region == null:
		return {}
	var all: Variant = state.region.get("poi")
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var r: Variant = all.get(id)
	if typeof(r) != TYPE_DICTIONARY:
		r = {}
		all[id] = r
	_clean(r)
	return r


static func _int(v: Variant, fallback := 0) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) else fallback


## Cleans a record in place: the dictionaries the game holds on to (a
## container's items, the visit's pack and boot) stay the same objects.
static func _clean(r: Dictionary) -> void:
	var c := _dict_in(r, "c")
	for cid in c.keys():
		var e: Variant = c[cid]
		if typeof(cid) != TYPE_STRING or typeof(e) != TYPE_DICTIONARY:
			c.erase(cid)
			continue
		_items_in(e, "items")
		e["searched"] = e.get("searched", false) == true
		e["day"] = _int(e.get("day"))
	for k in ["taken", "chop", "found"]:
		var d := _dict_in(r, k)
		for key in d.keys():
			if typeof(key) != TYPE_STRING:
				d.erase(key)
			else:
				d[key] = maxi(_int(d[key]), 0)
	var f := _dict_in(r, "forced")
	for key in f.keys():
		if f[key] != true or typeof(key) != TYPE_STRING:
			f.erase(key)
	r["visits"] = maxi(_int(r.get("visits")), 0)
	r["last_day"] = maxi(_int(r.get("last_day")), 0)
	r["stock0"] = clampf(float(r.get("stock0", 1.0)) if typeof(r.get("stock0")) in [TYPE_INT, TYPE_FLOAT] else 1.0, 0.0, 1.0)
	r["total"] = maxf(float(r.get("total", 0.0)) if typeof(r.get("total")) in [TYPE_INT, TYPE_FLOAT] else 0.0, 0.0)
	var vis: Variant = r.get("visit")
	if typeof(vis) == TYPE_DICTIONARY:
		vis["day"] = _int(vis.get("day"))
		vis["car"] = vis.get("car", false) == true
		_items_in(vis, "pack")
		_items_in(vis, "cargo")
	else:
		r.erase("visit")


## r[key] as a Dictionary (replaced by {} when it is something else).
static func _dict_in(r: Dictionary, key: String) -> Dictionary:
	if typeof(r.get(key)) != TYPE_DICTIONARY:
		r[key] = {}
	return r[key]


## r[key] as clean item counts, in place (FurnitureStorage.clean's rules).
static func _items_in(r: Dictionary, key: String) -> void:
	var d := _dict_in(r, key)
	for id in d.keys():
		var n := Inventory.to_count(d[id]) if Items.has(id) else 0
		if n <= 0:
			d.erase(id)
		else:
			d[id] = n


static func generated(r: Dictionary) -> bool:
	return not (r.get("c", {}) as Dictionary).is_empty()


static func in_visit(r: Dictionary) -> bool:
	return r.has("visit")


static func container(r: Dictionary, cid: String) -> Dictionary:
	var c: Dictionary = r.get("c", {})
	if not c.has(cid):
		c[cid] = {"items": {}, "searched": false, "day": 0}
	return c[cid]


# --- visits ------------------------------------------------------------------------------

## Starts a visit (or continues the one in progress, e.g. after loading a save
## made at the POI). First visit: the site is generated; later visits: the
## gradual replenishment. Returns the record.
static func begin_visit(state: GameState, id: String, by_car := false) -> Dictionary:
	var r := record(state, id)
	if r.is_empty() or in_visit(r):
		return r
	var today := state.day()
	if not generated(r):
		generate(state, id, r)
	else:
		replenish(state, id, r, today)
	r["visits"] = int(r["visits"]) + 1
	r["stock0"] = state.region.stock_on(id, today)
	r["total"] = site_load(r)
	r["visit"] = {"day": today, "car": by_car, "pack": {}, "cargo": {}}
	state.region.discover(id)
	return r


## Ends the visit: the place's stock on the map follows what is left (never
## below the location's floor), the visit is counted, the in-progress record
## goes. Returns {"pack", "cargo", "left": 0..1}.
static func finish_visit(state: GameState, id: String) -> Dictionary:
	var r := record(state, id)
	if r.is_empty() or not in_visit(r):
		return {"pack": {}, "cargo": {}, "left": 1.0}
	var today := state.day()
	var v: Dictionary = r["visit"]
	var total := float(r.get("total", 0.0))
	var left := clampf(site_load(r) / total, 0.0, 1.0) if total > 0.0 else 1.0
	var def := PoiDefs.get_def(id)
	state.region.set_stock(id, maxf(float(r.get("stock0", 1.0)) * left, float(def.get("floor", 0.1))), today)
	var note: Dictionary = state.region.call("_note", id)      # visits and last day, as an expedition result would
	note["visits"] = int(note.get("visits", 0)) + 1
	note["last_day"] = today
	r["last_day"] = today
	r.erase("visit")
	return {"pack": v.get("pack", {}), "cargo": v.get("cargo", {}), "left": left}


## Everything left in the site's containers (weight units).
static func site_load(r: Dictionary) -> float:
	var n := 0.0
	for cid in r.get("c", {}):
		n += load_of(r["c"][cid]["items"])
	return n


# --- generation --------------------------------------------------------------------------

static func _seed(state: GameState, parts: Array) -> int:
	return hash([int(state.run.get("seed", 0))] + parts)


## True if a one-of-a-kind item may appear: not owned, a book not yet learned,
## not already lying somewhere in this site, and nowhere else in the region
## (placed_elsewhere: Exp 008 (L)).
static func may_find(state: GameState, r: Dictionary, id: String) -> bool:
	if not Items.is_unique(id):
		return true
	if ExpeditionData.owns(state, id):
		return false
	if Research.is_book(id) and Research.knows(state, Research.book_skill(id)):
		return false
	for cid in r.get("c", {}):
		if int(r["c"][cid]["items"].get(id, 0)) > 0:
			return false
	return not placed_elsewhere(state, id)


## Exp 008 (L): true if one-of-a-kind `id` already exists in the region: Eli
## took one at some POI (stored at home or in the boot since: not "owned"
## any more, but found), one lies in a POI's container or as an untaken
## pickup of a generated POI, or one rides in a car's boot.
static func placed_elsewhere(state: GameState, id: String) -> bool:
	if state == null or state.region == null or typeof(state.region.get("poi")) != TYPE_DICTIONARY:
		return false
	var all: Dictionary = state.region.poi
	for pid in all:
		var r: Variant = all[pid]
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if typeof(r.get("found")) == TYPE_DICTIONARY and (r["found"] as Dictionary).has(id):
			return true
		var c: Variant = r.get("c")
		if typeof(c) == TYPE_DICTIONARY:
			for cid in c:
				var e: Variant = c[cid]
				if typeof(e) == TYPE_DICTIONARY and typeof(e.get("items")) == TYPE_DICTIONARY and int(e["items"].get(id, 0)) > 0:
					return true
		var vis: Variant = r.get("visit")
		if typeof(vis) == TYPE_DICTIONARY and typeof(vis.get("cargo")) == TYPE_DICTIONARY and int(vis["cargo"].get(id, 0)) > 0:
			return true
		if typeof(c) == TYPE_DICTIONARY and not (c as Dictionary).is_empty() and PoiDefs.has(str(pid)):
			var taken: Variant = r.get("taken", {})
			for p in PoiDefs.get_def(str(pid))["layout"].get("pickups", []):
				if str(p["item"]) == id and typeof(taken) == TYPE_DICTIONARY and not (taken as Dictionary).has(p["id"]):
					return true
	return false


## Exp 008 (L): Eli took one-of-a-kind `id` at POI `poi` (the helper's
## pack_add): it is never generated again (may_find).
static func note_found(state: GameState, poi: String, id: String) -> void:
	if not Items.is_unique(id):
		return
	var r := record(state, poi)
	if not r.is_empty():
		(r["found"] as Dictionary)[id] = state.day()


## Rolls a loot table (ExpeditionData entries [id, min, max, chance]) with the
## expedition rules: stackables scale their amounts (stochastic rounding),
## unique items their chance (capped).
static func roll(state: GameState, r: Dictionary, table: Array, mult: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for e in table:
		var id := str(e[0])
		var hit := rng.randf()
		var n := rng.randi_range(int(e[1]), int(e[2]))
		var frac := rng.randf()
		if not Items.has(id):
			continue
		if Items.is_unique(id):
			if may_find(state, r, id) and not out.has(id) and hit < minf(float(e[3]) * minf(mult, 1.5), ExpeditionData.UNIQUE_CHANCE_MAX):
				out[id] = 1
			continue
		if hit >= float(e[3]):
			continue
		var x := float(n) * maxf(mult, 0.0)
		var k := int(floor(x)) + (1 if frac < x - floor(x) else 0)
		if k > 0:
			out[id] = int(out.get(id, 0)) + k
	return out


static func accepts(holds: Array, id: String) -> bool:
	return holds.is_empty() or Items.category(id) in holds


## The first visit: one roll of the main table and one of the locked table,
## shared out over the containers (see the header). Pickups are there in
## proportion to the stock.
static func generate(state: GameState, id: String, r: Dictionary) -> void:
	var def := PoiDefs.get_def(id)
	var L: Dictionary = def["layout"]
	var today := state.day()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(state, [id, "pool"])
	var stock := maxf(state.region.stock_on(id, today), 0.15)
	var mult := ExpeditionData.loot_scale(state) * stock
	var c: Dictionary = r["c"]
	for e in L["containers"]:
		c[e["id"]] = {"items": {}, "searched": false, "day": today}
	var open_ones := (L["containers"] as Array).filter(func(e): return not e["picked"] and e["table"] != "locked")
	var locked_ones := (L["containers"] as Array).filter(func(e): return not e["picked"] and e["table"] == "locked")
	_share(c, roll(state, r, def["loot"], mult, rng), open_ones, rng)
	# rolled after the main share, so a one-of-a-kind item is never in both
	_share(c, roll(state, r, def["locked"], mult, rng), locked_ones if not locked_ones.is_empty() else open_ones, rng)
	var maybe := []
	for p in L["pickups"]:
		var gone := rng.randf() > 0.35 + 0.65 * stock
		if gone or Items.is_unique(str(p["item"])):
			r["taken"][p["id"]] = today
			if not gone:
				maybe.append(p)
	for p in maybe:                        # Exp 008 (L): a one-of-a-kind pickup lies there only while it may be found
		if may_find(state, r, str(p["item"])):
			r["taken"].erase(p["id"])
	r["last_day"] = today


## Shares `pool` out over `boxes` (container entries): each stack in one to
## three parts, each part to a container that holds that kind of item
## (weighted), else to any.
static func _share(c: Dictionary, pool: Dictionary, boxes: Array, rng: RandomNumberGenerator) -> void:
	if boxes.is_empty():
		return
	var ids := pool.keys()
	ids.sort()
	for id in ids:
		var n := int(pool[id])
		var parts := 1 if n <= 2 or Items.is_unique(id) else rng.randi_range(1, mini(3, n))
		var left := n
		for k in parts:
			var part := left if k == parts - 1 else maxi(1, int(round(float(n) / float(parts))))
			part = mini(part, left)
			if part <= 0:
				break
			var b := _pick(boxes, id, rng)
			var items: Dictionary = c[b["id"]]["items"]
			items[id] = int(items.get(id, 0)) + part
			left -= part


static func _pick(boxes: Array, id: String, rng: RandomNumberGenerator) -> Dictionary:
	var fit := boxes.filter(func(b): return accepts(b["holds"], id))
	if fit.is_empty():
		fit = boxes
	var sum := 0.0
	for b in fit:
		sum += float(b["weight"])
	var x := rng.randf() * sum
	for b in fit:
		x -= float(b["weight"])
		if x <= 0.0:
			return b
	return fit[fit.size() - 1]


## A revisit after `days`: limited, gradual replenishment (see the header).
static func replenish(state: GameState, id: String, r: Dictionary, today: int) -> void:
	var days := today - int(r.get("last_day", today))
	if days <= 0:
		return
	var def := PoiDefs.get_def(id)
	var L: Dictionary = def["layout"]
	var regen := float(def.get("regen", 0.02))
	var p := minf(regen * float(days) * 2.0, REFILL_MAX)
	var mult := REFILL_MULT * ExpeditionData.loot_scale(state)
	for e in L["containers"]:
		if e["picked"]:
			continue
		var box := container(r, e["id"])
		if not box["searched"]:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(state, [id, e["id"], "refill", today])
		if rng.randf() >= p:
			continue
		var table: Array = def["locked"] if e["table"] == "locked" else def["loot"]
		var fits := table.filter(func(t): return accepts(e["holds"], str(t[0])))
		var got := roll(state, r, fits, mult, rng)
		FurnitureStorage.merge(box["items"], got)
		box["searched"] = false
		box["day"] = today
	var unique_items := {}
	for q in L.get("pickups", []):
		if Items.is_unique(str(q["item"])):
			unique_items[q["id"]] = str(q["item"])
	for pid in (r["taken"] as Dictionary).keys():
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(state, [id, pid, "pickup", today])
		if rng.randf() < p and (not unique_items.has(pid) or may_find(state, r, unique_items[pid])):
			r["taken"].erase(pid)             # Exp 008 (L): never a second one-of-a-kind item
	var regrow := int(floor(float(days) * regen * 10.0))
	for wid in (r["chop"] as Dictionary).keys():
		r["chop"][wid] = maxi(int(r["chop"][wid]) - regrow, 0)


## Developer: every container back to a fresh roll, pickups and wood back.
static func restore(state: GameState, id: String) -> void:
	var r := record(state, id)
	if r.is_empty():
		return
	var keep: Variant = r.get("visit")
	r["c"] = {}
	r["taken"] = {}
	r["chop"] = {}
	r["forced"] = {}
	state.region.stock.erase(id)
	generate(state, id, r)
	if keep != null:
		r["visit"] = keep
	r["total"] = site_load(r)


# --- carrying ------------------------------------------------------------------------------

static func weight_of(id: String) -> float:
	if WEIGHTS.has(id):
		return float(WEIGHTS[id])
	var cat := Items.category(id)
	if cat == "book":
		return BOOK_WEIGHT
	if Items.is_unique(id):
		return GEAR_WEIGHT
	return 1.0


static func load_of(items: Dictionary) -> float:
	var n := 0.0
	for id in items:
		n += weight_of(str(id)) * maxi(int(items[id]), 0)
	return n


## The pack limit: PACK_BASE, x the carry multiplier with the backpack equipped.
static func pack_cap(state: GameState) -> float:
	var m := 1.0
	if state != null and state.has_method("carry_multiplier"):
		m = maxf(float(state.carry_multiplier()), 1.0)
	return PACK_BASE * m


## What still counts in the pack: what was taken here and is still carried
## (eaten or stowed in the car, it no longer counts).
static func pack_load(state: GameState, pack: Dictionary) -> float:
	var n := 0.0
	for id in pack:
		var k := mini(int(pack[id]), state.inventory.count(id) if state != null else int(pack[id]))
		n += weight_of(str(id)) * maxi(k, 0)
	return n


## How many of `id` fit into `cap` with `used` already in it.
static func room_for(id: String, used: float, cap: float) -> int:
	return maxi(int(floor((cap - used) / weight_of(id) + 1e-6)), 0)


static func pack_text(state: GameState, pack: Dictionary) -> String:
	return "Pack: %s / %s" % [_num(pack_load(state, pack)), _num(pack_cap(state))]


static func _num(x: float) -> String:
	return str(int(round(x))) if absf(x - round(x)) < 0.05 else "%.1f" % x
