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
## Exp 012 (§33): how many games (roster warmers) are running. While one is
## and no loading screen is up, a person whose look isn't built yet never
## builds it on the spot (a 0.5..1.5 s freeze): it wears a stand-in look of
## its archetype that is ready and changes into its own look a moment later
## (HumanoidRig.adopt_pending). 0 (tests, the showroom): built on the spot.
static var _games := 0
static var stand_ins := 0           ## people that started in a stand-in look (F10, tests)


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
	# Exp 012: every look of the archetype is a candidate (was 8 tries)
	var v := maxi(a.variety(), 1)
	for i in v:
		var s := first + i
		if HumanoidSculpt.is_ready(str(a.look(s)["key"])):
			return s
	return first


## Exp 012 (§33): whether a rig made now must not build its look on the spot.
static func defer_builds() -> bool:
	return _games > 0 and LoadingScreen.current() == null


## Exp 012 (§33): a built look of the same archetype to wear while `l` builds
## (the nearest index first), or {} when none is ready.
static func stand_in(l: Dictionary) -> Dictionary:
	var a := archetype(str(l.get("kind", "")))
	if a == null:
		return {}
	var v := maxi(a.variety(), 1)
	var i0 := int(l.get("index", 0))
	for d in v:
		var cand := a.look(i0 + d)
		if HumanoidSculpt.is_cached(str(cand["key"])):
			return cand
	return {}


## Starts building looks of `kind` in the background while `host` (a node in
## the tree: the game's roster) lives; when it leaves the tree, unfinished
## builds are cancelled and waited for (nothing runs on at quit).
static func warm(kind: String, host: Node, count := 16) -> void:
	var a := archetype(kind)
	if a == null or host == null or not host.is_inside_tree():
		return
	# Exp 012 (§33): behind a loading screen (a staged boot), the archetype's
	# first look is built now on every core, so in the game there is always a
	# ready stand-in and no person is ever built on the spot
	if LoadingScreen.current() != null:
		var l0 := a.look(0)
		if not HumanoidSculpt.is_cached(str(l0["key"])):
			HumanoidSculpt.meshes(l0, HumanoidRig.material_for(l0))
	if host.get_node_or_null("HumanoidWarmer") == null:
		var w := Warmer.new()
		w.name = "HumanoidWarmer"
		host.add_child(w)
	# Exp 012: the first look of every archetype first (a kind with nothing
	# ready would have to build on the spot), then the rest
	var w: Node = host.get_node("HumanoidWarmer")
	w.call("queue_kind", kind, mini(a.variety(), count))


## Adopts background builds every frame; cancels them on leaving the tree.
## Exp 012: it also counts as a running game (defer_builds) and queues the
## warm-ups round-robin over the archetypes, one look each in turn.
class Warmer extends Node:
	var _queue := []           ## [kind, next index, count]

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _enter_tree() -> void:
		HumanoidLooks._games += 1

	var _fed := false

	func queue_kind(kind: String, count: int) -> void:
		_queue.append([kind, 0, count])
		if not _fed:
			_fed = true
			_feed.call_deferred()             # after every warm() of this frame: round-robin

	## Hands the background queue one look per archetype per round.
	func _feed() -> void:
		_fed = false
		if not is_inside_tree():
			return
		var more := true
		while more:
			more = false
			for q in _queue:
				if int(q[1]) < int(q[2]):
					var l := HumanoidLooks.archetype(str(q[0])).look(int(q[1]))
					HumanoidSculpt.request(l, HumanoidRig.material_for(l))
					q[1] = int(q[1]) + 1
					more = true

	func _process(_delta: float) -> void:
		HumanoidSculpt.poll()

	func _exit_tree() -> void:
		HumanoidLooks._games = maxi(HumanoidLooks._games - 1, 0)
		HumanoidSculpt.cancel_background()


## Builds the meshes of these looks ahead of time (loading screens, tests).
static func prewarm(kind: String, seeds: Array) -> void:
	for s in seeds:
		var l := look(kind, int(s))
		if not l.is_empty():
			HumanoidSculpt.meshes(l, HumanoidRig.material_for(l))
