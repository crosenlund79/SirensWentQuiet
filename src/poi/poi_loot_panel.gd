class_name PoiLootPanel
extends StoragePanel
## Experiment 007 (P): agent F's StoragePanel at a POI, in two modes:
##   loot   a searched container, take-only: "Your pack" (what you took here,
##          informational) and "In the shelf" (Take 1 / Take all / Eat...)
##   cargo  the car's boot: what you carry (Put 1 / Put all) and what is in
##          the boot (Take)
## The pack limit (PoiState) caps every take, the boot's capacity every put,
## and the line under the title shows both ("Pack: 18 / 30"). Transfers go
## through FurnitureStorage on the live dictionaries (nothing duplicated or
## lost); the helper (game_poi.gd) keeps the pack's count.
## Exp 008 (L): every row shows its weight ("wt 1.5"); "Take all" becomes
## "Take 4" when only four fit and is disabled when none does; a take the
## pack stops says so (the helper's full_text). The boot has "Stow what you
## found" (everything taken at this place, as far as the boot holds).

const RULE := "What you take goes into your pack (a backpack carries more). The car's boot holds more, and comes home with you."
const RULE_HOME := "What you take goes into the household supplies, as far as their caps allow."

var mode := "loot"
var helper: Object              ## game_poi.gd: pack accounting (null: no pack, e.g. at home)
var label_text := ""


## A searched container (contents: its live items).
func open_loot(s: GameState, contents: Dictionary, title: String, h: Object) -> void:
	mode = "loot"
	helper = h
	label_text = title.to_lower()
	open(s, "loot_pile", contents, title)


## Exp 012 (L): the public way to loot anything that holds items (a corpse,
## a dropped bag...): a take-only window of the same fixed size on the live
## `contents` dictionary. `h`: the POI helper when away (the pack limit
## applies and what is taken counts in the pack), or null at home (only the
## household caps apply). Listen to `taken(id, n)` for each take and
## `closed` when it closes. Whatever doesn't fit stays in `contents`.
##   game.poi.panel.open_items(state, "Body of Ray Duncan", corpse.items, game.poi)
func open_items(s: GameState, title: String, contents: Dictionary, h: Object = null) -> void:
	open_loot(s, contents, title, h)


## The car's boot (contents: the live cargo).
func open_cargo(s: GameState, contents: Dictionary, h: Object) -> void:
	mode = "cargo"
	helper = h
	label_text = "boot"
	open(s, "loot_pile", contents, "Car (cargo)")


func _pack() -> Dictionary:
	return helper.pack if helper != null else {}


# --- the layout hooks (StoragePanel's fixed frame) --------------------------------------------

func _sub_text() -> String:
	if helper == null and mode != "cargo":
		return "Take what you can carry home."
	var sub := PoiState.pack_text(state, _pack())
	if _full():
		sub += " · full"
	if mode == "cargo":
		sub = "Boot: %s / %s  ·  %s" % [PoiState._num(PoiState.load_of(items)), PoiState._num(PoiState.CARGO_CAP), sub]
	elif helper != null and bool(helper.get("has_car")):
		sub += "  ·  Boot %s / %s (at the car)" % [PoiState._num(PoiState.load_of(helper.get("cargo"))), PoiState._num(PoiState.CARGO_CAP)]
	return sub


func _sub_color() -> Color:
	return UiTheme.WARN if _full() and mode != "cargo" else UiTheme.TEXT_DIM


func _left_heading() -> String:
	if mode == "cargo":
		return "You carry"
	return "Your pack" if helper != null else "Taken"


func _right_heading() -> String:
	return "In the boot" if mode == "cargo" else "In the %s" % label_text


func _fill_left(list: VBoxContainer) -> bool:
	var any := false
	for id in Items.DEFS:
		if mode == "cargo":
			if state.inventory.count(id) > 0:
				list.add_child(_row(id, state.inventory.count(id), true))
				any = true
		else:
			var k := mini(int(_pack().get(id, 0)), state.inventory.count(id))
			if k > 0:
				var r := ItemRows.row(id, k, {"prefix": "Pack_", "status": "wt %s" % PoiState._num(PoiState.weight_of(id) * k)})
				ItemRows.track(r, id, _details)
				list.add_child(r)
				any = true
	return any


func _left_empty_text() -> String:
	return "You carry nothing." if mode == "cargo" else "Nothing yet."


func _right_empty_text() -> String:
	return "Empty." if mode == "cargo" else "Nothing here."


func _rule_text() -> String:
	return RULE if helper != null or mode == "cargo" else RULE_HOME


func _buttons() -> Array:
	var buttons := super()
	if mode == "cargo":                # Exp 008 (L): the quick way into the boot
		var stow_b := UiTheme.make_button("Stow what you found")
		stow_b.name = "StowFound"
		stow_b.disabled = _carried_found().is_empty()
		stow_b.pressed.connect(stow_found)
		buttons.push_front(stow_b)
	return buttons


