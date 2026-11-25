extends Node
## Exp 006 (B) "house and balance" in the running game. SurvivalGame creates
## it in _assemble() as `balance` (after storage and comfort; the game_*.gd
## pattern).
##
## - House supply (the user's §13): a HouseSupply over every storey's storage
##   furniture (storage.worlds()), handed to BuildMode as `supply`, so
##   building, repairing, upgrading and reinforcing pay from what you carry
##   and then from the house's containers.
## - TV and radio (§9, HouseMedia): E on a placed TV ("tv_stand") or radio,
##   or at the front of the house's own TV, switches it; it plays while the
##   house has power and the piece stands. Playing: the TV's screen glows and
##   flickers (an emissive pane and a cold light), the radio's dial glows, and
##   both make a faint generated static (no music; a later "Radio" sound from
##   the audio inbox can replace it). Comfort and mood read playing_sources()
##   (game_comfort.gd, HouseMedia's caps).
## - Saved: WorldObject "on" for placed pieces; the house TV in
##   GameState.run["media"] = {"tv_stand": bool}.
## - F10 "House & balance": dev_* below.

const REFRESH := 0.25
const HOUSE_TV := "tv_stand"            ## HousePlan furniture id of the house's own TV
const SCREEN := Color(0.62, 0.78, 1.0)
const STATIC_RATE := 22050
const STATIC_SECONDS := 1.6
const STATIC_DB := {"tv_stand": -27.0, "radio": -22.0}
const DEV_MATERIALS := {"wood": 30, "nails": 40, "stone": 20, "iron": 6, "scrap": 10}

static var _static_stream: AudioStreamWAV

var game: Node                         ## SurvivalGame
var state: GameState
var supply: HouseSupply
var tv_spot: Node3D                    ## MediaSpot in front of the house's TV
var last_text := ""                    ## the last dev / toast text (tests)
var _fx := {}                          ## source key -> {"node", "kind", "light", "pane", "sound"}
var _t := 0.0
var _clock := 0.0
var _root: Node3D


func setup(g: Node) -> void:
	game = g
	state = g.state
	supply = HouseSupply.new(state, worlds)
	var b = g.get("build")
	if b != null:
		b.set("supply", supply)
	_root = Node3D.new()
	_root.name = "BalanceNodes"
	add_child(_root)
	tv_spot = MediaSpot.new()
	tv_spot.name = "HouseTvSpot"
	tv_spot.helper = self
	_root.add_child(tv_spot)
	var f := _house_tv_plan()
	if not f.is_empty():
		var r: Rect2 = f["rect"]
		var front: Vector2 = {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}.get(f["facing"], Vector2(0, 1))
		var c := r.get_center() + front * (minf(r.size.x, r.size.y) * 0.5 + 0.3)
		tv_spot.position = Vector3(c.x, 0.0, c.y)
	refresh()


## The house's storeys (the ground floor first).
func worlds() -> Array:
	var st = game.get("storage") if game != null else null
	if st != null and st.has_method("worlds"):
		return st.call("worlds")
	return [game.world] if game != null and game.world != null else []


func interactables() -> Array:
	return [tv_spot] if tv_spot != null and house_tv_ok() else []


func _process(delta: float) -> void:
	_clock += delta
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH
		refresh()
	for k in _fx:
		var e: Dictionary = _fx[k]
		if e["kind"] == "tv_stand" and is_instance_valid(e["light"]):
			var ph := float(hash(k) % 97)
			var f := 0.72 + 0.18 * sin(_clock * 7.3 + ph) + 0.1 * sin(_clock * 23.0 + ph * 0.3)
			if sin(_clock * 0.9 + ph) > 0.93:
				f *= 0.55                       # a scene cut
			(e["light"] as OmniLight3D).light_energy = 0.9 * f
			var m: StandardMaterial3D = (e["pane"] as MeshInstance3D).material_override
			m.emission_energy_multiplier = 1.1 * f
			m.emission = SCREEN.lerp(Color(1.0, 0.86, 0.7), 0.5 + 0.5 * sin(_clock * 0.37 + ph))


# --- sources ---------------------------------------------------------------------------------

func _house_tv_plan() -> Dictionary:
	for f in HousePlan.FURNITURE:
		if f["id"] == HOUSE_TV:
			return f
	return {}


