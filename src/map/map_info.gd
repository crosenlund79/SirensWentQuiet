class_name MapInfo
extends RefCounted
## Gameplay text for the region map's info panel (SPEC-003 §6). Owner: M.
##
## summary(id, state) returns one normalised Dictionary for the panel. When
## the expedition module provides ExpeditionData.location_summary(id, state)
## (X's API, detected with has_method), its data is used; otherwise a local
## fallback built only from RegionLocations and RegionState fills the same
## keys. Keys (all present):
##   id, name, category, category_name, district, district_name, desc,
##   travel_minutes, km, search_minutes (0 = unknown), minutes (0 = unknown),
##   risk_name, risk_tier (0..3), resources_text, targets [item ids],
##   equipment [{id, name, effect, have, equipped, required}] (equipped: it
##     comes along on a trip, X's can_bring),
##   approaches [{id, name, short, desc, available, reason, minutes, risk_name}],
##   stock (0..1), stock_text, notes [String], available, reason,
##   source ("expedition" | "map").

const HOME := "home"
const RISK_NAMES := ["Low", "Moderate", "High", "Severe"]
const APPROACH_ORDER := ["general", "targeted", "careful", "raid"]
## Same ids and names as the expedition module's approaches.
const APPROACHES := {
	"general": {"name": "General scavenging", "short": "A bit of everything",
		"desc": "Search the place for whatever is useful."},
	"targeted": {"name": "Targeted collection", "short": "Much more of one thing",
		"desc": "Go straight for one resource: much more of it, little of anything else."},
	"careful": {"name": "Careful exploration", "short": "Slower, safer, finds new places",
		"desc": "Slow and quiet: safer, a little less loot, and a chance to find new places for the map."},
	"raid": {"name": "High-risk raid", "short": "Fast and loud: more loot, more danger",
		"desc": "In fast and loud with a loaded weapon: more loot in less time, far more danger."},
}
## Map colours per category (markers, legend, list dots).
const CATEGORY_COLORS := {
	"construction": Color(0.88, 0.67, 0.36), "weapons": Color(0.9, 0.42, 0.34), "medical": Color(0.5, 0.8, 0.76),
	"food": Color(0.68, 0.8, 0.46), "residential": Color(0.64, 0.74, 0.9), HOME: Color(0.95, 0.62, 0.22),
}

# --- local fallback data (used only until the expedition module provides its own) ---
const FALLBACK_RISK := {"residential": 0, "food": 1, "medical": 1, "construction": 1, "weapons": 2}
const FALLBACK_RISK_ID := {"convenience": 0, "logging": 0, "homes": 0, "hospital": 2, "scrapyard": 2,
	"police": 2, "gun_shop": 2, "military": 3}
const FALLBACK_RESOURCES := {
	"residential": "A little of everything: food, water, planks and nails; sometimes ammunition.",
	"food": "Canned food, snacks and bottled water.",
	"medical": "Bandages and first-aid kits.",
	"weapons": "Ammunition and protective gear; rarely a weapon.",
	"logging": "Wood.", "sawmill": "Planks and tools.", "quarry": "Stone.",
	"construction_site": "Wood, stone and iron.", "scrapyard": "Scrap and iron.",
	"warehouse": "Mixed materials.", "hardware": "Planks, nails and tools.",
}
const FALLBACK_EQUIPMENT := {
	"backpack": "Carry more back.",
	"flashlight": "Dark interiors: safer with a light.",
	"crowbar": "Opens locked stockrooms and doors.",
	"vest": "Less damage when it goes wrong.",
}


## Normalised info for a location id (or HOME) for the given state (may be null).
static func summary(id: String, state: GameState) -> Dictionary:
	if id == HOME:
		return home_summary()
	if not RegionLocations.has(id):
		return {}
	var base := fallback(id, state)
	var ed: Variant = ExpeditionData
	if ed != null and (ed as Object).has_method("location_summary"):
		var x: Variant = (ed as Object).call("location_summary", id, state)
		if typeof(x) == TYPE_DICTIONARY and not (x as Dictionary).is_empty():
			return normalize(x, base)
	return base


