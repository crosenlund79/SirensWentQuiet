class_name BuildPieces
extends RefCounted
## Construction pieces, tools and costs (SPEC §6). Owner: V. Pure data.
## Keys 1-7 are the SPEC's; 8 and 9 add the upgrade and demolish tools.

const LIST := [
	{"id": "wall", "name": "Wooden wall", "short": "Wall", "tool": "place", "cost": {"wood": 4, "nails": 6}, "per_m": true,
		"hint": "LMB place · drag along a line for a run · RMB cancel"},
	{"id": "barricade", "name": "Barricade", "short": "Barricade", "tool": "place", "cost": {"wood": 2, "nails": 4}, "per_m": true,
		"hint": "Planks across a 1 m gap or line · drag for several · bullets pass, bodies don't"},
	{"id": "door", "name": "Door", "short": "Door", "tool": "place", "cost": {"wood": 4, "nails": 6, "scrap": 1},
		"hint": "Aim at a wall (cuts it) or a 1 m doorway · E opens and closes it"},
	{"id": "doorway", "name": "Doorway", "short": "Doorway", "tool": "place", "cost": {},
		"hint": "Aim at a wall: cuts a 1 m opening"},
	{"id": "crate", "name": "Storage crate", "short": "Crate", "tool": "place", "cost": {"wood": 3, "nails": 4},
		"hint": "Raises material caps · R rotates"},
	{"id": "rain_collector", "name": "Rain collector", "short": "Collector", "tool": "place", "cost": {"wood": 2, "nails": 2, "scrap": 3},
		"hint": "One water every dawn · R rotates"},
	{"id": "repair", "name": "Repair", "short": "Repair", "tool": "repair", "cost": {},
		"hint": "Aim at a damaged wall section or object · 1 plank per 150 voxels, 1 nail per 60"},
	{"id": "upgrade", "name": "Metal sheathing", "short": "Sheathe", "tool": "upgrade", "cost": {"scrap": 3, "nails": 4},
		"hint": "Aim at a 1 m wall section: its outer skin becomes hard sheet metal"},
	{"id": "demolish", "name": "Demolish", "short": "Demolish", "tool": "demolish", "cost": {},
		"hint": "Your pieces refund half · an original wall section becomes an opening"},
]

## Costs of placed objects (for object repair and demolish refunds).
const OBJECT_COST := {
	"door": {"wood": 4, "nails": 6, "scrap": 1},
	"barricade": {"wood": 2, "nails": 4},
	"crate": {"wood": 3, "nails": 4},
	"rain_collector": {"wood": 2, "nails": 2, "scrap": 3},
}
const WALL_COST := {"wood": 4, "nails": 6}


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return -1


static func times(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = int(cost[k]) * n
	return out


static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out


## Half the cost, rounded down.
static func refund(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		if int(cost[k]) / 2 > 0:
			out[k] = int(cost[k]) / 2
	return out


## SPEC: 1 wood per 150 missing voxels + 1 nail per 60 (rounded up).
static func section_repair_cost(missing: int) -> Dictionary:
	if missing <= 0:
		return {}
	return {"wood": ceili(missing / 150.0), "nails": ceili(missing / 60.0)}


## SPEC: lost-HP fraction x the piece's cost, minimum 1 wood.
static func object_repair_cost(kind: String, hp: int, max_hp: int) -> Dictionary:
	var frac := clampf(1.0 - float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	if frac <= 0.0:
		return {}
	var out := {}
	var base: Dictionary = OBJECT_COST.get(kind, {"wood": 1})
	for k in base:
		var n := ceili(frac * int(base[k]))
		if n > 0:
			out[k] = n
	out["wood"] = maxi(int(out.get("wood", 0)), 1)
	return out


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts := PackedStringArray()
	for k in ["wood", "nails", "scrap"]:
		if cost.has(k) and int(cost[k]) > 0:
			parts.append("%d %s" % [cost[k], Items.name_of(k).to_lower()])
	return ", ".join(parts)
