class_name Research
extends RefCounted
## Experiment 006 (R): the small research tree (SPEC-006 §2). Pure rules on
## GameState.skills (skill id -> the day it was learned; 0 = granted to an
## older save). Skills come from skill books found on expeditions (mostly the
## Library): reading a book (inventory "Skills" tab, key K) teaches its
## skill once the skill's prerequisite is known, and uses the book up.
##
## The tree (one line, four steps; in the spirit of a small survival
## progression, no code from elsewhere):
##   woodworking     Basic woodworking           drawbridges; wooden repairs cost a quarter less
##   reinforced      Reinforced construction     reinforced doors (and Reinforce wood -> reinforced), iron barricades
##   metalworking    Metalworking                metal doors (and Reinforce reinforced -> metal), metal spikes;
##                                               the workbench makes 1 iron from 2 scrap instead of 3
##   advanced_metal  Advanced metal fabrication  iron plating on wall sections
## Everything else needs nothing: plain wood, stone, furniture, floors,
## stairs and storeys, trenches and water, the workbench, the fuse box.
##
## Gating: BuildMode.evaluate calls `gate(state, piece, r)`; a locked piece
## is refused with `locked_reason` ("Requires Metalworking (read
## 'Metalworking Manual')"). A piece's own `"requires"` field (BuildPieces
## entries of the other agents) wins over GATES. Built structures are never
## touched: a locked recipe only stops new building and Reinforce steps.
## Objects without a `skills` property (test doubles) know everything.
##
## Older saves (no "skills" in the state): RunSave.parse calls
## `infer_from_world`, which grants what the saved house already contains
## (metal doors or metal spikes -> metalworking, reinforced doors or iron
## barricades -> reinforced, iron plating -> advanced metal fabrication,
## drawbridges -> woodworking), each with its prerequisites.

const SKILLS := {
	"woodworking": {"name": "Basic woodworking", "book": "book_woodworking", "requires": [],
		"desc": "Joints, frames and hinges: the basics of building properly in wood.",
		"effects": ["Wooden repairs cost a quarter less (planks and nails)."]},
	"reinforced": {"name": "Reinforced construction", "book": "book_reinforced", "requires": ["woodworking"],
		"desc": "Bracing, bolts and iron straps: wood that holds when something leans on it.",
		"effects": []},
	"metalworking": {"name": "Metalworking", "book": "book_metalworking", "requires": ["reinforced"],
		"desc": "Cutting, bending and riveting steel with hand tools.",
		"effects": ["The workbench makes 1 iron from 2 scrap instead of 3."]},
	"advanced_metal": {"name": "Advanced metal fabrication", "book": "book_advanced_metal", "requires": ["metalworking"],
		"desc": "Plate work and structural steel: armouring whole walls.",
		"effects": []},
}
## Tree order (each step needs the one before it).
const ORDER := ["woodworking", "reinforced", "metalworking", "advanced_metal"]

## BuildPieces ids -> the skill they need (a piece's own "requires" wins).
## spikes_metal and the drawbridges are agent D's pieces (Experiment 006).
const GATES := {
	"iron_door": "reinforced",
	"iron_barricade": "reinforced",
	"metal_door": "metalworking",
	"spikes_metal": "metalworking",
	"drawbridge_1": "woodworking",
	"drawbridge_2": "woodworking",
}
## Reinforce steps (BuildPieces.REINFORCE): "kind:to_mat" -> skill.
const REINFORCE_GATES := {"door:iron": "reinforced", "door:metal": "metalworking"}
## The Iron plating tool on wall sections ("upgrade" without a door).
const PLATING_SKILL := "advanced_metal"
## Woodworking: wooden repairs (planks and nails) x this, rounded up.
const WOOD_REPAIR_FACTOR := 0.75
## The workbench: scrap per iron, without and with Metalworking.
const SCRAP_PER_IRON := 3
const SCRAP_PER_IRON_SKILLED := 2
## Display names of gated tools and pieces that are not in BuildPieces here.
const EXTRA_NAMES := {"spikes_metal": "Metal spikes", "drawbridge_1": "Drawbridge (1 tile)", "drawbridge_2": "Drawbridge (2 tiles)"}


static func has_skill(id) -> bool:
	return typeof(id) in [TYPE_STRING, TYPE_STRING_NAME] and SKILLS.has(str(id))


static func name_of(id) -> String:
	return str(SKILLS[str(id)]["name"]) if has_skill(id) else str(id)


static func book_of(id) -> String:
	return str(SKILLS[str(id)]["book"]) if has_skill(id) else ""


static func prerequisites(id) -> Array:
	return (SKILLS[str(id)]["requires"] as Array).duplicate() if has_skill(id) else []


## Book item ids, in tree order.
static func books() -> Array:
	var out := []
	for s in ORDER:
		out.append(SKILLS[s]["book"])
	return out


static func is_book(item) -> bool:
	return Items.has(item) and Items.category(item) == "book"


