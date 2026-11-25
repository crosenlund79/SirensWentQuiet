class_name BuildNoise
extends RefCounted
## Experiment 007 (N): the noise of construction (the user's §12). BuildMode
## calls after_apply() once per successful action (one line at the end of
## BuildMode.apply). Hammering wood is low, masonry and digging moderate or
## low, hammering metal high, smashing or demolishing furniture high.
## Moving furniture, filling a trench with water and putting a rug down
## make no noise event.

const QUIET_TOOLS := ["move", "fill"]
const METAL_PIECES := ["iron_barricade", "iron_door", "metal_door", "spikes_metal", "fuse_box", "tool_cabinet"]
const STONE_PIECES := ["stone_wall", "foundation", "pillar"]
const QUIET_PIECES := ["rug", "painting", "plant", "table_lamp", "radio"]


## The event name (NoiseEvent.EVENTS) for a successful BuildMode evaluation `r`; "" for none.
static func event_for(bm: Node, r: Dictionary) -> String:
	var piece := str(r.get("piece", ""))
	var tool := str(bm.call("tool")) if bm != null and bm.has_method("tool") else "place"
	if tool in QUIET_TOOLS or piece in QUIET_PIECES:
		return ""
	match piece:
		"upgrade":
			return "hammer_metal"            # iron plating, reinforcing a door
		"repair":
			if _metal(bm, r):
				return "hammer_metal"
			return "masonry" if _stone(bm, r) else "hammer_wood"
		"demolish", "remove_window":
			if r.has("furniture"):
				return "smash_furniture"
			var o = r.get("object")
			if o is WorldObject and FurnitureCatalog.is_furniture((o as WorldObject).kind):
				return "smash_furniture"
			return "demolish_metal" if _metal(bm, r) else "demolish"
		"doorway":
			return "demolish"
	if tool == "dig" or tool == "backfill":
		return "dig"
	if piece in METAL_PIECES or str(bm.call("_mat") if bm != null and bm.has_method("_mat") else "wood") in ["iron", "metal"]:
		return "hammer_metal"
	if piece in STONE_PIECES:
		return "masonry"
	return "hammer_wood"


## Makes the noise of an applied action at `at` (BuildMode._where: plan x, z).
static func after_apply(bm: Node, r: Dictionary, at: Vector3) -> Dictionary:
	var ev := event_for(bm, r)
	if ev == "":
		return {}
	var w = bm.get("world") if bm != null else null
	var pos := at
	if w is LevelWorld:
		pos.y = Levels.base_y((w as LevelWorld).storey) + 0.5
	elif bm != null and bm.get("plane_y") != null:
		pos.y = float(bm.get("plane_y")) + 0.5
	return NoiseEvent.emit(w if w is HouseWorld else bm, pos, NoiseEvent.level_of(ev), ev)


static func _metal(bm: Node, r: Dictionary) -> bool:
	var o = r.get("object")
	if o is WorldObject:
		var wo := o as WorldObject
		return wo.mat in ["iron", "metal"] or wo.kind in METAL_PIECES or str(r.get("to_mat", "")) in ["iron", "metal"]
	var w = bm.get("world") if bm != null else null
	var segs: Array = r.get("segs", [])
	if w is HouseWorld and not segs.is_empty() and segs[0] is Vector3i:
		var info: Dictionary = (w as HouseWorld).section_info(segs[0]) if (w as HouseWorld).sections.has(segs[0]) else {}
		return bool(info.get("upgraded", false))
	return false


static func _stone(bm: Node, r: Dictionary) -> bool:
	if r.get("foundation_repair", false):
		return true
	var segs: Array = r.get("segs", [])
	if bm != null and bm.has_method("wall_material") and not segs.is_empty() and segs[0] is Vector3i:
		return str(bm.call("wall_material", segs[0])) == "stone"
	return false
