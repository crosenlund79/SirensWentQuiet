extends "res://tests/test_case.gd"
## Ambience (SPEC §7.6): loops start on entering the tree, day/night
## cross-fade, tension drone, distant noises from beyond the lot edge.


func _ambience() -> Ambience:
	Sfx.reset()
	var root := add(Node3D.new())
	Sfx.attach(root)
	var a := Ambience.new()
	root.add_child(a)
	return a


func test_loops_start_when_entering_the_tree() -> void:
	var a := _ambience()
	await frames(2)
	for id in ["wind", "night"]:
		var p := a.player(id)
		check(p != null and p.playing, "%s loop playing" % id)
		check(p != null and String(p.bus) == "Outdoor", "%s on the Outdoor bus (it sends to Ambient)" % id)
		check(p != null and (p.stream as AudioStreamOggVorbis).loop, "%s stream loops" % id)
	check(not a.player("tension").playing, "no tension by default")


func test_night_amount_crossfades_wind_and_night() -> void:
	var a := _ambience()
	await frames(1)
	for i in 20:
		a._step(0.5)
	var day := a.gains()
	check(day["wind"] > 0.99 and day["night"] < 0.01, "day: wind only (%s)" % day)
	a.set_night_amount(1.0)
	a._step(0.1)
	var mid := a.gains()
	check(mid["wind"] < 1.0 and mid["night"] > 0.0, "fading, not jumping (%s)" % mid)
	for i in 20:
		a._step(0.5)
	var night := a.gains()
	check(night["night"] > 0.99 and night["wind"] < 0.01, "night: night bed only (%s)" % night)
	check(a.player("night").volume_db > a.player("wind").volume_db + 30.0, "volumes follow")
	a.set_night_amount(0.5)
	for i in 20:
		a._step(0.5)
	var half := a.gains()
	check(absf(half["wind"] * half["wind"] + half["night"] * half["night"] - 1.0) < 0.01, "equal-power at dusk")
	a.set_night_amount(7.0)
	check_eq(a.night_amount, 1.0, "clamped")


func test_tension_drone_fades_in_and_stops() -> void:
	var a := _ambience()
	await frames(1)
	a.set_tension(1.0)
	a._step(0.2)
	check(a.player("tension").playing, "drone started")
	check((a.player("tension").stream as AudioStreamOggVorbis).loop, "drone loops")
	for i in 20:
		a._step(0.5)
	check(a.gains()["tension"] > 0.99, "full tension")
	a.set_tension(0.0)
	for i in 30:
		a._step(0.5)
	check(not a.player("tension").playing, "drone stopped after fading out")


func test_distant_noises_come_from_beyond_the_lot_edge() -> void:
	var a := _ambience()
	await frames(1)
	var outer := Ambience.LOT.grow(Ambience.DISTANT_OUTSET.y + 0.01)
	for i in 64:
		var p := a.distant_point(TAU * i / 64.0)
		var plan := Vector2(p.x, p.z)
		var nearest := Vector2(clampf(plan.x, Ambience.LOT.position.x, Ambience.LOT.end.x),
				clampf(plan.y, Ambience.LOT.position.y, Ambience.LOT.end.y))
		check(plan.distance_to(nearest) >= 1.0, "at least 1 m beyond the lot edge (%s)" % plan)
		check(outer.has_point(plan), "within the fog band (%s)" % plan)
		check(is_equal_approx(p.y, Ambience.DISTANT_HEIGHT), "height")
	var at := a.play_distant(2)
	check_eq(Sfx.active_count("ambient/distant_3"), 1, "the siren plays")
	var found := false
	for c in a.get_parent().get_node("SfxHost").get_children():
		if c is AudioStreamPlayer3D and c.playing and c.get_meta("sfx_key") == "ambient/distant":
			found = c.global_position.is_equal_approx(at) and String(c.bus) == "Outdoor"
	check(found, "positional, on the Outdoor bus (muffled indoors; it sends to Ambient), at the edge point")


func test_distant_noises_are_more_frequent_at_night() -> void:
	var a := _ambience()
	await frames(1)
	var day := a.distant_interval_range()
	check(day.x >= 20.0 and day.y <= 75.0, "day interval about 25-70 s (%s)" % day)
	a.set_night_amount(1.0)
	var night := a.distant_interval_range()
	check(night.x < day.x and night.y < day.y, "shorter at night (%s)" % night)
	check(a.next_distant_in() >= day.x and a.next_distant_in() <= day.y, "first one scheduled")
	var counts := [0, 0, 0]
	for i in 300:
		counts[a._pick_distant()] += 1
	check(counts[0] > 0 and counts[1] > 0 and counts[2] > 0, "all three noises in rotation (%s)" % [counts])


func test_timer_plays_a_distant_noise_and_reschedules() -> void:
	var a := _ambience()
	await frames(1)
	a.set_night_amount(1.0)
	a._next_distant = 0.01
	a._process(0.05)
	check_eq(Sfx.active_count("ambient/distant"), 1, "one distant noise playing")
	var r := a.distant_interval_range()
	check(a.next_distant_in() >= r.x and a.next_distant_in() <= r.y, "next one scheduled in the night range")
	a.distant_enabled = false
	a._next_distant = 0.01
	a._process(0.05)
	check(is_equal_approx(a.next_distant_in(), 0.01), "disabled: the timer holds")
