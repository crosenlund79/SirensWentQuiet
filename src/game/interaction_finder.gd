extends RefCounted
## Picks what [E] acts on: the nearest interactable (SPEC §7.3 duck type:
## interact_prompt() -> String, "" hides; interact(game)) within RADIUS of the
## player whose prompt is not empty (and, Exp 005, whose optional
## interact_reach(p) allows the player's plan point p).

const RADIUS := 1.6


static func nearest(candidates: Array, p: Vector2, radius := RADIUS) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for n in candidates:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		if not n.has_method("interact_prompt") or not n.has_method("interact"):
			continue
		var q: Vector3 = (n as Node3D).global_position
		var d := p.distance_to(Vector2(q.x, q.z))
		if d > best_d:
			continue
		if str(n.interact_prompt()) == "":
			continue
		if n.has_method("interact_reach") and not n.interact_reach(p):
			continue          # Exp 005 (F): e.g. a cupboard isn't opened from behind its wall
		best = n
		best_d = d
	return best


## Exp 008 (L): one clear choice when several things are in reach (a shelf,
## a loose item, a door and an exit side by side). Each candidate (the same
## filters as nearest) scores its distance, plus up to FACING_COST m when Eli
## faces away from it (`facing`: his plan direction, ZERO to ignore; the game
## passes it at a POI; the thing's optional interact_point() is where it is,
## for this), plus INFO_COST m when its
## prompt is only information (no "[key]"), so something he can use wins
## over a note beside it. The current choice `keep` stays unless another
## beats it by KEEP_MARGIN m, so the prompt doesn't flicker between two
## things at about the same distance.
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
		if not prompt.begins_with("["):
			s += INFO_COST
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
