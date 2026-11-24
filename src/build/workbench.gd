class_name Workbench
extends RefCounted
## The workbench's one processing step (SPEC-003 §2, §4): scrap (raw) into
## iron (a construction resource), 3 scrap -> 1 iron, no crafting tree.
##
## The survival core owns the rule: for a GameState, `convert` calls
## `Crafting.convert_scrap(state, batches)` (src/survival, K: all-or-nothing
## units, limited by the scrap owned and the iron cap; the unlimited cheat
## makes the scrap free) and reports its `reason` when nothing was made.
## For anything else with an `inventory` (tests, tools) a local fallback with
## the same 3 -> 1 rule runs. Either way the amounts are read back from the
## inventory (before/after).

const SCRAP_PER_IRON := 3


## Converts up to `batches` x (3 scrap -> 1 iron). Returns
## {"ok": bool, "iron": iron gained, "scrap": scrap used, "text": String,
##  "via": "Crafting" | "fallback" | ""}.
static func convert(state: Variant, batches := 1) -> Dictionary:
	var out := {"ok": false, "iron": 0, "scrap": 0, "text": "", "via": ""}
	if state == null or not (state is Object) or state.get("inventory") == null:
		out["text"] = "Nothing to work with."
		return out
	var inv: Inventory = state.inventory
	var scrap0 := inv.count("scrap")
	var iron0 := inv.count("iron")
	var reason := ""
	if state is GameState:
		var r: Dictionary = Crafting.convert_scrap(state, batches)
		reason = str(r.get("reason", ""))
		out["via"] = "Crafting"
	else:
		if scrap0 < SCRAP_PER_IRON:
			reason = "You need %d scrap metal." % SCRAP_PER_IRON
		elif inv.space_for("iron") <= 0:
			reason = "No room for more iron."
		else:
			var n := mini(batches, mini(scrap0 / SCRAP_PER_IRON, inv.space_for("iron")))
			if inv.remove("scrap", n * SCRAP_PER_IRON):
				inv.add("iron", n)
		out["via"] = "fallback"
	out["iron"] = inv.count("iron") - iron0
	out["scrap"] = scrap0 - inv.count("scrap")
	out["ok"] = out["iron"] > 0
	if out["ok"]:
		out["text"] = "Worked %d scrap into %d iron (iron %d)." % [out["scrap"], out["iron"], inv.count("iron")]
	else:
		out["text"] = "Workbench: %s" % (reason if reason != "" else "nothing to make.")
	return out