static func home_summary() -> Dictionary:
	return {"id": HOME, "name": "Your house", "category": HOME, "category_name": "Home",
		"district": "suburbs", "district_name": RegionLocations.DISTRICTS.get("suburbs", ""),
		"desc": "Your house on the south-western edge of town. The lot is ringed by fog: walk into it to set out.",
		"travel_minutes": 0, "km": 0.0, "search_minutes": 0, "minutes": 0, "risk_name": "", "risk_tier": -1,
		"resources_text": "", "targets": [], "equipment": [], "approaches": [], "stock": 1.0, "stock_text": "",
		"notes": [], "available": false, "reason": "", "source": "map"}


## The fallback: RegionLocations + RegionState only.
static func fallback(id: String, state: GameState) -> Dictionary:
	var d := RegionLocations.get_def(id)
	var cat := str(d.get("category", ""))
	var tier := int(FALLBACK_RISK_ID.get(id, FALLBACK_RISK.get(cat, 1)))
	var eq := []
	var eq_ids := ["backpack"]
	match cat:
		"medical", "weapons":
			eq_ids.append_array(["flashlight", "vest"])
		_:
			eq_ids.append("crowbar")
	for g in eq_ids:
		var have := owns(state, g)
		eq.append({"id": g, "name": Items.name_of(g), "effect": FALLBACK_EQUIPMENT.get(g, ""), "have": have, "equipped": have, "required": false})
	var aps := []
	for a in APPROACH_ORDER:
		var ad: Dictionary = APPROACHES[a]
		aps.append({"id": a, "name": ad["name"], "short": ad["short"], "desc": ad["desc"], "available": true, "reason": "",
			"minutes": 0, "risk_name": ""})
	var stock := today_stock(state, id)
	return {
		"id": id, "name": str(d.get("name", id)), "category": cat,
		"category_name": str(RegionLocations.CATEGORIES.get(cat, cat)),
		"district": str(d.get("district", "")), "district_name": str(RegionLocations.DISTRICTS.get(d.get("district", ""), "")),
		"desc": str(d.get("desc", "")),
		"travel_minutes": RegionLocations.travel_minutes(id), "km": RegionLocations.distance_km(id),
		"search_minutes": 0, "minutes": 0,
		"risk_name": RISK_NAMES[tier], "risk_tier": tier,
		"resources_text": str(FALLBACK_RESOURCES.get(id, FALLBACK_RESOURCES.get(cat, ""))),
		"targets": [], "equipment": eq, "approaches": aps,
		"stock": stock, "stock_text": stock_text(stock), "notes": [],
		"available": true, "reason": "", "source": "map",
	}


