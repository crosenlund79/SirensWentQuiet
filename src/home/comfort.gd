class_name HomeComfort
extends RefCounted
## Experiment 005 (C): the comfort of one room from what it contains and its
## condition. Pure function of a small description (no nodes), so it is cheap
## and testable; game_comfort.gd gathers the description from the worlds.
## Values, caps and thresholds: ComfortCatalog.
##
## comfort = furniture (diminishing per category, capped)
##         + well furnished / bare room + floor finish
##         + light (lamps, daylight through intact windows, darkness)
##         + fireplace warmth (here, or next door)
##         - exposure (a gap to the outside), broken windows, damaged walls,
##           wrecked furniture.
## The level is one of ComfortCatalog.LEVEL_NAMES.

const C := preload("res://src/home/comfort_catalog.gd")


## `info`: {"area", "bbox": Rect2, "storey", "items": [{"type", "state"}],
## "wrecked": int, "lamps": int (lit), "fire": "here" | "near" | "",
## "fireplace": bool (a fireplace stands here, lit or not),
## "windows": {"intact", "broken", "boarded"}, "light": "day" | "dusk" | "night",
## "floor": 0..1 (finished), "exposed": bool, "damaged_walls": int,
## "media": "" | "tv_stand" | "radio" (Exp 006 (B): the playing source that counts here)}.
## Returns {"comfort", "level", "level_name", "label", "factors": [[text, delta]],
## "hints": [text], "exposed": bool, "lit": bool}.
static func evaluate(info: Dictionary) -> Dictionary:
	var items: Array = info.get("items", [])
	var factors := []
	var hints := []
	# --- furniture --------------------------------------------------------------------
	var by_cat := {}
	for it in items:
		var t := str(it.get("type", ""))
		var cat := C.category_of(t)
		var v := C.value_of(t)
		var damaged := str(it.get("state", "intact")) == "damaged"
		if damaged:
			v *= C.DAMAGED_FACTOR
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append({"type": t, "v": v, "damaged": damaged})
	var furniture := 0.0
	var living := 0
	for cat in by_cat:
		var cdef: Dictionary = C.CATEGORIES.get(cat, C.CATEGORIES["other"])
		if float(cdef["cap"]) <= 0.0:
			continue
		var list: Array = by_cat[cat]
		list.sort_custom(func(p, q): return p["v"] > q["v"])
		var sum := 0.0
		var w := 1.0
		for e in list:
			sum += float(e["v"]) * w
			w *= C.DECAY
		var capped := minf(sum, float(cdef["cap"]))
		if capped <= 0.0:
			continue
		furniture += capped
		if cat in C.LIVING_CATEGORIES:
			living += 1
		var names := _names(list)
		var text: String = names if list.size() == 1 else "%s: %s" % [cdef["name"], names]
		if list.size() > 1:
			text += " (more count less)" if capped >= sum - 0.01 else " (full)"
		factors.append([text, capped])
	if furniture > C.FURNITURE_CAP:
		factors.append(["More furniture than a room needs", C.FURNITURE_CAP - furniture])
		furniture = C.FURNITURE_CAP
	var area := float(info.get("area", 0.0))
	var label := label_for(items, bool(info.get("fireplace", false)), area, info.get("bbox", Rect2()))
	if living >= C.WELL_FURNISHED_MIN:
		factors.append(["Well furnished", C.WELL_FURNISHED])
	elif items.is_empty() and label != "Hallway":
		factors.append(["Bare and empty", C.BARE_ROOM])
		hints.append("Bring in some furniture: a chair, a rug, a lamp.")
	# --- floor ------------------------------------------------------------------------
	var fl := float(info.get("floor", 1.0))
	if fl >= C.FLOOR_GOOD:
		factors.append(["Finished floor", C.FINISHED_FLOOR])
	elif fl < C.FLOOR_BAD:
		factors.append(["Bare floor (earth or stone)", C.BARE_FLOOR])
		hints.append("Lay a wooden floor (B, 0).")
	# --- light ------------------------------------------------------------------------
	var light := str(info.get("light", "day"))
	var wins: Dictionary = info.get("windows", {})
	var intact := int(wins.get("intact", 0))
	var broken := int(wins.get("broken", 0))
	var boarded := int(wins.get("boarded", 0))
	var lamps := int(info.get("lamps", 0))
	var fire := str(info.get("fire", ""))
	if lamps > 0:
		var lv := minf(C.LAMP_FIRST + C.LAMP_MORE * (lamps - 1), C.LAMP_CAP)
		if light == "day":
			lv *= C.DAY_LAMP_FACTOR
		factors.append(["Lamp light" if lamps == 1 else "Lamp light (%d lamps)" % lamps, lv])
	var day_k := 1.0 if light == "day" else (0.5 if light == "dusk" else 0.0)
	if intact > 0 and day_k > 0.0:
		var dv := minf(C.DAYLIGHT_FIRST + C.DAYLIGHT_MORE * (intact - 1), C.DAYLIGHT_CAP) * day_k
		factors.append(["Daylight through the window" if intact == 1 else "Daylight through %d windows" % intact, dv])
	elif boarded > 0 and intact == 0 and day_k > 0.0:
		factors.append(["Boarded windows (no daylight)", C.BOARDED_GLOOM])
	var lit := lamps > 0 or fire == "here" or (intact > 0 and day_k > 0.0)
	if not lit:
		if light == "day":
			factors.append(["Dark: no window or lamp", C.DARK_DAY])
		else:
			factors.append(["Dark at night", C.DARK_NIGHT])
		hints.append("A lamp would help here.")
	# --- Exp 006 (B): a TV or radio playing (one per room; HouseMedia caps the house) ---
	var mf := HouseMedia.factor(str(info.get("media", "")))
	if not mf.is_empty():
		factors.append(mf)
	# --- warmth -----------------------------------------------------------------------
	if fire == "here":
		factors.append(["Fireplace warmth", C.FIRE_HERE])
	elif fire == "near":
		factors.append(["Warmth from the fireplace next door", C.FIRE_NEAR])
	# --- condition --------------------------------------------------------------------
	var exposed := bool(info.get("exposed", false))
	if exposed:
		factors.append(["Open to the outside", C.EXPOSED])
		hints.append("Close the gap to the outside with a wall or a door (B).")
	if broken > 0:
		var bv := maxf(C.BROKEN_WINDOW_FIRST + C.BROKEN_WINDOW_MORE * (broken - 1), C.BROKEN_WINDOW_CAP)
		factors.append(["Broken window" if broken == 1 else "%d broken windows" % broken, bv])
		hints.append("Board up the broken window (B, 2) or repair it (B, 7).")
	var dw := int(info.get("damaged_walls", 0))
	if dw > 0:
		factors.append(["Damaged walls" if dw > 1 else "A damaged wall", maxf(C.DAMAGED_WALL * dw, C.DAMAGED_WALL_CAP)])
		if hints.size() < 2:
			hints.append("Repair the walls (B, 7).")
	var wr := int(info.get("wrecked", 0))
	if wr > 0:
		factors.append(["Wrecked furniture" if wr > 1 else "A wrecked piece of furniture", maxf(C.WRECKED * wr, C.WRECKED_CAP)])
	# --- small hints for a better room ------------------------------------------------
	if hints.size() < 2 and not items.is_empty():
		if not by_cat.has("rug") and area >= 6.0:
			hints.append("A rug would make it warmer.")
		elif not by_cat.has("decor") and label in ["Bedroom", "Living room", "Kitchen & living room"]:
			hints.append("A painting or a plant would make it homelier.")
	var total := 0.0
	for f in factors:
		total += float(f[1])
	var lvl := C.level_of(total)
	return {"comfort": total, "level": lvl, "level_name": C.LEVEL_NAMES[lvl], "label": label, "factors": factors,
		"hints": hints.slice(0, 2), "exposed": exposed or broken > 0, "lit": lit, "furnished": not items.is_empty()}


