extends RefCounted
## Picks what [E] acts on: the nearest interactable (SPEC §7.3 duck type:
## interact_prompt() -> String, "" hides; interact(game)) within RADIUS of the
## player whose prompt is not empty (and, Exp 005, whose optional
## interact_reach(p) allows the player's plan point p).

const RADIUS := 1.6


## Exp 012 (L, §24): `keep` (the current choice) stays unless another is
## NEAREST_KEEP m nearer, so two things at about the same distance don't flicker.
const NEAREST_KEEP := 0.15


static func nearest(candidates: Array, p: Vector2, radius := RADIUS, keep: Node3D = null) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	var keep_d := INF
	for n in candidates:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		if not n.has_method("interact_prompt") or not n.has_method("interact"):
			continue
		var q: Vector3 = (n as Node3D).global_position
		var d := p.distance_to(Vector2(q.x, q.z))
		if d > (radius if n == keep else best_d):
			continue
		if str(n.interact_prompt()) == "":
			continue
		if n.has_method("interact_reach") and not n.interact_reach(p):
			continue          # Exp 005 (F): e.g. a cupboard isn't opened from behind its wall
		if n == keep:
			keep_d = d
		if d <= best_d:
			best = n
			best_d = d
	if keep != null and keep_d < INF and keep_d <= best_d + NEAREST_KEEP:
		return keep
	return best


## Exp 008 (L): one clear choice when several things are in reach (a shelf,
## a loose item, a door and an exit side by side). Each candidate (the same
## filters as nearest) scores its distance,
##   + up to FACING_COST m when Eli faces away from it (`facing`: his plan
##     direction, ZERO to ignore; the thing's
##     optional interact_point() is where it is, for this),
##   + INFO_COST m when its prompt is only a note (no "[key]"), so something
##     he can use wins over a note beside it (a thing whose optional
##     interact_busy() is true, e.g. a shelf being searched, is no note).
## The current choice `keep` stays unless another beats it by KEEP_MARGIN m,
## so the prompt doesn't flicker between two things at about the same distance.
## The game uses it at a POI (home keeps nearest).
const FACING_COST := 0.4
const INFO_COST := 0.6
const KEEP_MARGIN := 0.25


static func best(candidates: Array, p: Vector2, facing := Vector2.ZERO, keep: Node3D = null, radius := RADIUS) -> Node3D:
	var top: Node3D = null
	var top_s := INF
	var keep_s := INF
	for n in candidates:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		if not n.has_method("interact_prompt") or not n.has_method("interact"):
			continue
		var q: Vector3 = (n as Node3D).global_position
		var d := p.distance_to(Vector2(q.x, q.z))
		if d > radius:
			continue
		var prompt := str(n.interact_prompt())
		if prompt == "":
			continue
		if n.has_method("interact_reach") and not n.interact_reach(p):
			continue
		var s := d
		if facing != Vector2.ZERO:
			var at: Vector2 = n.interact_point() if n.has_method("interact_point") else Vector2(q.x, q.z)
			var to := at - p
			if to.length() > 0.3:
				s += FACING_COST * 0.5 * (1.0 - clampf(to.normalized().dot(facing.normalized()), -1.0, 1.0))
		if not prompt.begins_with("[") and not (n.has_method("interact_busy") and n.interact_busy()):
			s += INFO_COST              # a note, not a timed action in progress ("Searching... 40 %")
		if n == keep:
			keep_s = s
		if s < top_s:
			top = n
			top_s = s
	if keep != null and keep_s < INF and keep_s <= top_s + KEEP_MARGIN:
		return keep
	return top


## Exp 008 (L): the way Eli faces on the plan (towards his aim point), or
## Vector2.ZERO when that is unclear.
static func facing_of(player: Node3D) -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	var a: Variant = player.get("aim_point")
	if not (a is Vector3):
		return Vector2.ZERO
	var to := Vector2((a as Vector3).x - player.global_position.x, (a as Vector3).z - player.global_position.z)
	return to.normalized() if to.length() > 0.3 else Vector2.ZERO