## The skill a book teaches ("" for anything else).
static func book_skill(item) -> String:
	if not Items.has(item):
		return ""
	return str(Items.DEFS[str(item)].get("skill", ""))


# --- knowledge --------------------------------------------------------------------------

## The state's skill dictionary, or null when the object has no research
## system (test doubles): then everything counts as known.
static func _skills(state) -> Variant:
	if state == null or not (state is Object):
		return null
	var v = (state as Object).get("skills")
	return v if typeof(v) == TYPE_DICTIONARY else null


static func knows(state, id) -> bool:
	if not has_skill(id):
		return str(id) == ""
	var sk = _skills(state)
	return sk == null or (sk as Dictionary).has(str(id))


## Skills the state knows, in tree order.
static func known(state) -> Array:
	var out := []
	for s in ORDER:
		if knows(state, s):
			out.append(s)
	return out


## Learns `id` (and nothing else). Returns true when it was new.
static func learn(state, id: String, day := -1) -> bool:
	var sk = _skills(state)
	if sk == null or not has_skill(id) or (sk as Dictionary).has(id):
		return false
	(sk as Dictionary)[id] = maxi(day if day >= 0 else _day(state), 0)
	_changed(state)
	return true


## Learns `id` with its prerequisites (older saves, dev tools).
static func learn_with_prerequisites(state, id: String, day := -1) -> Array:
	var out := []
	for p in prerequisites(id):
		out.append_array(learn_with_prerequisites(state, p, day))
	if learn(state, id, day):
		out.append(id)
	return out


## Developer tool and tests: every skill.
static func learn_all(state) -> void:
	for s in ORDER:
		learn(state, s)


## Developer tool: forgets every skill (built structures stay).
static func forget_all(state) -> void:
	var sk = _skills(state)
	if sk == null or (sk as Dictionary).is_empty():
		return
	(sk as Dictionary).clear()
	_changed(state)


static func _day(state) -> int:
	return int(state.day()) if state != null and (state as Object).has_method("day") else 0


static func _changed(state) -> void:
	if state != null and (state as Object).has_signal("changed"):
		(state as Object).emit_signal("changed")


# --- books ------------------------------------------------------------------------------

## Why `book` can't be read now ("" = it can).
static func can_read(state, book: String) -> String:
	var skill := book_skill(book)
	if state == null or skill == "":
		return "That isn't something to study."
	if bool(state.get("dead")):
		return "You're dead."
	if state.inventory.count(book) <= 0:
		return "You don't have that book."
	if knows(state, skill):
		return "You already know %s." % name_of(skill).to_lower()
	for p in prerequisites(skill):
		if not knows(state, p):
			return "Too advanced for now: learn %s first ('%s')." % [name_of(p).to_lower(), Items.name_of(book_of(p))]
	return ""


## Reads `book`: the skill is learned and the book used up. Returns
## {"ok", "text", "skill"}.
static func read_book(state, book: String) -> Dictionary:
	var why := can_read(state, book)
	if why != "":
		return {"ok": false, "text": why, "skill": ""}
	var skill := book_skill(book)
	state.inventory.remove(book, 1)
	learn(state, skill)
	var text := "You study '%s' cover to cover. Learned: %s." % [Items.name_of(book), name_of(skill)]
	var un := unlocks(skill)
	if not un.is_empty():
		text += " Unlocks: " + ", ".join(un) + "."
	for e in effects(skill):
		text += " " + str(e)
	return {"ok": true, "text": text, "skill": skill}


# --- gating -----------------------------------------------------------------------------

## The skill a build piece (a BuildPieces.LIST entry) needs, or "".
static func required_skill(piece: Dictionary) -> String:
	var own := str(piece.get("requires", ""))
	if own != "":
		return own
	return str(GATES.get(str(piece.get("id", "")), ""))


## "" when `piece` can be built, else "Requires Metalworking (read 'Metalworking Manual')".
static func locked_reason(state, piece: Dictionary) -> String:
	return skill_reason(state, required_skill(piece))


## "" when `skill` is known (or empty), else the refusal text.
static func skill_reason(state, skill: String) -> String:
	if skill == "" or knows(state, skill):
		return ""
	if not has_skill(skill):
		return "Requires %s." % skill.capitalize()
	return "Requires %s (read '%s')" % [name_of(skill), Items.name_of(book_of(skill))]


## The skill a Reinforce step to `to_mat` on a `kind` object needs.
static func reinforce_skill(kind: String, to_mat: String) -> String:
	return str(REINFORCE_GATES.get("%s:%s" % [kind, to_mat], ""))


