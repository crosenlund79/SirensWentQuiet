class_name EnemyBehaviour
extends RefCounted
## The small per-archetype hook of the shared AI (SPEC-003 §5). AIEnemy owns
## the body, movement, swings, damage, stagger and death; PursuitBrain owns
## pathing, bashing and the stuck rules. A behaviour only decides:
##   configure(e)          brain settings for the archetype (once, at spawn)
##   goal(e) -> Vector2    where to go this frame (plan metres)
##   think(e, dt, r) -> r  adjust the brain's decision (e.g. stop and fuse)
##   on_death(e, cause)    react to dying (e.g. the bomber's fizzle or pop)
## The base class is the "chase" behaviour used by the psycho, the runner and
## the brute: hunt the player; their differences are data (EnemyDefs).

const SCRIPTS := {
	"chase": "res://src/ai/enemy_behaviour.gd",
	"bomber": "res://src/ai/bomber_behaviour.gd",
}


static func make(name: String) -> EnemyBehaviour:
	return load(SCRIPTS.get(name, SCRIPTS["chase"])).new()


func configure(e: AIEnemy) -> void:
	var b := e.brain
	b.attack_goal = true
	b.bash = int(e.def["wall_strikes"]) > 0


## Chasers hunt the player (the retreat is handled by AIEnemy).
func goal(e: AIEnemy) -> Vector2:
	if e.player == null or not is_instance_valid(e.player):
		return e.plan_pos()
	return Vector2(e.player.global_position.x, e.player.global_position.z)


func think(_e: AIEnemy, _delta: float, r: Dictionary) -> Dictionary:
	return r


func on_death(_e: AIEnemy, _cause: String) -> void:
	pass


## A short label for debug overlays and tests.
func state_name() -> String:
	return "chase"
