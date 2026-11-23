extends RefCounted
## Picks what [E] acts on: the nearest interactable (SPEC §7.3 duck type:
## interact_prompt() -> String, "" hides; interact(game)) within RADIUS of the
## player whose prompt is not empty.

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
		best = n
		best_d = d
	return best