## The room's name from what's in it (no elaborate classifier: the player may
## build any layout). A fireplace makes a living room.
static func label_for(items: Array, fireplace: bool, area: float, bbox: Rect2) -> String:
	var types := {}
	var storage := 0
	for it in items:
		var t := str(it.get("type", ""))
		types[t] = true
		if C.category_of(t) == "storage":
			storage += 1
	var has := func(list: Array) -> bool:
		for t in list:
			if types.has(t):
				return true
		return false
	if has.call(C.BED_TYPES):
		return "Bedroom"
	var kitchen: bool = has.call(C.KITCHEN_TYPES)
	var living: bool = fireplace or has.call(C.LIVING_TYPES)
	if kitchen and living:
		return "Kitchen & living room"
	if kitchen:
		return "Kitchen"
	if living:
		return "Living room"
	if has.call(C.BATH_TYPES):
		return "Bathroom"
	if has.call(C.WORK_TYPES):
		return "Workshop"
	if storage >= C.STORAGE_FOR_ROOM:
		return "Storage room"
	if area <= C.HALLWAY_MAX_AREA and minf(bbox.size.x, bbox.size.y) <= C.HALLWAY_MAX_WIDTH:
		return "Hallway"
	return "Room"


static func _names(list: Array) -> String:
	var counts := {}
	var order := []
	var damaged := false
	for e in list:
		var t: String = e["type"]
		if not counts.has(t):
			counts[t] = 0
			order.append(t)
		counts[t] += 1
		damaged = damaged or e["damaged"]
	var parts := []
	for t in order:
		parts.append(C.type_name(t, counts[t]).to_lower() if parts.size() > 0 else C.type_name(t, counts[t]))
	return ", ".join(parts) + (" (damaged)" if damaged else "")


## House comfort: the rooms' comfort weighted by size (clamped) and by what
## they are for (ComfortCatalog.LABEL_WEIGHT); empty rooms (unfinished space,
## a fresh basement) weigh EMPTY_WEIGHT, so expanding the house doesn't sour
## it. `rooms`: [{"comfort", "area", "label", "furnished"}]. With no rooms at
## all: NO_SHELTER.
const NO_SHELTER := -10.0
const EMPTY_WEIGHT := 0.35

static func house_value(rooms: Array) -> float:
	var sum := 0.0
	var wsum := 0.0
	for r in rooms:
		var w := clampf(float(r.get("area", 0.0)) / 12.0, 0.4, 1.5) * float(C.LABEL_WEIGHT.get(str(r.get("label", "Room")), 0.7))
		if not bool(r.get("furnished", true)):
			w *= EMPTY_WEIGHT
		sum += float(r.get("comfort", 0.0)) * w
		wsum += w
	return sum / wsum if wsum > 0.0 else NO_SHELTER
