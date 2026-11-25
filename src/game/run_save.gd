extends RefCounted
## What goes into the save and how it comes back (SPEC §7.2). SaveGame does the
## file IO; this composes the dictionary and validates a loaded one.
##
## Layout: {"summary", "state": GameState.to_dict(), "world": HouseWorld.save_data(),
##          "game": {"version", "player": {"pos": [x, z], "yaw", "storey"}, "time_scale", "director"}}
## Experiment 004: "storey" (optional; -1 basement, 0 ground, 1 upper floor;
## Exp 005: -2..+2)
## and world["levels"] (src/levels/game_levels.gd). Older saves: the ground floor.
## (Saves from the foundation stub era kept "game" in "game_data"; still read.)
##
## Exp 007 (T), optional "site" (a save made at a POI, travel_flow.gd):
##   {"id": POI id, "player": {"pos": [x, z], "yaw"}, "camera_turns",
##    "travel": the trip ({"to", "car", "minutes", "depart_at", "leg"}),
##    "poi": the POI helper's state (agent P)}
## "world" and "game" then hold the home snapshot taken when Eli left (so a
## build without travel loads the home), "state" the run as it is at the POI
## (with the ledger of what happened at home meanwhile, state.run["away"]).
## parse() returns it as "site" ({} without one: older saves load at home).
## The travel animation is never saved: the checkpoints are the departure
## (an ordinary home save) and the POI.

const VERSION := 1


static func summary_of(state: GameState) -> Dictionary:
	if state.has_method("summary"):
		var s = state.summary()
		if typeof(s) == TYPE_DICTIONARY:
			return s
	return {"day": state.day(), "clock": state.clock_text(), "health": roundi(state.health),
		"days_survived": state.days_survived(), "text": "Day %d, %s" % [state.day(), state.clock_text()]}


static func compose(state: GameState, world_data: Dictionary, player_pos: Vector3, yaw: float, extra := {}, storey := 0) -> Dictionary:
	var game := {"version": VERSION, "player": {"pos": [player_pos.x, player_pos.z], "yaw": yaw}}
	if storey != 0:
		game["player"]["storey"] = storey
	game.merge(extra, true)
	return {"summary": summary_of(state), "state": state.to_dict(), "world": world_data, "game": game}


## Returns {"ok", "error", "state": GameState, "world": Dictionary,
## "player_pos": Vector3 or null, "yaw": float, "storey": int, "game": Dictionary}
## (+ "skills_inferred": [ids] for a save from before Experiment 006).
static func parse(data: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "state": null, "world": {}, "player_pos": null, "yaw": 0.0, "storey": 0, "game": {}, "site": {}}
	var sd = data.get("state")
	if typeof(sd) != TYPE_DICTIONARY:
		out["error"] = "the survival state is missing."
		return out
	var st := GameState.from_dict(sd)
	if st == null:
		out["error"] = "the survival state is damaged."
		return out
	if st.dead:
		out["error"] = "that run has already ended."
		return out
	var wd = data.get("world")
	if typeof(wd) != TYPE_DICTIONARY:
		out["error"] = "the house data is missing."
		return out
	var g = data.get("game")
	if typeof(g) != TYPE_DICTIONARY:
		g = data.get("game_data", {})
	if typeof(g) != TYPE_DICTIONARY:
		g = {}
	var p = (g as Dictionary).get("player", {})
	if typeof(p) == TYPE_DICTIONARY:
		var pos = p.get("pos")
		if (typeof(pos) == TYPE_ARRAY or typeof(pos) == TYPE_PACKED_FLOAT32_ARRAY or typeof(pos) == TYPE_PACKED_FLOAT64_ARRAY) and pos.size() == 2:
			var x := float(pos[0])
			var z := float(pos[1])
			if is_finite(x) and is_finite(z):
				out["player_pos"] = Vector3(x, 0, z)
		var yaw := float(p.get("yaw", 0.0))
		out["yaw"] = yaw if is_finite(yaw) else 0.0
		var storey = p.get("storey", 0)
		if typeof(storey) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(storey)):
			out["storey"] = clampi(int(storey), Levels.LOWEST, Levels.HIGHEST)      # Exp 005 (V): -2..+2
	# Exp 006 (R): a save from before research gets the skills its house
	# already shows (metal doors -> Metalworking, ...), so nothing built is
	# suddenly out of reach. Research.infer_from_world.
	if not (sd as Dictionary).has("skills"):
		out["skills_inferred"] = Research.infer_from_world(st, wd)
	out["site"] = parse_site(data.get("site"))      # Exp 007 (T)
	out["ok"] = true
	out["state"] = st
	out["world"] = wd
	out["game"] = g
	return out


## Exp 007 (T): the "site" part of a save made at a POI, sanitised:
## {"id", "player_pos": Vector3 or null, "yaw", "camera_turns", "travel", "poi"},
## or {} (none, or an unknown place).
static func parse_site(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	var id := str(d.get("id", "")) if typeof(d.get("id")) == TYPE_STRING else ""
	if id == "" or id == "home" or not RegionLocations.has(id):
		return {}
	var out := {"id": id, "player_pos": null, "yaw": 0.0, "camera_turns": 0, "travel": {}, "poi": {}}
	var p = d.get("player", {})
	if typeof(p) == TYPE_DICTIONARY:
		var pos = p.get("pos")
		if (typeof(pos) == TYPE_ARRAY or typeof(pos) == TYPE_PACKED_FLOAT32_ARRAY or typeof(pos) == TYPE_PACKED_FLOAT64_ARRAY) and pos.size() == 2:
			var x := float(pos[0])
			var z := float(pos[1])
			if is_finite(x) and is_finite(z):
				out["player_pos"] = Vector3(x, 0, z)
		var yaw := float(p.get("yaw", 0.0)) if typeof(p.get("yaw")) in [TYPE_INT, TYPE_FLOAT] else 0.0
		out["yaw"] = yaw if is_finite(yaw) else 0.0
	if typeof(d.get("camera_turns")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(d["camera_turns"])):
		out["camera_turns"] = int(d["camera_turns"])
	for k in ["travel", "poi"]:
		if typeof(d.get(k)) == TYPE_DICTIONARY:
			out[k] = (d[k] as Dictionary).duplicate(true)
	return out