# --- Exp 012 (L, §24): never through walls ---------------------------------------------------

## Agent V's visibility hook: when valid, `sight_hook.call(world_pos: Vector3)
## -> bool` decides whether a thing at world_pos is visible to Eli (e.g. its
## visibility node's is_point_visible). Unset, a voxel line of sight is used.
static var sight_hook := Callable()
const SIGHT_EYE := 1.5            ## m: Eli's eyes
const SIGHT_AT := 0.8             ## m: the height looked at on a thing
const SIGHT_SLACK := 0.35         ## m: a wall this close to the thing doesn't hide it (wall-mounted things)
static var _skip := PackedByteArray()


## The candidates Eli can actually see (the finder's input): a wall or a
## closed door between Eli's eyes and a thing within reach hides it, so E
## never picks, and the ring never marks, something in the next room. Things
## out of reach pass unchecked (the finder drops them anyway).
static func in_sight(candidates: Array, game: Node) -> Array:
	var pl: Variant = game.get("player") if game != null else null
	if not (pl is Node3D):
		return candidates
	var eye := (pl as Node3D).global_position + Vector3(0, SIGHT_EYE, 0)
	var p := Vector2(eye.x, eye.z)
	var w: Variant = _world_of(game)
	var out := []
	for n in candidates:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var q: Vector3 = (n as Node3D).global_position
		if p.distance_to(Vector2(q.x, q.z)) > RADIUS + 0.4 or sees(w, eye, n):
			out.append(n)
	return out


## True if Eli's eye sees the thing `n` (see in_sight): the hook, else the
## voxel world `w` (HouseWorld / PoiWorld / LevelWorld; null: always true).
static func sees(w: Variant, eye: Vector3, n: Node3D) -> bool:
	var q := n.global_position
	var at := Vector2(q.x, q.z)
	if n.has_method("interact_point"):
		at = n.interact_point()
	var target := Vector3(at.x, q.y + SIGHT_AT, at.y)
	if sight_hook.is_valid():
		return bool(sight_hook.call(target))
	if not (w is Object) or not is_instance_valid(w):
		return true
	var grid: Variant = (w as Object).get("grid")
	if grid is VoxelGrid:
		var dist := eye.distance_to(target)
		if dist > 0.05:
			var hit: Dictionary = (grid as VoxelGrid).raycast(eye, (target - eye) / dist, dist, _wall_skip())
			if not hit.is_empty() and float(hit.get("dist", INF)) < dist - SIGHT_SLACK:
				return false
	var objs: Variant = (w as Object).get("objects")
	if objs is Array:
		var a := Vector2(eye.x, eye.z)
		for o in objs:
			if o == n or not is_instance_valid(o) or str(o.get("kind")) != "door" or bool(o.get("open")) or not o.has_method("footprint"):
				continue
			var fp: Rect2 = o.footprint()
			if fp.get_center().distance_to(at) < 0.3:
				continue          # the thing is at this door (its own lock, a window board...)
			if Geometry2D.segment_intersects_segment(a, at, fp.position, fp.end) != null:
				return false
	return true


## The voxel world Eli is in now (his storey's at home, the site's away).
static func _world_of(game: Node) -> Variant:
	var lv: Variant = game.get("levels")
	if lv is Object and is_instance_valid(lv) and lv.has_method("active_world"):
		return lv.active_world()
	return game.get("world")


## Only structure (walls, floors) stops the look; furniture, glass, frames pass.
static func _wall_skip() -> PackedByteArray:
	if _skip.is_empty():
		_skip.resize(256)
		for i in 256:
			_skip[i] = 0 if VoxelMat.is_struct(i) and (VoxelMat.FLAGS[i] & VoxelMat.F_GLASS) == 0 else 1
	return _skip