## Reads the expedition module's summary over the fallback (tolerant of
## missing or differently typed fields).
static func normalize(x: Dictionary, base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	out["source"] = "expedition"
	for k in ["name", "category", "category_name", "district", "desc", "stock_text", "reason"]:
		if x.has(k) and str(x[k]) != "":
			out[k] = str(x[k])
	out["district_name"] = str(RegionLocations.DISTRICTS.get(out["district"], out["district_name"]))
	for k in ["travel_minutes", "search_minutes", "minutes"]:
		if typeof(x.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			out[k] = int(x[k])
	if typeof(x.get("stock")) in [TYPE_INT, TYPE_FLOAT]:
		out["stock"] = clampf(float(x["stock"]), 0.0, 1.0)
	if typeof(x.get("available")) == TYPE_BOOL:
		out["available"] = x["available"]
	var rn := str(x.get("risk_name", x.get("risk", "")))
	if rn != "" and RISK_NAMES.has(rn):
		out["risk_name"] = rn
		out["risk_tier"] = RISK_NAMES.find(rn)
	var rewards := str(x.get("rewards", ""))
	if rewards != "":
		out["resources_text"] = rewards
	elif typeof(x.get("resources")) == TYPE_ARRAY and not (x["resources"] as Array).is_empty():
		out["resources_text"] = items_text(x["resources"])
	if typeof(x.get("targets")) == TYPE_ARRAY:
		out["targets"] = (x["targets"] as Array).map(func(v): return str(v))
	if typeof(x.get("notes")) == TYPE_ARRAY:
		out["notes"] = (x["notes"] as Array).map(func(v): return str(v))
	elif typeof(x.get("notes")) == TYPE_STRING and str(x["notes"]) != "":
		out["notes"] = [str(x["notes"])]
	if typeof(x.get("equipment")) == TYPE_ARRAY:
		var eq := []
		for e in x["equipment"]:
			if typeof(e) == TYPE_DICTIONARY:
				var gid := str(e.get("id", ""))
				var have := bool(e.get("have", false))
				eq.append({"id": gid, "name": str(e.get("name", Items.name_of(gid))), "effect": str(e.get("effect", "")),
					"have": have, "equipped": bool(e.get("equipped", have)), "required": bool(e.get("required", false))})
			elif typeof(e) == TYPE_STRING:
				eq.append({"id": e, "name": Items.name_of(e), "effect": "", "have": false, "equipped": false, "required": false})
		out["equipment"] = eq
	if typeof(x.get("approaches")) == TYPE_ARRAY and not (x["approaches"] as Array).is_empty():
		var aps := []
		for a in x["approaches"]:
			if typeof(a) != TYPE_DICTIONARY or str(a.get("id", "")) == "":
				continue
			var aid := str(a["id"])
			var fb: Dictionary = APPROACHES.get(aid, {"name": aid.capitalize(), "short": "", "desc": ""})
			aps.append({"id": aid, "name": str(a.get("name", fb["name"])), "short": str(a.get("short", fb["short"])),
				"desc": str(a.get("desc", fb["desc"])), "available": bool(a.get("available", true)),
				"reason": str(a.get("reason", "")), "minutes": int(a.get("minutes", 0)) if typeof(a.get("minutes")) in [TYPE_INT, TYPE_FLOAT] else 0,
				"risk_name": str(a.get("risk_name", ""))})
		if not aps.is_empty():
			out["approaches"] = aps
	return out


## Today's stock (RegionState.stock_on with recovery when the region has it).
static func today_stock(state: GameState, id: String) -> float:
	if state == null or state.region == null:
		return 1.0
	if state.region.has_method("stock_on"):
		return float(state.region.call("stock_on", id, state.day()))
	return state.region.stock_of(id)


## Sets a place's stock as left today (RegionState.set_stock when present;
## previews and tests).
static func set_stock(state: GameState, id: String, value: float) -> void:
	if state.region.has_method("set_stock"):
		state.region.call("set_stock", id, value, state.day())
	else:
		state.region.stock[id] = value


static func owns(state: GameState, item: String) -> bool:
	if state == null:
		return false
	if state.inventory != null and state.inventory.count(item) > 0:
		return true
	return item in state.equipment.values()


static func stock_text(stock: float) -> String:
	if stock >= 0.85:
		return "Untouched"
	if stock >= 0.5:
		return "Picked over"
	if stock >= 0.25:
		return "Mostly stripped"
	return "Picked clean"


static func items_text(ids: Array) -> String:
	var names := []
	for i in ids:
		names.append(Items.name_of(str(i)))
	return ", ".join(names) + "."


static func risk_color(tier: int) -> Color:
	match tier:
		0:
			return UiTheme.GOOD
		1:
			return UiTheme.TEXT
		2:
			return UiTheme.WARN
		3:
			return UiTheme.BAD
	return UiTheme.TEXT_DIM


static func category_color(cat: String) -> Color:
	return CATEGORY_COLORS.get(cat, UiTheme.TEXT)


## Splits a plan purpose ("careful", "targeted:wood") into [approach, target].
static func split_purpose(purpose: String) -> Array:
	var parts := purpose.split(":", true, 1)
	var a := parts[0] if parts.size() > 0 else ""
	return [a if APPROACHES.has(a) else "general", parts[1] if parts.size() > 1 else ""]


static func purpose_text(purpose: String) -> String:
	var sp := split_purpose(purpose)
	var t: String = APPROACHES[sp[0]]["name"]
	if sp[1] != "":
		t += " (%s)" % Items.name_of(sp[1]).to_lower()
	return t


## Sets the plan on the state's RegionState (X's plan() when present).
static func plan(state: GameState, id: String, purpose: String) -> void:
	if state == null or state.region == null:
		return
	if state.region.has_method("plan"):
		state.region.call("plan", id, purpose)
	else:
		state.region.planned = id
		state.region.planned_purpose = purpose