## The house's own TV still stands where it was (not moved, not wrecked).
func house_tv_ok() -> bool:
	var fur = game.world.furniture if game != null and game.world != null else null
	return fur != null and fur.pieces.has(HOUSE_TV) and fur.ok(HOUSE_TV)


func house_tv_on() -> bool:
	var m = state.run.get("media", {})
	return m is Dictionary and m.get(HOUSE_TV, false) == true


## The house has power (the fuse box's mains; the home helper's rule).
func powered() -> bool:
	var h = game.get("home")
	if h != null and h.has_method("mains_on"):
		return bool(h.call("mains_on"))
	return true


## Every TV and radio: [{"key", "kind", "storey", "pos": Vector2, "on", "ok",
## "object": WorldObject | null, "node": Node3D (its mesh)}].
func sources() -> Array:
	var out := []
	if game == null or game.world == null:
		return out
	if house_tv_ok():
		var f := _house_tv_plan()
		out.append({"key": "house:" + HOUSE_TV, "kind": "tv_stand", "storey": 0, "pos": (f["rect"] as Rect2).get_center(),
			"on": house_tv_on(), "ok": true, "object": null, "node": game.world.furniture.pieces[HOUSE_TV]["node"],
			"size": FurnitureCatalog.size_of_rect(f["rect"], f["height"], f["facing"])})
	for w in worlds():
		var s := int(w.get("storey")) if w.get("storey") != null else 0
		for o in w.objects:
			if HouseMedia.is_media(o.kind):
				out.append({"key": "%d:%s" % [s, o.uid if o.uid != "" else o.name], "kind": o.kind, "storey": s, "pos": o.pos,
					"on": o.media_on, "ok": o.hp > 0 and is_instance_valid(o), "object": o, "node": o.visual, "size": o.size3()})
	return out


## The sources that play now (switched on, standing, with power).
func playing_sources() -> Array:
	if not powered():
		return []
	return sources().filter(func(e): return e["on"] and e["ok"])


func media_signature() -> String:
	var parts := PackedStringArray()
	for e in playing_sources():
		parts.append(str(e["key"]))
	return ",".join(parts)


# --- switching ---------------------------------------------------------------------------------

func toggle_object(o: WorldObject) -> void:
	o.media_on = not o.media_on
	_switched(o.kind, o.media_on)


func toggle_house_tv() -> void:
	var m: Dictionary = state.run.get("media", {}) if state.run.get("media") is Dictionary else {}
	m[HOUSE_TV] = not house_tv_on()
	state.run["media"] = m
	_switched("tv_stand", m[HOUSE_TV])


func _switched(kind: String, on: bool) -> void:
	Sfx.ui("ui/click")
	var name: String = HouseMedia.NAMES.get(kind, kind)
	if on and not powered():
		_say(HouseMedia.NO_POWER, "warn")
	elif on:
		_say("The %s comes on: %s." % [name, "a test card, then an old film" if kind == "tv_stand" else "soft static, now and then a voice"], "info")
	refresh()
	var c = game.get("comfort")
	if c != null and c.has_method("recompute"):
		c.call("recompute")


func _say(text: String, kind: String) -> void:
	last_text = text
	if game != null and game.has_method("toast"):
		game.toast(text, kind)


# --- effects -------------------------------------------------------------------------------------

## Brings the screen glow, dial and static in line with what plays.
func refresh() -> void:
	var live := {}
	var power := powered()
	for e in sources():
		var plays: bool = e["on"] and e["ok"] and power
		var node: Variant = e["node"]
		if e["kind"] == "radio" and node is Node3D and is_instance_valid(node):
			PropKit.set_lit(node, 1.0 if plays else 0.0)
		if not plays or not (node is Node3D) or not is_instance_valid(node):
			continue
		live[e["key"]] = true
		var fx: Dictionary = _fx.get(e["key"], {})
		if fx.is_empty() or not is_instance_valid(fx["node"]) or (fx["node"] as Node).get_parent() != node:
			if not fx.is_empty() and is_instance_valid(fx["node"]):
				(fx["node"] as Node).queue_free()
			_fx[e["key"]] = _make_fx(e["kind"], node, e["size"])
	for k in _fx.keys():
		if not live.has(k):
			if is_instance_valid(_fx[k]["node"]):
				(_fx[k]["node"] as Node).queue_free()
			_fx.erase(k)


