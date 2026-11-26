class_name EnemyBarricades
extends RefCounted
## Exp 012 (G): the barricades siege attackers put up in doorways (ASSIGNMENT
## §9 "Barricading"). No enemy-construction framework: an enemy barricade IS
## the build system's wooden barricade (WorldObject "barricade", 12 HP, a
## WALL for navigation, a body for collision), placed with
## HouseWorld.place_object as a non-player piece (`built` false) and marked by
## its uid (UID_PREFIX). So it is:
##   - physical and visible: it blocks Eli and the enemies alike;
##   - counterable: hastily nailed (HP ENEMY_HP of the barricade's 12), and,
##     unlike the player's barricades, it stops bullets (its body joins the
##     environment layer, harden()), so shots break it; enemy swings and
##     blasts break it too, build mode demolishes it (salvage like any
##     original piece), F10 clears them;
##   - persistent and save-safe: it stays until destroyed and is saved with
##     the house's objects; the uid survives the save (an older build that
##     doesn't know the prefix just loads an ordinary barricade).
## Only an empty doorway gets one: the same checks as building a barricade
## there (no wall, no glass, nothing standing in it, no furniture, nobody in
## it). It never replaces or damages the player's construction.

const UID_PREFIX := "sbar"

static var _n := 0
const MAX_STANDING := 5          ## enemy barricades in the house at most
const ENEMY_HP := 6              ## hastily nailed: half a built barricade
const SHOT_LAYER := 1            ## HouseWorld.shoot's environment layer


static func is_enemy(o: Object) -> bool:
	return o is WorldObject and (o as WorldObject).kind == "barricade" and (o as WorldObject).uid.begins_with(UID_PREFIX)


static func all_in(world: HouseWorld) -> Array:
	if world == null:
		return []
	return world.objects.filter(func(o): return is_enemy(o))


## "" if an enemy may barricade wall segment `s` now, else why not.
static func why_not(world: HouseWorld, s: Vector3i) -> String:
	if world == null:
		return "no world"
	var rect := HouseWorld.seg_rect(s, 0.1)
	if not HouseWorld.LOT.encloses(rect):
		return "outside the lot"
	var info := world.section_info(s)
	if info["glass"]:
		return "a window"
	if info["coverage"] >= 0.3:
		return "a wall"
	if not world.objects_in(HouseWorld.seg_rect(s, 0.12)).is_empty():
		return "something stands there"
	if world.furniture_in(rect):
		return "furniture"
	if world.bodies_in(rect.grow(0.05)):
		return "someone stands there"
	if all_in(world).size() >= MAX_STANDING:
		return "enough barricades"
	return ""


## Places an enemy barricade on segment `s` (call why_not first). Returns it.
static func place(world: HouseWorld, s: Vector3i) -> WorldObject:
	if why_not(world, s) != "":
		return null
	var o := world.place_object("barricade", HouseWorld.seg_center(s), world.seg_rot(s), false, "wood")
	if o != null:
		_n += 1
		o.uid = "%s%d_%d" % [UID_PREFIX, Time.get_ticks_msec() % 10000000, _n % 1000]
		o.hp = mini(ENEMY_HP, o.max_hp)
		harden(world)
		Sfx.play("build/place", Vector3(o.pos.x, 1.0, o.pos.y))
	return o


## Enemy barricades stop bullets (after placing and after a load: the game
## calls this when the structure changes). Returns how many there are.
static func harden(world: HouseWorld) -> int:
	var list := all_in(world)
	for o in list:
		var b: StaticBody3D = (o as WorldObject).body
		if b != null:
			b.collision_layer |= SHOT_LAYER
	return list.size()


## Removes every enemy barricade (F10). Returns how many.
static func clear(world: HouseWorld) -> int:
	var list := all_in(world)
	for o in list:
		world.remove_object(o)
	return list.size()
