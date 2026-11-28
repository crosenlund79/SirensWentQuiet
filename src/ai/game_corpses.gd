class_name GameCorpses
extends Node3D
## Experiment 012 (E): the enemies' names, deaths and bodies in the running
## game (`game.corpses`, the game_*.gd helper pattern), at home and at POIs.
##
##   names    every enemy gets HumanNames from its appearance seed (AIEnemy
##            .display_name); the roster keeps them unique in the scene
##   downed   §13: a compact toast "Walter Briggs — Brute — Downed" in the
##            HUD's toast stack; several downs in quick succession merge
##            ("... · +3 more") so a horde doesn't flood it
##   corpses  §14: every roster enemy keeps its body (AIEnemy.keep_corpse);
##            when it has settled it becomes a static Corpse (src/ai/corpse.gd)
##            under this node, with a name and loot; searching ([E]) opens
##            the same loot panel as containers (home: the storage panel;
##            POIs: the POI loot panel with the pack limit) on the corpse's
##            own items, so a full inventory leaves the rest on the body (§25)
##   persist  the records live in the saved state: state.home["corpses"] at
##            home, the POI record's "corpses" (state.region.poi[id], kept
##            between visits) at a POI; a body's record is written when it
##            dies, its items are the record's dictionary, and searched-empty
##            ones are dropped (cleaned up) after a search
##   F10      the Enemies tools (dev_*) and the perception debug labels

const FEED_GAP := 0.7             ## s between downed toasts
const FEED_MERGE := 2             ## this many waiting: one merged toast
const DEBUG_EVERY := 0.2

var game: Node
var bodies: Array = []            ## Corpse nodes here
var downed := 0                   ## downs seen (tests, F10)
var last_downed := ""             ## the last downed toast (tests)
var debug_on := false
var _feed: Array = []
var _feed_t := 0.0
var _debug_t := 0.0
var _labels := {}                 ## enemy instance id -> Label3D


func setup(g: Node) -> void:
	game = g
	name = "Corpses"
	var r: Variant = g.get("roster")
	if r is Node and is_instance_valid(r):
		r.connect("enemy_spawned", _on_spawned)
		r.connect("enemy_died", _on_died)
		for e in r.get("enemies"):
			if is_instance_valid(e) and e is AIEnemy:
				_on_spawned(e, (e as AIEnemy).kind)
	restore()


func _state() -> GameState:
	var s: Variant = game.get("state") if game != null else null
	return s if s is GameState else null


func _home() -> bool:
	return game == null or not game.has_method("is_home") or bool(game.call("is_home"))


## The saved list of this site's corpses (live in the state; created when missing).
func store() -> Array:
	var s := _state()
	if s == null:
		return []
	var d: Dictionary = s.home
	if not _home():
		var w: Variant = game.get("world")
		var id := str(w.get("poi_id")) if w is Object and is_instance_valid(w) and w.get("poi_id") != null else ""
		if id == "":
			return []
		d = PoiState.record(s, id)
		if d.is_empty():
			return []
	if typeof(d.get("corpses")) != TYPE_ARRAY:
		d["corpses"] = []
	return d["corpses"]


## Rebuilds the bodies from the saved list (cleaned in place; spent ones dropped).
func restore() -> void:
	var list := store()
	var keep := []
	for v in list:
		var d := Corpse.clean(v)
		if not d.is_empty() and not Corpse.is_spent(d):
			keep.append(d)
	list.clear()
	list.append_array(keep)
	for d in list:
		var c := Corpse.new()
		add_child(c)
		c.rebuild(d)
		bodies.append(c)


func _process(delta: float) -> void:
	HumanoidRig._sync_night()
	Corpse.sync_materials()
	_feed_t -= delta
	if not _feed.is_empty() and _feed_t <= 0.0:
		_flush_feed()
	if debug_on:
		_debug_t -= delta
		if _debug_t <= 0.0:
			_debug_t = DEBUG_EVERY
			_update_debug()


# --- deaths --------------------------------------------------------------------------------

func _on_spawned(e: Node, _kind: String) -> void:
	if not (e is AIEnemy):
		return
	var a := e as AIEnemy
	a.keep_corpse = true
	if not a.corpse_settled.is_connected(_on_settled):
		a.corpse_settled.connect(_on_settled)


func _on_died(e: Node, _kind: String, cause: String) -> void:
	if not (e is AIEnemy):
		return
	var a := e as AIEnemy
	if cause == "detonated":
		return                             # blown apart: no body, no name to report
	note_downed(a)
	if not a.keep_corpse:
		return
	var d := Corpse.record_for(a, _state())
	a.set_meta("corpse_data", d)
	if a.rig is HumanoidRig:
		(a.rig as HumanoidRig)._rng.seed = int(d["seed"])      # the same fall when rebuilt
	store().append(d)


func _on_settled(e: AIEnemy) -> void:
	if not is_instance_valid(e):
		return
	var d: Variant = e.get_meta("corpse_data", null)
	if typeof(d) != TYPE_DICTIONARY:
		e.queue_free()
		return
	var c := Corpse.new()
	add_child(c)
	c.adopt(e, d)
	bodies.append(c)
	e.queue_free()


