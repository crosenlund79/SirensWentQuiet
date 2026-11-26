class_name HumanoidArchetype
extends RefCounted
## Experiment 011: base of a humanoid archetype (one per enemy kind, in
## src/character/archetypes/<kind>.gd; HumanoidLooks finds it by file name).
## An archetype turns an appearance seed into one of its looks and makes the
## rig for it. Override:
##   variety()       how many distinct looks it has (the cache holds at most
##                   HumanoidSculpt.CACHE_MAX looks across all archetypes)
##   make_look(i)    look number i (0 .. variety() - 1): a Dictionary with
##                   "name", "body", "outfit", "face", "hair", "style"
##                   (see HumanoidSculpt, HumanoidBody, HumanoidRig.STYLE)
##   new_rig(look)   optional: a HumanoidRig subclass for its own animation
## The key ("<kind>/<i>") is filled in by look().

var kind := ""
var _looks := {}


func variety() -> int:
	return 1


func make_look(_i: int) -> Dictionary:
	return {"name": kind.capitalize()}


func new_rig(l: Dictionary) -> HumanoidRig:
	return HumanoidRig.new(l)


## The look for appearance seed `seed` (stable: the same seed, the same look).
func look(seed: int) -> Dictionary:
	var i := posmod(seed, maxi(variety(), 1))
	if not _looks.has(i):
		var l := make_look(i)
		l["key"] = "%s/%d" % [kind, i]
		l["kind"] = kind
		l["index"] = i
		_looks[i] = l
	return _looks[i]


# --- helpers for archetypes ----------------------------------------------------------------

## A small deterministic random source for look i.
static func rng_for(kind_name: String, i: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s#%d" % [kind_name, i])
	return r


## Picks from an array with the rng.
static func pick(r: RandomNumberGenerator, a: Array) -> Variant:
	return a[r.randi() % a.size()]


## Varies each numeric body parameter by +-amount (relative) for a little individuality.
static func jitter_body(r: RandomNumberGenerator, b: Dictionary, amount := 0.04) -> Dictionary:
	var o := b.duplicate()
	for k in ["height", "head_w", "head_h", "jaw", "nose", "ears", "shoulders", "hips"]:
		var base := float(o.get(k, HumanoidBody.DEFAULTS[k]))
		o[k] = base * (1.0 + r.randf_range(-amount, amount) * (0.5 if k == "height" else 1.0))
	for k in ["chin", "cheeks"]:
		o[k] = clampf(float(o.get(k, 0.5)) + r.randf_range(-0.2, 0.2), 0.0, 1.0)
	if o.has("weight"):
		o["weight"] = clampf(float(o["weight"]) + r.randf_range(-0.07, 0.07), 0.0, 1.0)
	return o
