extends RefCounted
## What goes into the save and how it comes back (SPEC §7.2). SaveGame does the
## file IO; this composes the dictionary and validates a loaded one.
##
## Layout: {"summary", "state": GameState.to_dict(), "world": HouseWorld.save_data(),
##          "game": {"version", "player": {"pos": [x, z], "yaw"}, "time_scale", "director"}}
## (Saves from the foundation stub era kept "game" in "game_data"; still read.)

const VERSION := 1


static func summary_of(state: GameState) -> Dictionary:
	if state.has_method("summary"):
		var s = state.summary()
		if typeof(s) == TYPE_DICTIONARY:
			return s
	return {"day": state.day(), "clock": state.clock_text(), "health": roundi(state.health),
		"days_survived": state.days_survived(), "text": "Day %d, %s" % [state.day(), state.clock_text()]}


static func compose(state: GameState, world_data: Dictionary, player_pos: Vector3, yaw: float, extra := {}) -> Dictionary:
	var game := {"version": VERSION, "player": {"pos": [player_pos.x, player_pos.z], "yaw": yaw}}
	game.merge(extra, true)
	return {"summary": summary_of(state), "state": state.to_dict(), "world": world_data, "game": game}


## Returns {"ok", "error", "state": GameState, "world": Dictionary,
## "player_pos": Vector3 or null, "yaw": float, "game": Dictionary}.
static func parse(data: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "state": null, "world": {}, "player_pos": null, "yaw": 0.0, "game": {}}
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
	out["ok"] = true
	out["state"] = st
	out["world"] = wd
	out["game"] = g
	return out