# --- the downed toast ----------------------------------------------------------------------

func note_downed(e: AIEnemy) -> void:
	downed += 1
	var who := e.display_name if e.display_name != "" else "Someone"
	_feed.append("%s — %s" % [who, e.kind_label()])
	if _feed_t <= 0.0:
		_flush_feed()


func _flush_feed() -> void:
	var first: String = _feed.pop_front()
	var text := first + " — Downed"
	if _feed.size() >= FEED_MERGE:
		text += "  · +%d more" % _feed.size()
		_feed.clear()
	last_downed = text
	_feed_t = FEED_GAP
	if game != null and game.has_method("toast"):
		game.toast(text, "info")


# --- searching -----------------------------------------------------------------------------

## What [E] can reach here (the game's _interactables).
func interactables() -> Array:
	var pl: Variant = game.get("player") if game != null else null
	var y: float = (pl as Node3D).global_position.y if pl is Node3D else 0.0
	return bodies.filter(func(c): return is_instance_valid(c) and not (c as Corpse).spent() \
		and absf((c as Corpse).global_position.y - y) < 1.5)       # on Eli's storey


## [E] on a body: the loot panel on its items (home: the storage panel; a POI:
## the POI's loot panel, under the pack limit).
func search(c: Corpse) -> void:
	if not is_instance_valid(c) or game == null or str(game.get("_modal")) != "":
		return
	var s := _state()
	if s == null or s.dead:
		return
	var first := not c.searched()
	c.data["searched"] = true
	if first:
		Sfx.play_first(["poi/search", "door/open"], c.global_position + Vector3(0, 0.5, 0), -6.0)
	if c.items.is_empty():
		game.toast("%s had nothing worth taking." % c.display_name if c.display_name != "" else "Nothing on the body.", "info")
		cleanup()
		return
	var title := "%s · %s" % [c.display_name, HumanNames.kind_label(c.kind)] if c.display_name != "" else "The body"
	var poi: Variant = game.get("poi")
	if poi is Object and is_instance_valid(poi) and poi.get("panel") is PoiLootPanel:
		var panel: PoiLootPanel = poi.get("panel")
		if game.has_method("_set_modal"):
			game._set_modal("poi", true)
		panel.open_loot(s, c.items, title, poi)
		if "label_text" in panel and panel.has_method("_render"):
			panel.label_text = "pockets"            # "In the pockets" (the panel says "In the <label>")
			panel.call("_render")
		if not panel.closed.is_connected(cleanup):
			panel.closed.connect(cleanup, CONNECT_ONE_SHOT)
		return
	var st: Variant = game.get("storage")
	if st is Object and is_instance_valid(st) and st.get("panel") is StoragePanel:
		var sp: StoragePanel = st.get("panel")
		if game.get("build") != null and game.build.active and game.has_method("_set_build"):
			game._set_build(false)
		st.set("open_ref", {"world": game.get("world"), "object": null, "piece": "", "type": "corpse"})
		game._set_modal("storage", true)
		sp.open(s, "corpse", c.items, title)
		if not sp.closed.is_connected(cleanup):
			sp.closed.connect(cleanup, CONNECT_ONE_SHOT)
		return
	# no panel (tools): take what fits
	FurnitureStorage.take_all(s, c.items)
	cleanup()


## Drops searched-empty bodies from the saved list (the body stays until the scene ends).
func cleanup() -> void:
	var list := store()
	for i in range(list.size() - 1, -1, -1):
		if typeof(list[i]) == TYPE_DICTIONARY and Corpse.is_spent(list[i]):
			list.remove_at(i)


# --- F10: Enemies ----------------------------------------------------------------------------

func _player_pos() -> Vector2:
	var pl: Variant = game.get("player") if game != null else null
	if pl is Node3D:
		return Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	return Vector2.INF


func _roster() -> Node:
	var r: Variant = game.get("roster") if game != null else null
	return r if r is Node and is_instance_valid(r) else null


## A calm wanderer of `kind` 5-8 m from Eli where it can see him (so it
## reacts: startle, scream, charge). Falls back to any walkable point.
func dev_spawn_near(kind: String) -> String:
	var r := _roster()
	var me := _player_pos()
	var w: Variant = game.get("world") if game != null else null
	if r == null or me == Vector2.INF or not (w is HouseWorld):
		return "No roster."
	var nav: GridNav = (w as HouseWorld).nav
	var at := Vector2.INF
	var fallback := Vector2.INF
	for dist in [7.5, 6.5, 5.5, 8.5]:
		for i in 16:
			var q: Vector2 = me + Vector2.from_angle(TAU * float(i) / 16.0) * dist
			if nav == null or not nav.is_walkable(nav.cell_of(q)):
				continue
			if fallback == Vector2.INF:
				fallback = q
			if nav == null or nav.segment_clear(q, me):
				at = q
				break
		if at != Vector2.INF:
			break
	if at == Vector2.INF:
		at = fallback
	if at == Vector2.INF:
		return "No room for a %s here." % kind
	var opts := {"mode": "wander", "facing": atan2(-(me - at).x, -(me - at).y)}
	var s := _state()
	if s != null:
		opts["level"] = s.difficulty
	var e: Variant = r.call("spawn_type", kind, at, opts)
	if e is AIEnemy:
		var a := e as AIEnemy
		return "%s (%s) at %.1f m, calm until it sees you." % [a.display_name, a.kind_label(), at.distance_to(me)]
	return "Spawned."


