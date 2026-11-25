extends Node
## Exp 006 (D): the game side of the defences (src/defense/). The world owns
## the trenches and the rules (HouseWorld.defense, DefenseGrid); this helper
## slows and lowers the player in a dry trench (ground floor only), tells the
## player when a drawbridge is smashed down, and holds the F10 "Defences"
## tools (dev_*), which the developer menu calls on `game.defense`.

const RING := Rect2i(-2, -2, 18, 14)            ## dev moat: the cells x -2..15, y -2..11
const RING_BRIDGE := Vector2i(4, 11)            ## on the front path, south of the front door
const MOAT_SPAWN := Vector2(8.5, 13.4)          ## in the fog, south of the dev moat

var game: Node
var world: HouseWorld


func setup(g: Node) -> void:
	game = g
	world = g.world
	if world != null and world.defense != null and not world.defense.bridge_smashed.is_connected(_on_bridge_smashed):
		world.defense.bridge_smashed.connect(_on_bridge_smashed)


func grid() -> DefenseGrid:
	return world.defense if world != null else null


## After the game root's _process (which resets the player's speed scale):
## a dry trench slows the player down and lowers them into it.
func _process(delta: float) -> void:
	var g := grid()
	if g == null or game == null or game.player == null:
		return
	var levels: Variant = game.get("levels")
	if levels is Node and int((levels as Node).get("player_storey")) != 0:
		return
	var f := g.player_step(game.player, delta)
	if f < 1.0:
		game.player.speed_scale *= f


func _on_bridge_smashed(_o: WorldObject) -> void:
	if game != null and game.has_method("toast"):
		game.toast("The drawbridge was smashed down! Repair it (Repair tool) before you can raise it again.", "warn")


## A line for the developer menu.
func info() -> String:
	var g := grid()
	if g == null:
		return "No defences here."
	var spikes := 0
	for o in world.objects:
		if DefenseGrid.is_spikes(o.kind):
			spikes += 1
	var raised := 0
	var bridges := g.bridges()
	for o in bridges:
		if not o.open:
			raised += 1
	return "Trench %d m (%d under water) · drawbridges %d (%d raised) · spikes %d m" % [g.cells.size(), g.wet_count(), bridges.size(), raised, spikes]


# --- F10 "Defences" -------------------------------------------------------------------

func dev_defense_kit() -> String:
	var st: GameState = game.state
	for k in ["shovel", "hammer"]:
		if st.inventory.count(k) <= 0:
			st.inventory.add(k, 1)
	var got := {}
	for k in {"water": 12, "wood": 40, "nails": 40, "iron": 10, "scrap": 10}:
		got[k] = st.inventory.add(k, {"water": 12, "wood": 40, "nails": 40, "iron": 10, "scrap": 10}[k])
	return "Shovel and hammer, %s." % BuildPieces.cost_text(got)


## The dev moat's cells: the ring of RING, detouring outward around what
## can't be dug (the tipped bin on the east side).
func ring_cells() -> Array:
	var g := grid()
	var x0 := RING.position.x
	var y0 := RING.position.y
	var x1 := RING.end.x - 1
	var y1 := RING.end.y - 1
	var ring := []
	for x in range(x0, x1 + 1):
		ring.append(Vector2i(x, y0))
		ring.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		ring.append(Vector2i(x0, y))
		ring.append(Vector2i(x1, y))
	var out := {}
	for c in ring:
		var why := g.dig_reason(c) if not g.has(c) else ""
		if why == "":
			out[c] = true
			continue
		var n := Vector2i(-1, 0) if c.x == x0 else (Vector2i(1, 0) if c.x == x1 else (Vector2i(0, -1) if c.y == y0 else Vector2i(0, 1)))
		var t := Vector2i(n.y, n.x)
		for k in [c + n, c + n + t, c + n - t]:
			if g.has(k) or g.dig_reason(k) == "":
				out[k] = true
	return out.keys()


## Digs a ring trench around the house with a drawbridge (lowered) on the
## front path. Free and instant (dev).
func dev_moat_ring() -> String:
	var g := grid()
	if g == null:
		return "No ground floor world."
	var cells := []
	for c in ring_cells():
		if not g.has(c):
			cells.append(c)
	var ch := {}
	for c in cells:
		ch[c] = DefenseGrid.DRY
	g.apply_changes(ch)
	var msg := "Dug %d m of moat." % cells.size()
	if g.bridge_over(RING_BRIDGE) == null and g.has(RING_BRIDGE):
		var fit := g.bridge_fit(RING_BRIDGE, 1, 0)
		if fit["reason"] == "":
			var o := world.place_object("drawbridge_1", fit["pos"], fit["rot"], true)
			g.set_bridge(o, true, true)
			msg += " Drawbridge on the front path."
		else:
			msg += " No drawbridge: %s" % fit["reason"]
	return msg + " Fill it next."


## Floods every dry trench section (free, dev).
func dev_fill_moat() -> String:
	var g := grid()
	if g == null or g.cells.is_empty():
		return "No trench to fill: dig one first."
	var ch := {}
	for c in g.cells:
		if not g.is_wet(c):
			ch[c] = DefenseGrid.WET
	g.apply_changes(ch)
	return "%d m of trench filled with water." % ch.size()


## Raises every drawbridge if any is lowered, else lowers them all (dev:
## repairs a jammed one first).
func dev_toggle_bridges() -> String:
	var g := grid()
	var all := g.bridges() if g != null else []
	if all.is_empty():
		return "No drawbridges."
	var any_lowered := false
	for o in all:
		if o.open:
			any_lowered = true
	var n := 0
	for o in all:
		if any_lowered and o.hp < o.max_hp:
			o.restore()
		if g.set_bridge(o, not any_lowered) == "":
			n += 1
	return "%d drawbridge(s) %s." % [n, "raised" if any_lowered else "lowered"]


func dev_spawn_at_moat(kind := "psycho") -> String:
	var r: Variant = game.get("roster")
	if not (r is Node) or not r.has_method("spawn_type"):
		return "No enemy roster."
	r.spawn_type(kind, MOAT_SPAWN, {"facing": PI})
	return "A %s appears in the fog south of the moat." % EnemyDefs.value(kind, "name", kind)


func dev_defense_text() -> String:
	return info()
