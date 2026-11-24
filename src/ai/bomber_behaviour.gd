extends EnemyBehaviour
## The suicide bomber (SPEC-003 §5): it goes for the house's defences, never
## the player.
##   seek  pick from world.weak_points(from, player) (doors, barricades,
##         weak walls, ranked by the world; the player's position only raises
##         the walls near them), keep the first usable one and commit to it:
##         walk to its stand point on the OUTSIDE face (skipping open doors,
##         breached walls, stand points inside the house, unreachable ones and
##         targets another bomber claimed); re-pick only if the target is
##         gone (destroyed or walk-through) before arrival
##   fuse  at the face: stop, face the wall, fuse_started(e, at, FUSE) for the
##         HUD, a pulsing light that speeds up and a beep (FUSE_SOUND, falls
##         back to an existing name) for `fuse` seconds
##   blast world.explode(stand point 1 m up, blast_radius, blast_power) (the
##         world's recommended use: one blast breaches a wooden or house wall
##         or a wooden door; stone needs two), last_blast = its result,
##         detonated(at, blast_reach, blast_damage): the roster hurts other
##         enemies, the game hurts the player; the bomber vanishes
## Killed early (design choice, docs/experiment-003/ai.md):
##   before the fuse is lit -> it FIZZLES: sparks and smoke, no damage at all;
##   while the fuse burns   -> a small POP: no structural damage, characters
##                             within small_reach take up to small_damage.
## Fictional and abstract on purpose: a glowing pack, a beep, a blast.

const FUSE_SOUND := "enemy/bomber_fuse"      ## requested from the lead
const FUSE_SOUND_FALLBACK := "ui/error"
const BLAST_SOUNDS := ["enemy/bomber_blast", "structure/break"]
const FIZZLE_SOUND := "weapon/dry_fire"
const APPROACH := 0.6           ## m from the wall line to the stand point (foundation format)
const ARRIVE := 0.35            ## m from the stand point
const BLAST_HEIGHT := 1.0       ## m, blast centre height
const RETARGET := 1.0           ## s between target validity checks
const STALL_FUSE := 2           ## stalls in a row before it blows the nearest wall where it is
const BREACHED := 0.25          ## wall integrity below which it isn't worth a bomb

## World + target key -> bomber instance id (spreads several bombers).
static var _claims := {}

var state := "seek"             ## seek | fuse | spent
var target := {}                ## {"kind", "pos", "approach", "normal", "seg", "object", "key"}
var fuse_left := 0.0
var fuse_at := Vector3.ZERO
var picks := 0                  ## targets chosen (tests)
var last_blast := {}            ## world.explode's result (tests, debug)
var _check_t := 0.0
var _stalls := 0
var _beep_t := 0.0
var _pulse := 0.0


func configure(e: AIEnemy) -> void:
	var b := e.brain
	b.attack_goal = false
	b.bash = false
	b.arrive_radius = ARRIVE


func state_name() -> String:
	return state


func goal(e: AIEnemy) -> Vector2:
	if state != "seek":
		return e.plan_pos()
	_check_t -= e.get_physics_process_delta_time()
	if target.is_empty() or (_check_t <= 0.0 and not _still_valid(e)):
		_pick(e)
	if _check_t <= 0.0:
		_check_t = RETARGET
	if target.is_empty():
		# Nothing to bomb (no world or no defences): drift toward the house.
		return HousePlan.FOOTPRINT.get_center()
	return target["approach"]


func think(e: AIEnemy, delta: float, r: Dictionary) -> Dictionary:
	_animate(e, delta)
	match state:
		"seek":
			if target.is_empty():
				return r
			var me := e.plan_pos()
			if r["arrived"] or me.distance_to(target["approach"]) <= ARRIVE + 0.05:
				_light(e)
			elif r["stalled"]:
				_stalls += 1
				if _stalls >= STALL_FUSE and _wall_here(e):
					_light(e)
		"fuse":
			r["move"] = Vector2.ZERO
			r["swing"] = ""
			r["face"] = -(target.get("normal", Vector2.UP) as Vector2)
			fuse_left -= delta
			_beep_t -= delta
			if _beep_t <= 0.0:
				_beep_t = maxf(0.25, 0.55 * fuse_left / float(e.def["fuse"]) + 0.15)
				Sfx.play(_fuse_sound(), e.global_position + Vector3(0, 1.2, 0))
			if fuse_left <= 0.0:
				_detonate(e)
		_:
			r["move"] = Vector2.ZERO
	return r


func on_death(e: AIEnemy, cause: String) -> void:
	if state == "spent":
		return
	var was := state
	state = "spent"
	_release(e)
	var at := e.global_position + Vector3(0, 1.0, 0)
	_glow(e, 0.0, 0.0)
	if was == "fuse" and cause != "quiet":
		_pop(e, at)
	else:
		_fizzle(e, at)


# --- targets ---------------------------------------------------------------------------

