class_name Workbench
extends RefCounted
## The workbench's one processing step (SPEC-003 §2, §4): scrap (raw) into
## iron (a construction resource), 3 scrap -> 1 iron, no crafting tree.
##
## The survival core owns the rule (agent K). `convert` calls, in order:
##   1. `Crafting.convert_scrap(state, batches)` if a global class `Crafting`
##      with that static method exists (src/survival, K);
##   2. `state.convert_scrap(batches)` if the GameState has that method;
##   3. otherwise the local fallback: removes SCRAP_PER_IRON scrap per iron
##      and adds the iron (up to the iron cap), all through the inventory.
## Whatever ran, the result is read back from the inventory (before/after),
## so the report is right whatever the API returns.

const SCRAP_PER_IRON := 3


## Converts up to `batches` x (3 scrap -> 1 iron). Returns
## {"ok": bool, "iron": iron gained, "scrap": scrap used, "text": String,
##  "via": "Crafting" | "GameState" | "fallback" | ""}.
static func convert(state: Variant, batches := 1) -> Dictionary:
	var out := {"ok": false, "iron": 0, "scrap": 0, "text": "", "via": ""}
	if state == null or not (state is Object) or state.get("inventory") == null:
		out["text"] = "Nothing to work with."
		return out
	var inv: Inventory = state.inventory
	var scrap0 := inv.count("scrap")
	var iron0 := inv.count("iron")
	if scrap0 < SCRAP_PER_IRON:
		out["text"] = "The workbench needs %d scrap for 1 iron (you have %d)." % [SCRAP_PER_IRON, scrap0]
		return out
	if inv.space_for("iron") <= 0:
		out["text"] = "No room for more iron (build a storage crate)."
		return out
	var api := crafting_api()
	if api != null:
		api.call("convert_scrap", state, batches)
		out["via"] = "Crafting"
	elif state.has_method("convert_scrap"):
		state.call("convert_scrap", batches)
		out["via"] = "GameState"
	else:
		var n := mini(batches, mini(scrap0 / SCRAP_PER_IRON, inv.space_for("iron")))
		if n > 0 and inv.remove("scrap", n * SCRAP_PER_IRON):
			inv.add("iron", n)
		out["via"] = "fallback"
	out["iron"] = inv.count("iron") - iron0
	out["scrap"] = scrap0 - inv.count("scrap")
	out["ok"] = out["iron"] > 0
	if out["ok"]:
		out["text"] = "Hammered %d scrap into %d iron (iron %d)." % [out["scrap"], out["iron"], inv.count("iron")]
	else:
		out["text"] = "The workbench couldn't make any iron."
	return out


## K's crafting script (global class `Crafting` with a static
## `convert_scrap`), or null while it doesn't exist.
static func crafting_api() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c.get("class") == "Crafting":
			var sc: Script = load(c["path"])
			if sc != null:
				for m in sc.get_script_method_list():
					if m.get("name") == "convert_scrap":
						return sc
	return null
