extends "res://tests/test_case.gd"
## Exp 008 (lead): audio at the POIs. The indoor/outdoor mix follows the
## POI's own rooms (it used to test the home's footprint), an outdoor place's
## shelter counts as exposed, and the room tone falls back from a
## place-specific recording (store, clinic, library) to the house's.

const PREVIEW := "res://src/poi/poi_preview.tscn"
const AudioLink := preload("res://src/audio/game_audio.gd")


func _harness(id: String) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, false, 4242)
	add(h)
	await physics_frames(3)
	return h


func test_the_mix_follows_the_poi_rooms() -> void:
	var h: Node = await _harness("convenience")
	var w: PoiWorld = h.world
	var room: Dictionary = w.rooms()[0]
	var r: Rect2 = room["rect"]
	check_eq(AudioLink.poi_place(w, r.get_center()), "inside", "inside the store's %s" % room["id"])
	check_eq(AudioLink.poi_place(w, w.entry_point()), "outside", "outside at the entry")
	var far := Vector2(r.position.x - 3.0, r.position.y - 3.0)
	check_eq(AudioLink.poi_place(w, far), "outside", "outside behind the store")
	var f: Node = await _harness("forest")
	var fw: PoiWorld = f.world
	check_eq(AudioLink.poi_place(fw, (fw.rooms()[0]["rect"] as Rect2).get_center()), "exposed", "the woodcutter's shelter is open to the weather")


func test_room_tone_per_place_falls_back_to_the_house() -> void:
	check_eq(AudioLink.room_tone_for("home"), ["ambient/room_tone"], "home: the house's room tone")
	check_eq(AudioLink.room_tone_for("convenience")[0], "ambient/room_store", "a store asks for a store tone first")
	check_eq(AudioLink.room_tone_for("clinic")[0], "ambient/room_clinic", "the clinic asks for a clinic tone")
	check_eq(AudioLink.room_tone_for("library")[0], "ambient/room_library", "the library asks for a library tone")
	check_eq(AudioLink.room_tone_for("clinic").back(), "ambient/room_tone", "and falls back to the house's")
	var amb := Ambience.new()
	add(amb)
	await frames(1)
	var got := amb.set_room_tone(["ambient/room_clinic", "ambient/room_tone"])
	check(got == "ambient/room_clinic" or not Sfx.available("ambient/room_clinic"), "a delivered clinic tone is used")
	if not Sfx.available("ambient/room_clinic"):
		check_eq(got, "ambient/room_tone", "without one, the house's room tone")
	check_eq((amb.beds["room"] as AmbienceBed).logical, got, "the indoor bed plays it")


func test_inbox_names_route_the_place_tones() -> void:
	check_eq(AudioInbox.match_path("Room tone - Abandoned store 1" + ".wav")["name"], "ambient/room_store", "store tone")
	check_eq(AudioInbox.match_path("Room tone - Clinic" + ".wav")["name"], "ambient/room_clinic", "clinic tone")
	check_eq(AudioInbox.match_path("Room tone - Library 2" + ".wav")["name"], "ambient/room_library", "library tone")
	check_eq(AudioInbox.match_path("Room tone - House interior 1" + ".wav")["name"], "ambient/room_tone", "the house's tone is unchanged")
	check_eq(AudioInbox.match_path("Room tone - Basement 1" + ".wav")["name"], "ambient/basement_tone", "and the basement's")