func _pick(e: AIEnemy) -> void:
	_release(e)
	target = {}
	var w := e.world
	if w == null or not w.has_method("weak_points"):
		return
	var me := e.plan_pos()
	var pts: Array
	if e.player != null and is_instance_valid(e.player) and w.get_method_argument_count("weak_points") >= 2:
		pts = w.weak_points(me, Vector2(e.player.global_position.x, e.player.global_position.z))
	else:
		pts = w.weak_points(me)
	for p in pts:
		var t := describe(w, p)
		if t.is_empty() or _claimed(e, t["key"]):
			continue
		var path: PackedVector2Array = e.brain.planner.find_path(me, t["approach"]) if e.brain.planner != null else e.nav.find_path(me, t["approach"])
		if path.is_empty() or path[path.size() - 1].distance_to(t["approach"]) > 0.6:
			continue
		target = t
		_claims[t["key"]] = e.get_instance_id()
		picks += 1
		_stalls = 0
		e.brain.invalidate()
		return


## A weak point as a bomb target: "pos" (the target point), "approach" (the
## stand point on the outside face), "normal" (outward), "seg", "object".
## {} when it isn't usable: an open or broken object, a walk-through wall, a
## stand point inside the house. Reads the world's entries ({pos = stand
## point, target, seg, object}); the foundation format ({pos = the target})
## still works.
static func describe(w: HouseWorld, p: Dictionary) -> Dictionary:
	var kind := str(p.get("kind", "wall"))
	if p.has("target"):
		var stand: Vector2 = p["pos"]
		var tgt: Vector2 = p["target"]
		var o = p.get("object")
		var obj: WorldObject = o if o is WorldObject and is_instance_valid(o) else null
		if o != null and obj == null:
			return {}
		if obj != null and ((obj.kind == "door" and obj.open) or not obj.bashable()):
			return {}
		if obj == null and w.nav.is_walkable(w.nav.cell_of(tgt)):
			return {}
		if HousePlan.FOOTPRINT.grow(-0.05).has_point(stand) or not HousePlan.YARD.grow(-0.3).has_point(stand):
			return {}
		var seg2: Vector3i = p.get("seg", HouseWorld.nearest_seg(tgt))
		var n2 := (stand - tgt).normalized()
		return {"kind": kind, "pos": tgt, "approach": stand, "normal": n2, "seg": seg2, "object": obj, "has_object": obj != null,
			"key": "%d:%d,%d,%d" % [w.get_instance_id(), seg2.x, seg2.y, seg2.z]}
	var pos: Vector2 = p["pos"]
	var seg := HouseWorld.nearest_seg(pos)
	var sign := w.outer_sign(seg)
	var n := Vector2(0, sign) if seg.x == 0 else Vector2(sign, 0)
	var line_pos := Vector2(pos.x, seg.y) if seg.x == 0 else Vector2(seg.y, pos.y)
	var approach := line_pos + n * APPROACH
	if HousePlan.FOOTPRINT.grow(-0.05).has_point(approach) or not HousePlan.YARD.grow(-0.5).has_point(approach):
		return {}
	var obj: WorldObject = w.object_at(pos, 0.05) if kind != "wall" else null
	if obj != null:
		if (obj.kind == "door" and obj.open) or not obj.bashable():
			return {}
	elif kind in ["door", "barricade"]:
		return {}
	elif w.sections.has(seg) and w.section_integrity(seg) < BREACHED:
		return {}
	return {"kind": kind, "pos": line_pos, "approach": approach, "normal": n, "seg": seg, "object": obj, "has_object": obj != null,
		"key": "%d:%d,%d,%d" % [w.get_instance_id(), seg.x, seg.y, seg.z]}


func _still_valid(e: AIEnemy) -> bool:
	if target.is_empty() or e.world == null:
		return false
	if target.get("has_object", false):
		var obj = target["object"]       # untyped: it may have been freed
		return is_instance_valid(obj) and e.world.objects.has(obj) and obj.bashable()
	if str(target["key"]).begins_with("stall:"):
		return true
	if e.world.nav.is_walkable(e.world.nav.cell_of(target["pos"])):
		return false                     # already walk-through
	var seg: Vector3i = target["seg"]
	return not e.world.sections.has(seg) or e.world.section_integrity(seg) >= BREACHED


func _claimed(e: AIEnemy, key: String) -> bool:
	if not _claims.has(key):
		return false
	var other := instance_from_id(_claims[key])
	if other == null or other == e or not (other is AIEnemy) or not (other as AIEnemy).alive:
		_claims.erase(key)
		return false
	return true


func _release(e: AIEnemy) -> void:
	if not target.is_empty() and _claims.get(target["key"]) == e.get_instance_id():
		_claims.erase(target["key"])