## BuildMode.evaluate's hook (after the piece's own checks, before the cost
## check): refuses locked pieces and Reinforce steps; Woodworking discounts
## wooden repairs. `r` is the evaluation dictionary.
static func gate(state, piece: Dictionary, r: Dictionary) -> void:
	match str(piece.get("tool", "")):
		"upgrade":
			var why := ""
			if r.get("object") != null and r.has("to_mat"):
				var o: Object = r["object"]
				why = skill_reason(state, reinforce_skill(str(o.get("kind")), str(r["to_mat"])))
			elif not (r.get("segs", []) as Array).is_empty() and r.get("object") == null:
				why = skill_reason(state, PLATING_SKILL)
			if why != "" and str(r.get("reason", "")) == "":
				r["reason"] = why
				r["locked"] = true
		"repair":
			if knows(state, "woodworking") and _skills(state) != null:
				r["cost"] = wood_repair_cost(r.get("cost", {}))
		_:
			var lock := locked_reason(state, piece)
			if lock != "":
				r["reason"] = lock
				r["locked"] = true


## A repair cost with Woodworking: planks and nails x WOOD_REPAIR_FACTOR
## (rounded up, so never below 1 of what it needed).
static func wood_repair_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		var n := int(cost[k])
		if k in ["wood", "nails"] and n > 0:
			n = maxi(ceili(n * WOOD_REPAIR_FACTOR), 1)
		out[k] = n
	return out


## Scrap per iron at the workbench for this state.
static func scrap_per_iron(state) -> int:
	return SCRAP_PER_IRON_SKILLED if (_skills(state) != null and knows(state, "metalworking")) else SCRAP_PER_IRON


# --- what a skill opens -----------------------------------------------------------------

## Names of what `skill` unlocks: build pieces, Reinforce steps, plating and
## its other effects (for the panel and the read text).
static func unlocks(skill: String) -> Array:
	var out := []
	for p in BuildPieces.LIST:
		if required_skill(p) == skill:
			out.append(str(p.get("name", p.get("id", ""))))
	for id in GATES:
		if GATES[id] == skill and BuildPieces.index_of(id) < 0:
			out.append(str(EXTRA_NAMES.get(id, id.capitalize())))
	for k in REINFORCE_GATES:
		if REINFORCE_GATES[k] == skill:
			var parts: PackedStringArray = k.split(":")
			out.append("Reinforce: %s" % ({"iron": "wood → reinforced door", "metal": "reinforced → metal door"}.get(parts[1], k)))
	if skill == PLATING_SKILL:
		out.append("Iron plating on walls")
	var uniq := []
	for x in out:
		if not x in uniq:
			uniq.append(x)
	return uniq


## Other effects of `skill` (lines for the panel).
static func effects(skill: String) -> Array:
	return (SKILLS[skill].get("effects", []) as Array).duplicate() if has_skill(skill) else []


## The tree for the panel: [{id, name, desc, book, book_name, known,
## requires, ready (prerequisites known), unlocks, effects, have_book}].
static func tree(state) -> Array:
	var out := []
	for s in ORDER:
		var d: Dictionary = SKILLS[s]
		var ready := true
		for p in d["requires"]:
			ready = ready and knows(state, p)
		var have := 0
		if state != null and state.get("inventory") != null:
			have = state.inventory.count(d["book"])
		out.append({"id": s, "name": d["name"], "desc": d["desc"], "book": d["book"], "book_name": Items.name_of(d["book"]),
			"known": knows(state, s), "requires": (d["requires"] as Array).duplicate(), "ready": ready,
			"unlocks": unlocks(s), "effects": effects(s), "have_book": have > 0})
	return out


# --- persistence ------------------------------------------------------------------------

## Skills from untrusted (saved) data: known ids only, day >= 0.
static func clean(v) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if has_skill(k):
				var d = v[k]
				out[str(k)] = int(clampf(float(d), 0.0, 100000.0)) if typeof(d) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(d)) else 0
	elif typeof(v) == TYPE_ARRAY:
		for k in v:
			if has_skill(k):
				out[str(k)] = 0
	return out


## An older save (no "skills"): grants what the saved house shows was
## already built (see the header), with prerequisites, on day 0. Returns
## the skills granted.
static func infer_from_world(state, world: Variant) -> Array:
	var found := {}
	_scan(world, found, 0)
	var out := []
	for s in ORDER:
		if found.has(s):
			out.append_array(learn_with_prerequisites(state, s, 0))
	return out


static func _scan(v: Variant, found: Dictionary, depth: int) -> void:
	if depth > 6:
		return
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		var kind = d.get("kind")
		if typeof(kind) == TYPE_STRING:
			var mat := str(d.get("mat", "wood"))
			if kind == "door" and mat == "metal":
				found["metalworking"] = true
			elif (kind == "door" or kind == "barricade") and mat == "iron":
				found["reinforced"] = true
			if GATES.has(kind):
				found[GATES[kind]] = true
		var up = d.get("upgraded")
		if typeof(up) == TYPE_ARRAY and not (up as Array).is_empty():
			found[PLATING_SKILL] = true
		for k in d:
			if typeof(d[k]) in [TYPE_DICTIONARY, TYPE_ARRAY]:
				_scan(d[k], found, depth + 1)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			if typeof(x) in [TYPE_DICTIONARY, TYPE_ARRAY]:
				_scan(x, found, depth + 1)
