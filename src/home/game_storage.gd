extends Node
## Experiment 005 (F): storage furniture and placed lamps in the survival
## game. SurvivalGame creates it in _assemble() as `storage` (the game_*.gd
## pattern).
##
## - Storage: E on a storage piece (WorldObject.interact / the house's
##   StorageSpots) calls open_object / open_piece: the game pauses on modal
##   "storage" and the StoragePanel shows that container's live contents.
##   Closing it unpauses; a loot pile searched empty disappears.
## - Lamps: placed floor and table lamps shine while the house has power
##   (the game's home.mains_on(): a fuse box with its mains on, as the
##   electric fixtures) and their own switch is on (refresh_lamps, on power
##   and layout changes and twice a second). Table lamps whose surface went
##   come down (FurniturePlace.settle_lamps).
## - F10 "Furniture": dev_furniture_kit, dev_storage_items, dev_containers_text.

const KIT := ["cupboard", "wardrobe", "storage_chest", "shelves", "tool_cabinet", "bed", "sofa", "rug", "painting"]
const ITEMS_PACK := {"canned_food": 4, "snacks": 4, "water": 4, "bandage": 2, "medkit": 1, "ammo": 12, "wood": 10, "nails": 20,
	"scrap": 5, "flashlight": 1, "crowbar": 1, "vest": 1}
const REFRESH := 0.5

var game: Node                         ## SurvivalGame
var panel: StoragePanel
var open_ref := {}                     ## {"world", "object" | null, "piece", "type"} while the panel is open
var _connected := {}                   ## HouseWorld instance id -> true
var _t := 0.0


func setup(g: Node) -> void:
	game = g
	panel = StoragePanel.new()
	panel.name = "StoragePanel"
	add_child(panel)
	panel.closed.connect(_on_closed)
	_watch_worlds()
	refresh_lamps()


## The house's storeys (the ground floor first): SPEC §1 levels API when
## present, else the Experiment 004 upper floor and basement.
func worlds() -> Array:
	var out := []
	if game == null:
		return out
	if game.world != null:
		out.append(game.world)
	var l: Variant = game.get("levels")
	if l is Object and is_instance_valid(l):
		if l.has_method("storeys") and l.has_method("world_of"):
			for s in l.storeys():
				var w: Variant = l.world_of(s)
				if w is HouseWorld and not out.has(w):
					out.append(w)
		else:
			for k in ["basement", "upper"]:
				var w: Variant = l.get(k)
				if w is HouseWorld and is_instance_valid(w) and not out.has(w):
					out.append(w)
	return out


func _watch_worlds() -> void:
	for w in worlds():
		var key: int = (w as Object).get_instance_id()
		if _connected.has(key):
			continue
		_connected[key] = true
		w.furniture_layout_changed.connect(_on_layout.bind(w))
		w.power_changed.connect(refresh_lamps)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH
		_watch_worlds()
		refresh_lamps()
		settle_piles()


## Loot piles upstairs with no floor under them any more (a collapse, a hole)
## fall to the storey below, merged into a pile there. Returns how many fell.
func settle_piles() -> int:
	var n := 0
	for w in worlds():
		if not (w is LevelWorld) or int(w.get("storey")) <= 0 or not w.has_method("has_floor_at"):
			continue
		for o in w.objects.duplicate():
			if o.kind != "loot_pile" or w.has_floor_at(o.pos):
				continue
			var below := _world_below(int(w.get("storey")))
			if below == null:
				continue
			var keep: Dictionary = o.items.duplicate()
			o.items.clear()
			w.remove_object(o)
			below.drop_loot(o.pos, keep)
			n += 1
	return n


func _world_below(storey: int) -> HouseWorld:
	var l: Variant = game.get("levels")
	if storey - 1 == 0 or not (l is Object) or not is_instance_valid(l) or not l.has_method("world_of"):
		return game.world
	var w: Variant = l.world_of(storey - 1)
	return w if w is HouseWorld else game.world


# --- storage ---------------------------------------------------------------------------

func _can_open() -> bool:
	return game != null and game.get("_modal") == "" and not game.state.dead


## E on an original storage piece of `world`.
func open_piece(world: HouseWorld, id: String) -> void:
	if not _can_open() or world.furniture == null:
		return
	var t := world.furniture.storage_type(id)
	if t == "":
		return
	_open({"world": world, "object": null, "piece": id, "type": t}, world.furniture.items_of(id))


## E on a placed storage piece or a loot pile.
func open_object(o: WorldObject) -> void:
	if not _can_open() or o == null:
		return
	var t := o.kind if o.kind == "loot_pile" else o.storage_type()
	if t == "":
		return
	_open({"world": o.world, "object": o, "piece": "", "type": t}, o.items)