## Kills the living enemy nearest to Eli (it leaves a body).
func dev_kill_nearest() -> String:
	var r := _roster()
	var me := _player_pos()
	if r == null or me == Vector2.INF:
		return "No roster."
	var best: AIEnemy = null
	for e in r.get("enemies"):
		if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive:
			if best == null or (e as AIEnemy).plan_pos().distance_to(me) < best.plan_pos().distance_to(me):
				best = e
	if best == null:
		return "Nobody alive here."
	var who := best.display_name
	best.take_damage(maxi(best.hp, 1), Vector3.FORWARD, "dev")
	return "%s (%s) is down; the body settles in %.0f s." % [who, best.kind_label(), Corpse.SETTLE]


## The living enemies with their names, kinds and states.
func dev_list_text() -> String:
	var r := _roster()
	var me := _player_pos()
	var lines := []
	if r != null:
		for e in r.get("enemies"):
			if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive:
				var a := e as AIEnemy
				lines.append("%s · %s · %s · %.0f m%s" % [a.display_name, a.kind_label(), a.state_name(),
					a.plan_pos().distance_to(me) if me != Vector2.INF else 0.0, " · reacting" if a.reaction != null and a.reaction.active() else ""])
	var n := interactables().size()
	return ("\n".join(lines) if not lines.is_empty() else "Nobody alive here.") + "\nBodies here: %d (%d with something on them)." % [bodies.filter(func(c): return is_instance_valid(c)).size(), n]


## The nearest living enemy screams (a shout noise; tests the hearing).
func dev_shout() -> String:
	var r := _roster()
	var me := _player_pos()
	if r == null:
		return "No roster."
	var best: AIEnemy = null
	for e in r.get("enemies"):
		if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive and (e as AIEnemy).reaction != null:
			if best == null or (e as AIEnemy).plan_pos().distance_to(me) < best.plan_pos().distance_to(me):
				best = e
	if best == null:
		return "Nobody here to shout."
	var heard_before := EnemyReaction.shouts_total
	best.reaction.shout(best)
	return "%s screams%s." % [best.display_name, "" if EnemyReaction.shouts_total > heard_before else " (silently: a runner's whim)"]


## Removes looted-clean bodies now (their nodes too).
func dev_clear_looted() -> String:
	var n := 0
	for c in bodies.duplicate():
		if is_instance_valid(c) and (c as Corpse).spent():
			bodies.erase(c)
			c.queue_free()
			n += 1
	cleanup()
	return "Cleared %d looted bod%s." % [n, "y" if n == 1 else "ies"]


func dev_toggle_debug() -> String:
	debug_on = not debug_on
	if not debug_on:
		for l in _labels.values():
			if is_instance_valid(l):
				l.queue_free()
		_labels.clear()
	return "Perception labels %s." % ("on" if debug_on else "off")


## Labels over every living enemy: name, kind, state, what it senses.
func _update_debug() -> void:
	var r := _roster()
	if r == null:
		return
	var seen := {}
	for e in r.get("enemies"):
		if not is_instance_valid(e) or not (e is AIEnemy) or not (e as AIEnemy).alive:
			continue
		var a := e as AIEnemy
		var id := a.get_instance_id()
		seen[id] = true
		var l: Label3D = _labels.get(id)
		if l == null or not is_instance_valid(l):
			l = Label3D.new()
			l.name = "PerceptionLabel"
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0018
			l.font_size = 22
			l.outline_size = 6
			l.position = Vector3(0, 2.4, 0)
			a.add_child(l)
			_labels[id] = l
		l.text = perception_text(a)
		l.modulate = Color(1.0, 0.45, 0.35) if not a.is_calm() else (Color(1.0, 0.85, 0.4) if a.mind.alert > 0.3 else Color(0.8, 0.9, 1.0))
	for id in _labels.keys():
		if not seen.has(id):
			if is_instance_valid(_labels[id]):
				_labels[id].queue_free()
			_labels.erase(id)


static func perception_text(a: AIEnemy) -> String:
	var t := "%s · %s\n%s" % [a.display_name, a.kind_label(), a.state_name()]
	if a.is_calm():
		t += " · alert %.1f" % a.mind.alert
		if a.mind.seen_t > 0.0:
			t += " · sees Eli"
		if a.mind.shouts > 0:
			t += " · heard a shout"
	else:
		t += " · hunting"
		if a.reaction != null and a.reaction.active():
			t += " · " + a.reaction.phase
	return t
