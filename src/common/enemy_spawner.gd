class_name EnemySpawner
extends RefCounted
## Steady, modest spawn rhythm shared by all versions (see Tuning).

var enabled := true
var rng := RandomNumberGenerator.new()
var _timer := Tuning.SPAWN_FIRST_DELAY


## Call every frame. Returns a spawn point (plan meters) when an enemy
## should appear, otherwise null.
func tick(delta: float, alive: int, player: Vector2) -> Variant:
	if not enabled:
		return null
	_timer -= delta
	if _timer > 0.0:
		return null
	_timer = Tuning.SPAWN_INTERVAL
	if alive >= Tuning.MAX_ENEMIES:
		return null
	var options := []
	for p in HousePlan.SPAWN_POINTS:
		if (p as Vector2).distance_to(player) >= Tuning.SPAWN_MIN_DISTANCE:
			options.append(p)
	if options.is_empty():
		options = HousePlan.SPAWN_POINTS.duplicate()
	return options[rng.randi_range(0, options.size() - 1)]