## Stalled near some wall without reaching the face: make that wall the target.
func _wall_here(e: AIEnemy) -> bool:
	var me := e.plan_pos()
	var c := e.nav.nearest_raw_wall(e.nav.cell_of(me), me, 5)
	if c.x < 0 or e.nav.center_of(c).distance_to(me) > 1.3:
		return false
	var wp := e.nav.center_of(c)
	var n := (me - wp).normalized()
	target = {"kind": "wall", "pos": wp, "approach": me, "normal": n, "seg": HouseWorld.nearest_seg(wp), "object": null, "key": "stall:%d" % e.get_instance_id()}
	return true


# --- fuse and blast ------------------------------------------------------------------------

func _light(e: AIEnemy) -> void:
	state = "fuse"
	fuse_left = float(e.def["fuse"])
	_beep_t = 0.0
	var c: Vector2 = target["approach"]          # the stand point, as the world recommends
	fuse_at = Vector3(c.x, BLAST_HEIGHT, c.y)
	e.fuse_started.emit(e, fuse_at, fuse_left)


func _detonate(e: AIEnemy) -> void:
	state = "spent"
	_release(e)
	var d := e.def
	var at := fuse_at
	last_blast = {}
	if e.world != null and e.world.has_method("explode"):
		var res = e.world.explode(at, float(d["blast_radius"]), float(d["blast_power"]))
		last_blast = res if res is Dictionary else {}
	if last_blast.has("breach"):
		# The world's blast brings its own flash, fireball, debris and sounds.
		if Sfx.has(BLAST_SOUNDS[0]):
			Sfx.play(BLAST_SOUNDS[0], at)
	else:
		_flash(e, at, 9.0, 6.0)
		_debris(e, at, 1.0)
		for snd in BLAST_SOUNDS:
			if Sfx.has(snd):
				Sfx.play(snd, at)
				break
	e.death_cause = "detonated"
	e.detonated.emit(at, float(d["blast_reach"]), e.blast_damage)
	e.died.emit(e, "detonated")
	e.vanish()


func _pop(e: AIEnemy, at: Vector3) -> void:
	_flash(e, at, 4.0, 3.0)
	_debris(e, at, 0.4)
	Sfx.play("structure/break", at)
	e.detonated.emit(at, float(e.def["small_reach"]), e.small_damage)


func _fizzle(e: AIEnemy, at: Vector3) -> void:
	var fx := e.world.fx if e.world != null else null
	if fx != null:
		fx.sparks(at, Vector3.UP, 10, 3.0)
		for k in 5:
			fx.puff(at + Vector3(randf_range(-0.15, 0.15), 0.1 * k, randf_range(-0.15, 0.15)),
				Vector3(0, 0.6, 0), Color(0.35, 0.34, 0.33, 0.6), 0.25, 0.8, 1.6)
	Sfx.play(FIZZLE_SOUND, at)
	e.fizzled.emit(e, at)


func _debris(e: AIEnemy, at: Vector3, k: float) -> void:
	var fx := e.world.fx if e.world != null else null
	if fx == null:
		return
	fx.sparks(at, Vector3.UP, int(30 * k), 9.0)
	for i in int(14 * k):
		var v := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		fx.puff(at + v * 0.3, v * 2.2, Color(0.3, 0.28, 0.26, 0.75), 0.45, 1.6, 2.4)


func _flash(e: AIEnemy, at: Vector3, energy: float, range_m: float) -> void:
	var host := e.get_parent()
	if host == null:
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.omni_range = range_m
	l.light_energy = energy
	l.shadow_enabled = false
	host.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)


static func _fuse_sound() -> String:
	return FUSE_SOUND if Sfx.has(FUSE_SOUND) else FUSE_SOUND_FALLBACK


# --- the pack's light ----------------------------------------------------------------------------

func _animate(e: AIEnemy, delta: float) -> void:
	if state == "fuse":
		var k := 1.0 - clampf(fuse_left / float(e.def["fuse"]), 0.0, 1.0)
		_pulse += delta * lerpf(3.0, 11.0, k) * TAU
		var on := 0.5 + 0.5 * sin(_pulse)
		_glow(e, lerpf(1.2, 3.8, on), lerpf(1.5, 6.0, on))
		e.rig.stagger = 0.15 + 0.1 * on          # trembles
	elif state == "seek":
		_pulse += delta * 1.4 * TAU
		var on := 0.5 + 0.5 * sin(_pulse)
		_glow(e, lerpf(0.35, 1.3, on), lerpf(0.8, 2.2, on))


func _glow(e: AIEnemy, light: float, emission: float) -> void:
	var l: OmniLight3D = e.extras.get("light")
	if l != null:
		l.light_energy = light
		l.visible = light > 0.01
	var m: StandardMaterial3D = e.extras.get("pack_mat")
	if m != null:
		m.emission_energy_multiplier = emission
	var lm: StandardMaterial3D = e.extras.get("lamp_mat")
	if lm != null:
		lm.emission_energy_multiplier = emission * 1.4
