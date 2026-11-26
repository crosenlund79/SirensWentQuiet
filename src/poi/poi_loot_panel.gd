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

var mode := "loot"
var helper: Object              ## game_poi.gd: pack accounting
var label_text := ""


## A searched container (contents: its live items).
func open_loot(s: GameState, contents: Dictionary, title: String, h: Object) -> void:
	mode = "loot"
	helper = h
	label_text = title.to_lower()
	open(s, "loot_pile", contents, title)


## The car's boot (contents: the live cargo).
func open_cargo(s: GameState, contents: Dictionary, h: Object) -> void:
	mode = "cargo"
	helper = h
	label_text = "boot"
	open(s, "loot_pile", contents, "Car (cargo)")


func _pack() -> Dictionary:
	return helper.pack if helper != null else {}


func _render() -> void:
	if state == null:
		return
	var had_focus := is_open
	var box := _begin(title_text, WIDTH)
	var sub := PoiState.pack_text(state, _pack())
	var full := _full()
	if full:
		sub += " · full"
	if mode == "cargo":
		sub = "Boot: %s / %s  ·  %s" % [PoiState._num(PoiState.load_of(items)), PoiState._num(PoiState.CARGO_CAP), sub]
	elif helper != null and bool(helper.get("has_car")):
		sub += "  ·  Boot %s / %s (at the car)" % [PoiState._num(PoiState.load_of(helper.get("cargo"))), PoiState._num(PoiState.CARGO_CAP)]
	var subl := UiTheme.make_label(sub, UiTheme.FONT_BODY, UiTheme.WARN if full and mode != "cargo" else UiTheme.TEXT_DIM)
	subl.name = "Fill"
	box.add_child(subl)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	box.add_child(cols)
	var left := _column(cols, "You carry" if mode == "cargo" else "Your pack")
	var right := _column(cols, "In the boot" if mode == "cargo" else "In the %s" % label_text)
	var any_left := false
	for id in Items.DEFS:
		if mode == "cargo":
			if state.inventory.count(id) > 0:
				left.add_child(_row(id, state.inventory.count(id), true))
				any_left = true
		else:
			var k := mini(int(_pack().get(id, 0)), state.inventory.count(id))
			if k > 0:
				var l := UiTheme.make_label("%s  ×%d" % [Items.name_of(id), k], UiTheme.FONT_BODY)
				l.name = "Pack_" + id
				left.add_child(l)
				any_left = true
	if not any_left:
		left.add_child(UiTheme.make_caption("Nothing yet." if mode != "cargo" else "You carry nothing.", 420, UiTheme.TEXT_FAINT))
	var any_right := false
	for id in Items.DEFS:
		if int(items.get(id, 0)) > 0:
			right.add_child(_row(id, int(items[id]), false))
			any_right = true
	if not any_right:
		right.add_child(UiTheme.make_caption("Empty." if mode == "cargo" else "Nothing here.", 420, UiTheme.TEXT_FAINT))
	box.add_child(UiTheme.make_spacer(2))
	box.add_child(UiTheme.make_caption(RULE, WIDTH - 60, UiTheme.TEXT_FAINT))
	_feedback = UiTheme.make_label(last_text, UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size.y = 22
	box.add_child(_feedback)
	var all_b := UiTheme.make_button("Take everything")
	all_b.name = "TakeAll"
	all_b.disabled = items.is_empty()
	all_b.pressed.connect(take_everything)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(_close_and_emit)
	var buttons := [all_b, close_b]
	if mode == "cargo":                # Exp 008 (L): the quick way into the boot
		var stow_b := UiTheme.make_button("Stow what you found")
		stow_b.name = "StowFound"
		stow_b.disabled = _carried_found().is_empty()
		stow_b.pressed.connect(stow_found)
		buttons.push_front(stow_b)
	box.add_child(_footer("E / Esc", "Close", buttons))
	if had_focus:
		_root.modulate.a = 1.0
		_focus()


## Exp 008 (L): a row with its weight; taking is capped by the pack's room.
func _row(id: String, n: int, carried: bool) -> Control:
	var row: Control = super(id, n, carried)
	var wt := UiTheme.make_label("wt %s" % PoiState._num(PoiState.weight_of(id) * n), UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT)
	wt.name = "Weight"
	wt.custom_minimum_size.x = 64
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wt.tooltip_text = "%s each" % PoiState._num(PoiState.weight_of(id))
	row.add_child(wt)
	row.move_child(wt, row.get_node("Count").get_index() + 1)
	if not carried:
		if not Items.is_consumable(id):       # keeps the columns lined up with the rows that have Eat / Drink
			var gap := Control.new()
			gap.name = "NoVerb"
			gap.custom_minimum_size.x = 76
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
			row.move_child(gap, row.get_node("Take1").get_index())
		var fit := mini(_room(id), state.inventory.space_for(id))
		var one: Button = row.get_node_or_null("Take1")
		var all: Button = row.get_node_or_null("Takeall")
		if one != null:
			one.disabled = fit <= 0
		if all != null:
			all.disabled = fit <= 0
			if fit > 0 and fit < n:
				all.text = "Take %d" % fit
	elif mode == "cargo":
		var room := PoiState.room_for(id, PoiState.load_of(items), PoiState.CARGO_CAP)
		for b in ["Put1", "Putall"]:
			var btn: Button = row.get_node_or_null(b)
			if btn != null:
				btn.disabled = room <= 0
	return row


## Room in the pack for `id` (cargo mode: taking out of the boot counts too).
func _room(id: String) -> int:
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
	var room := PoiState.room_for(id, PoiState.pack_load(state, _pack()), PoiState.pack_cap(state))
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
		var room := PoiState.room_for(id, PoiState.pack_load(state, _pack()), PoiState.pack_cap(state))
		var k := FurnitureStorage.take(state, items, id, mini(int(items[id]), room))
		if k > 0:
			got[id] = k
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