## The playing look of a source, as a child of its mesh (PropKit's canonical
## frame: front +z, ground at 0): the TV's glowing pane and light, a static hiss.
func _make_fx(kind: String, parent: Node3D, size: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "MediaFx"
	var out := {"node": root, "kind": kind, "light": null, "pane": null, "sound": null}
	if kind == "tv_stand":
		var w := size.x
		var h := size.y
		var top := minf(0.5, h * 0.45)
		var tw := minf(1.25, w * 0.7)
		var ty0 := top + 0.06
		var pane := MeshInstance3D.new()
		pane.name = "Screen"
		var q := QuadMesh.new()
		q.size = Vector2(tw - 0.04, h - ty0 - 0.04)
		pane.mesh = q
		pane.position = Vector3(0, (ty0 + h) * 0.5, 0.009)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.55, 0.65, 0.8)
		m.emission_enabled = true
		m.emission = SCREEN
		m.emission_energy_multiplier = 1.1
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		pane.material_override = m
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pane)
		var l := OmniLight3D.new()
		l.name = "ScreenLight"
		l.light_color = SCREEN
		l.omni_range = 3.6
		l.omni_attenuation = 1.6
		l.light_energy = 0.9
		l.light_specular = 0.1
		l.shadow_enabled = false
		l.position = Vector3(0, (ty0 + h) * 0.5, 0.6)
		root.add_child(l)
		out["light"] = l
		out["pane"] = pane
	var p := AudioStreamPlayer3D.new()
	p.name = "Static"
	p.stream = static_stream()
	p.volume_db = float(STATIC_DB.get(kind, -26.0))
	p.pitch_scale = 0.7 if kind == "tv_stand" else 1.0
	p.unit_size = 1.6
	p.max_distance = 9.0
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	p.position = Vector3(0, minf(size.y, 1.0) * 0.7, 0.1)
	root.add_child(p)
	out["sound"] = p
	parent.add_child(root)
	if p.is_inside_tree():
		p.play()
	return out


## A soft looping hiss with a faint crackle (generated once; no recorded sound).
static func static_stream() -> AudioStreamWAV:
	if _static_stream != null:
		return _static_stream
	var n := int(STATIC_RATE * STATIC_SECONDS)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6006
	var lp := 0.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.35                    # soften the hiss
		var v := lp * 0.5
		if rng.randf() < 0.0008:
			v += rng.randf_range(-0.6, 0.6)          # crackle
		var fade := minf(1.0, minf(float(i), float(n - i)) / 400.0)    # seamless loop
		v *= 0.6 + 0.4 * fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 12000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = STATIC_RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	_static_stream = s
	return s


# --- F10 "House & balance" ------------------------------------------------------------------------

func dev_aurora_preview() -> String:
	var h = game.get("home")
	var sky = h.get("sky") if h != null else null
	if sky == null or not sky.has_method("toggle_preview"):
		return "No northern lights here."
	var o: float = sky.call("toggle_preview")
	return "Northern lights tonight at %d %% (%s)" % [roundi(o * 100.0), "the old look" if o > 0.99 else "the new subtle look"]


func dev_spawn(kind: String) -> String:
	var r = game.get("roster")
	if r == null or not r.has_method("spawn_type"):
		return "No enemy roster."
	var p: Vector2 = game.player.plan_pos()
	var at := p + Vector2(3.0, 0.0).rotated(randf() * TAU)
	at = at.clamp(HouseWorld.LOT.position + Vector2.ONE, HouseWorld.LOT.end - Vector2.ONE)
	var opts := {"level": state.difficulty, "invasion": maxi(state.invasion_index(), 1)} if state.has_method("invasion_index") else {}
	r.call("spawn_type", kind, at, opts)
	var st := EnemyDefs.stats(kind, state.difficulty, maxi(state.invasion_index(), 1))
	return "%s at %.1f m/s, swings every %.2f s, %d hp" % [EnemyDefs.get_def(kind)["name"], float(EnemyDefs.get_def(kind)["speed"]) * st["speed_scale"],
		float(EnemyDefs.get_def(kind)["attack_interval"]) * st["attack_scale"], st["hp"]]


