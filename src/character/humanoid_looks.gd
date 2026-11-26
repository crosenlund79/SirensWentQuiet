class_name HumanoidLooks
extends RefCounted
## Experiment 011: the humanoid rig factory. Every enemy body asks
##   HumanoidLooks.make_rig(kind, seed)
## for its figure: the archetype in src/character/archetypes/<kind>.gd (a
## HumanoidArchetype) gives the look for the appearance seed and its rig;
## kinds without an archetype file keep the old VoxelRig figure (EnemyDefs
## "looks"). Adding an archetype = adding that file; nothing to register.
## The seed is stable per enemy (POI encounters save it), so a revisited
## enemy keeps its face.

const ARCH_DIR := "res://src/character/archetypes/"

static var _arch := {}              ## kind -> HumanoidArchetype (or null: none)


## The archetype of `kind`, or null when it has none (old figure).
static func archetype(kind: String) -> HumanoidArchetype:
	if _arch.has(kind):
		return _arch[kind]
	var a: HumanoidArchetype = null
	var path := ARCH_DIR + kind + ".gd"
	if kind != "" and ResourceLoader.exists(path):
		var s: Variant = load(path)
		if s is GDScript:
			var o: Variant = (s as GDScript).new()
			if o is HumanoidArchetype:
				a = o
				a.kind = kind
	_arch[kind] = a
	return a


static func has_humanoid(kind: String) -> bool:
	return archetype(kind) != null


## How many distinct looks `kind` has (0: old figure).
static func variety(kind: String) -> int:
	var a := archetype(kind)
	return a.variety() if a != null else 0


## The look of `kind` for appearance seed `seed` ({} when it has no archetype).
static func look(kind: String, seed: int) -> Dictionary:
	var a := archetype(kind)
	return a.look(seed) if a != null else {}


## The figure for an enemy of `kind` with appearance `seed`. `legacy_look`:
## the VoxelRig.Look for kinds without an archetype (-1: EnemyDefs' first).
static func make_rig(kind: String, seed: int, legacy_look := -1) -> VoxelRig:
	var a := archetype(kind)
	if a != null:
		return a.new_rig(a.look(seed))
	if legacy_look < 0:
		var looks: Array = EnemyDefs.get_def(kind).get("looks", [1]) if EnemyDefs.has(kind) else [1]
		legacy_look = int(looks[0])
	return VoxelRig.new(legacy_look)


## An appearance seed for a new `kind` enemy from `rng`, preferring looks
## whose meshes are ready (no build on the spot); starts building the rest
## of the archetype's looks in the background, so variety grows as play goes on.
static func pick_seed(kind: String, rng: RandomNumberGenerator) -> int:
	var a := archetype(kind)
	var first := rng.randi() % 1000000
	if a == null:
		return first
	for i in 8:
		var s := first + i * 7919
		if HumanoidSculpt.is_ready(str(a.look(s)["key"])):
			return s
	return first


## Starts building looks of `kind` in the background while `host` (a node in
## the tree: the game's roster) lives; when it leaves the tree, unfinished
## builds are cancelled and waited for (nothing runs on at quit).
static func warm(kind: String, host: Node, count := 16) -> void:
	var a := archetype(kind)
	if a == null or host == null or not host.is_inside_tree():
		return
	if host.get_node_or_null("HumanoidWarmer") == null:
		var w := Warmer.new()
		w.name = "HumanoidWarmer"
		host.add_child(w)
	for i in mini(a.variety(), count):
		var l := a.look(i)
		HumanoidSculpt.request(l, HumanoidRig.material_for(l))


## Adopts background builds every frame; cancels them on leaving the tree.
class Warmer extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		HumanoidSculpt.poll()

	func _exit_tree() -> void:
		HumanoidSculpt.cancel_background()


## Builds the meshes of these looks ahead of time (loading screens, tests).
static func prewarm(kind: String, seeds: Array) -> void:
	for s in seeds:
		var l := look(kind, int(s))
		if not l.is_empty():
			HumanoidSculpt.meshes(l, HumanoidRig.material_for(l))