func _open(ref: Dictionary, contents: Dictionary) -> void:
	if game.build != null and game.build.active and game.has_method("_set_build"):
		game._set_build(false)
	open_ref = ref
	game._set_modal("storage", true)
	panel.open(game.state, ref["type"], contents)


func is_open() -> bool:
	return panel != null and panel.is_open


func close_panel() -> void:
	if panel.is_open:
		panel._close_and_emit()


func _on_closed() -> void:
	var o: Variant = open_ref.get("object")
	open_ref = {}
	if o is WorldObject and is_instance_valid(o) and o.kind == "loot_pile" and o.items.is_empty() and o.world != null:
		o.world.remove_object(o)        # searched empty: the pile goes
	if game.get("_modal") == "storage":
		game._set_modal("", false)


# --- lamps -----------------------------------------------------------------------------

func _house_power() -> bool:
	var h: Variant = game.get("home") if game != null else null
	if h is Object and is_instance_valid(h) and h.has_method("mains_on"):
		return bool(h.mains_on())
	var fb: Variant = game.world.fuse_box() if game != null and game.world != null else null
	return fb != null and bool(fb.mains_on)


func refresh_lamps() -> void:
	if game == null:
		return
	var on := _house_power()
	for w in worlds():
		for o in w.objects:
			if FurnitureCatalog.is_lamp(o.kind):
				o.set_powered(on)


## Every lit placed lamp (comfort and tests).
func lit_lamps() -> Array:
	var out := []
	for w in worlds():
		for o in w.objects:
			if FurnitureCatalog.is_lamp(o.kind) and o.is_lit():
				out.append(o)
	return out


func _on_layout(w: HouseWorld) -> void:
	if is_instance_valid(w):
		FurniturePlace.settle_lamps(w)
	refresh_lamps()


# --- F10 "Furniture" --------------------------------------------------------------------

func _active_world() -> HouseWorld:
	var l: Variant = game.get("levels")
	if l is Object and is_instance_valid(l) and l.has_method("active_world"):
		return l.active_world()
	return game.world


## One of each storage type plus a bed, a sofa, a rug and a painting, placed
## (free) in free spots around the player on the player's storey.
func dev_furniture_kit() -> String:
	var w := _active_world()
	var pp: Vector2 = game.player.plan_pos()
	var done := []
	var missed := []
	for kind in KIT:
		if _place_near(w, kind, pp):
			done.append(kind.replace("_", " "))
		else:
			missed.append(kind.replace("_", " "))
	var text := "Placed %d: %s." % [done.size(), ", ".join(done)]
	if not missed.is_empty():
		text += " No room for: %s." % ", ".join(missed)
	return text


func _place_near(w: HouseWorld, kind: String, at: Vector2) -> bool:
	var size: Vector3 = WorldObject.DEFS[kind]["size"]
	if FurnitureCatalog.is_wall_hung(kind):
		for k in 24:
			var a := k * TAU / 24.0
			for dist: float in [0.6, 1.2, 2.0, 3.0]:
				var p: Vector2 = at + Vector2(cos(a), sin(a)) * dist
				var r := {"reason": "", "pos": Vector2.INF}
				FurniturePlace._eval_wall(game.build, r, kind, size, p, {})
				if r["reason"] == "" and r["pos"] != Vector2.INF:
					w.place_object(kind, r["pos"], r["rot"], true)
					return true
		return false
	for ring in range(2, 16):
		var dist := ring * 0.4
		var steps := maxi(8, ring * 6)
		for k in steps:
			var a := k * TAU / steps
			for rot: int in [0, 1]:
				var pos := FurnitureCatalog.snap(size, at + Vector2(cos(a), sin(a)) * dist, rot)
				if FurniturePlace.check(w, kind, size, pos, rot)["reason"] == "" and FurniturePlace._level_reason(game.build, FurnitureCatalog.footprint(size, pos, rot)) == "":
					w.place_object(kind, pos, rot, true)
					return true
	return false


## A bundle of supplies to try storing (the household caps apply).
func dev_storage_items() -> String:
	var got := {}
	for id in ITEMS_PACK:
		var n: int = game.state.inventory.add(id, ITEMS_PACK[id])
		if n > 0:
			got[id] = n
	return "Added %s." % FurnitureStorage.contents_text(got)


## Every container on every storey and what it holds.
func dev_containers_text() -> String:
	var lines := PackedStringArray()
	var n := 0
	for w in worlds():
		var storey := str(w.get("storey")) if w is LevelWorld else "0"
		for c in w.containers():
			n += 1
			var t: String = c["type"]
			lines.append("[%s] %s (%s) %s: %s" % [storey, c["name"], c["id"], FurnitureStorage.fill_text(t, c["items"]), FurnitureStorage.contents_text(c["items"])])
	return "%d containers\n%s" % [n, "\n".join(lines)]