## Walls up the window nearest to the player (on the player's storey).
func dev_remove_window() -> String:
	var w := _player_world()
	if w == null:
		return "No house here."
	var p: Vector2 = game.player.plan_pos()
	var best := []
	var best_d := INF
	for s in w.sections:
		if not WindowFill.is_window(w, s):
			continue
		var d := HouseWorld.seg_center(s).distance_to(p)
		if d < best_d:
			best_d = d
			best = WindowFill.window_segments(w, s)
	if best.is_empty():
		return "No window on this level."
	var why := WindowFill.block_reason(w, best)
	if why != "":
		return why
	WindowFill.fill(w, best)
	return "Walled up the %d m window at %s (free)." % [best.size(), str(HouseWorld.seg_center(best[0]))]


## Switches the nearest TV or radio (or the house TV).
func dev_toggle_media() -> String:
	var p: Vector2 = game.player.plan_pos()
	var best: Dictionary = {}
	var best_d := INF
	for e in sources():
		var d: float = (e["pos"] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		return "No TV or radio: build one (B, Furniture) or the house TV is gone."
	if best["object"] != null:
		toggle_object(best["object"])
	else:
		toggle_house_tv()
	var now := playing_sources().any(func(e): return e["key"] == best["key"])
	return "%s %s%s" % [HouseMedia.NAMES.get(best["kind"], "?").capitalize(), "playing" if now else "off",
		" (no power)" if not powered() else ""]


## A radio in front of the player (a quick test piece).
func dev_place_radio() -> String:
	var w := _player_world()
	if w == null:
		return "No house here."
	var p: Vector2 = game.player.plan_pos() + Vector2(0.0, 0.6)
	var o := w.place_object("radio", p, 2, true)
	o.media_on = true
	refresh()
	return "Radio placed and on at %s" % str(p)


func dev_foundation_kit() -> String:
	state.inventory.add("stone", 20)
	state.inventory.add("wood", 20)
	state.inventory.add("nails", 20)
	return "Foundation kit: +20 stone, +20 planks, +20 nails (B, 0: stone foundation, timber footing)"


## Fills the nearest storage container with materials (storage payment test).
func dev_fill_chest() -> String:
	var p: Vector2 = game.player.plan_pos()
	var best: Dictionary = {}
	var best_d := INF
	for c in supply.containers():
		if not FurnitureStorage.accepts(str(c["type"]), "wood") or FurnitureStorage.space_left(str(c["type"]), c["items"]) < 10:
			continue
		var d: float = (c.get("pos", Vector2.INF) as Vector2).distance_to(p) if c.get("pos") is Vector2 else 999.0
		if d < best_d:
			best_d = d
			best = c
	if best.is_empty():
		var w := _player_world()
		if w == null:
			return "No house here."
		var o := w.place_object("storage_chest", p + Vector2(0.0, 0.8), 0, true)
		best = {"type": "storage_chest", "items": o.items, "name": "Storage chest"}
	var put := {}
	for k in DEV_MATERIALS:
		var room := mini(int(DEV_MATERIALS[k]), FurnitureStorage.space_left(str(best["type"]), best["items"]))
		if room > 0 and FurnitureStorage.accepts(str(best["type"]), k):
			best["items"][k] = int(best["items"].get(k, 0)) + room
			put[k] = room
	return "%s: +%s (build mode pays from it)" % [str(best.get("name", "Chest")), BuildPieces.cost_text(put)]


func dev_supply_text() -> String:
	var parts := PackedStringArray()
	for k in ["wood", "stone", "iron", "nails", "scrap"]:
		parts.append("%s %s" % [Items.name_of(k), supply.count_text(k)])
	return "Supply: " + " · ".join(parts) + " · playing: " + (media_signature() if media_signature() != "" else "nothing")


func _player_world() -> HouseWorld:
	var lv = game.get("levels")
	if lv != null and lv.has_method("active_world"):
		return lv.call("active_world")
	return game.world


## "[E] Turn the TV on" in front of the house's own TV.
class MediaSpot extends Node3D:
	var helper: Object

	func interact_prompt() -> String:
		if helper == null or not helper.house_tv_ok():
			return ""
		return HouseMedia.prompt("tv_stand", helper.house_tv_on())

	func interact(_g: Node) -> void:
		helper.toggle_house_tv()