## Exp 008 (L): a row with its weight; taking is capped by the pack's room.
## Exp 012 (L): one line, the weight as its status.
func _row_opts(id: String, n: int, carried: bool) -> Dictionary:
	var o := super(id, n, carried)
	o["status"] = "wt %s" % PoiState._num(PoiState.weight_of(id) * n)
	o["status_name"] = "Weight"
	o["status_color"] = UiTheme.TEXT_FAINT
	if not carried:
		var fit := mini(_room(id), state.inventory.space_for(id))
		for a in o["actions"]:
			if str(a[3]) in ["Take1", "Takeall"]:
				a[2] = fit <= 0
			if str(a[3]) == "Takeall" and fit > 0 and fit < n:
				a[0] = "Take %d" % fit
		if fit <= 0:
			o["status"] = "no room"
			o["status_color"] = UiTheme.WARN
	elif mode == "cargo":
		var room := PoiState.room_for(id, PoiState.load_of(items), PoiState.CARGO_CAP)
		for a in o["actions"]:
			if str(a[3]) in ["Put1", "Putall"]:
				a[2] = room <= 0
	return o


## Room in the pack for `id` (cargo mode: taking out of the boot counts too).
func _room(id: String) -> int:
	if helper == null and mode != "cargo":
		return 1 << 20                  # Exp 012 (L): no pack at home, only the household caps
	return PoiState.room_for(id, PoiState.pack_load(state, _pack()), PoiState.pack_cap(state))


## What was taken here and is still carried (what counts in the pack).
func _carried_found() -> Dictionary:
	var out := {}
	if state == null:
		return out
	var p := _pack()
	for id in p:
		var k := mini(int(p[id]), state.inventory.count(id))
		if k > 0:
			out[id] = k
	return out


func _full() -> bool:
	return helper != null and helper.has_method("pack_full") and bool(helper.pack_full())


func _full_text() -> String:
	if helper != null and helper.has_method("full_text"):
		return str(helper.full_text())
	return "Your pack is full (%s)." % PoiState.pack_text(state, _pack())


## Takes up to n of `id` (as far as the pack and the household caps allow).
func take(id: String, n: int) -> int:
	var room := _room(id)
	if room <= 0:
		_say(_full_text(), false)
		_render()
		return 0
	var k := super.take(id, mini(n, room))
	if k > 0 and helper != null:
		helper.pack_add(id, k)
		if k < n and k == room:
			_say("Took %d %s. %s" % [k, Items.name_of(id).to_lower(), _full_text()], false)
		_render()
	return k


func take_everything() -> Dictionary:
	var got := {}
	for id in items.keys():
		var room := _room(id)
		var k := FurnitureStorage.take(state, items, id, mini(int(items[id]), room))
		if k > 0:
			got[id] = k
			taken.emit(id, k)
			if helper != null:
				helper.pack_add(id, k)
	if got.is_empty():
		_say((_full_text() if _full() else "Nothing taken: no room for it.") if not items.is_empty() else "It's empty.", false)
	elif not items.is_empty():
		_say("Took %s. %s" % [FurnitureStorage.contents_text(got), _full_text() if _full() else "Some didn't fit."], false)
		Sfx.ui("ui/click")
	else:
		_say("Took %s." % FurnitureStorage.contents_text(got), true)
		Sfx.ui("ui/click")
	_render()
	return got


## Cargo mode: stows up to n of `id` in the boot (as far as it has room).
func put(id: String, n: int) -> int:
	if mode != "cargo":
		return 0
	var room := PoiState.room_for(id, PoiState.load_of(items), PoiState.CARGO_CAP)
	if room <= 0:
		_say("The boot is full.", false)
		_render()
		return 0
	var k := FurnitureStorage.store(state, items, "loot_pile", id, mini(n, room))
	if k > 0:
		_say("Stowed %d %s in the boot." % [k, Items.name_of(id).to_lower()], true)
		Sfx.ui("ui/click")
		if helper != null:
			helper.pack_remove(id, k)
	_render()
	return k


## Exp 008 (L), cargo mode: everything taken at this place (still carried)
## into the boot, as far as it holds. Returns what went in.
func stow_found() -> Dictionary:
	var got := {}
	if mode != "cargo":
		return got
	var found := _carried_found()
	for id in Items.DEFS:
		if not found.has(id):
			continue
		var room := PoiState.room_for(id, PoiState.load_of(items), PoiState.CARGO_CAP)
		var k := FurnitureStorage.store(state, items, "loot_pile", id, mini(int(found[id]), room))
		if k > 0:
			got[id] = k
			if helper != null:
				helper.pack_remove(id, k)
	if got.is_empty():
		_say("The boot is full." if not found.is_empty() else "You've found nothing here yet.", false)
	else:
		var rest := not _carried_found().is_empty()
		_say("Stowed %s in the boot.%s" % [FurnitureStorage.contents_text(got), " The boot is full." if rest else ""], not rest)
		Sfx.ui("ui/click")
	_render()
	return got
