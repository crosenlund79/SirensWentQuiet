class_name Sfx
extends RefCounted
## Sound playback (SPEC §7.6). Owner: A. Static, no Autoload.
##
##   Sfx.attach(self)                        # once per scene, from its root
##   Sfx.play("impact/wood", hit_position)   # Vector3 (or plan Vector2) = positional
##   Sfx.play("player/footstep")             # a group name picks a random variant
##   Sfx.ui("ui/click")                      # UI bus, survives scene changes
##   Sfx.music("music/menu") ; Sfx.music("") # cross-fades; "" fades out
##
## Streams come from AssetResolver.get_audio, so creator files in
## custom/audio/ replace the templates (docs/experiment-002/audio.md).
## Experiment 005 (A): the audio inbox (AudioInbox) sits between the two:
## custom/ > the inbox > the template, per name (see clip()). Inbox clips can
## start late and stop early (silence trimmed, footsteps sliced) and carry a
## normalising gain. docs/experiment-005/AUDIO.md.
## Players are pooled. Flat and positional players live under the attached
## scene root and go away with the scene; UI and music players live under the
## SceneTree root so a click or a cross-fade outlives a scene change. Every
## name has a bus, base volume, pitch spread, cooldown and instance cap (DEFS)
## so rapid repeats don't machine-gun. Unknown names warn once and play nothing.

const FLAT_MAX := 16
const POSITIONAL_MAX := 32
const UI_MAX := 6
const MUSIC_MAX := 3
const MUSIC_FADE := 2.0          ## seconds for a music cross-fade
const LISTENER_HEIGHT := 1.0     ## the listener sits where the camera looks, at this height
const NEAR := {"unit": 9.0, "max_distance": 40.0, "cutoff": 7000.0, "filter_db": -10.0}
const FAR := {"unit": 14.0, "max_distance": 60.0, "cutoff": 2200.0, "filter_db": -20.0}

## Variant groups: the group name plays <group>_1..N at random, never the same
## one twice in a row. Variants share the group's DEFS entry and cooldown.
const GROUPS := {"player/footstep": 4, "enemy/moan": 2, "ambient/distant": 3}

const DEFAULT := {"bus": "SFX", "vol": 0.0, "pitch": 0.0, "cd": 0.05, "max": 4, "pos": true,
		"steal": true, "far": false, "loop": false, "tpl": true}
const CLIP_FADE := 0.03          ## Exp 005 (A): fade-out when a clip stops early

## Per logical name. bus: SFX | UI | Ambient | Music. vol: base dB. pitch:
## random +/- fraction. cd: seconds before the name plays again. max:
## simultaneous instances (steal: restart the oldest instead of skipping).
## pos: positional when given a position. far: stronger air absorption.
## loop: plays only through Sfx.music or Ambience.
## tpl: false for names with no generated template (Exp 005: the audio inbox
## fills them; they stay silent until a file maps to them).
const DEFS := {
	"player/footstep": {"pitch": 0.07, "cd": 0.12, "max": 2, "steal": false},
	"player/hurt": {"pitch": 0.06, "cd": 0.35, "max": 1, "pos": false},
	"player/eat": {"pitch": 0.03, "cd": 0.5, "max": 1, "pos": false},
	"player/drink": {"pitch": 0.03, "cd": 0.5, "max": 1, "pos": false},
	"player/bandage": {"pitch": 0.03, "cd": 0.5, "max": 1, "pos": false},
	"player/sleep": {"cd": 1.0, "max": 1, "pos": false},
	"player/death": {"cd": 2.0, "max": 1, "pos": false},
	"weapon/handgun_fire": {"pitch": 0.03, "cd": 0.05, "max": 4},
	"weapon/dry_fire": {"pitch": 0.04, "cd": 0.12, "max": 1},
	# Experiment 003: the shotgun, reloading and switching (WeaponHandler plays these).
	"weapon/shotgun_fire": {"pitch": 0.03, "cd": 0.1, "max": 3},
	"weapon/reload": {"pitch": 0.03, "cd": 0.3, "max": 1},
	"weapon/shotgun_reload": {"pitch": 0.03, "cd": 0.3, "max": 1, "tpl": false},   # Exp 006 (R): silent until a file maps here; the shotgun falls back to weapon/reload
	"weapon/reload_done": {"pitch": 0.03, "cd": 0.1, "max": 1},
	"weapon/shell_load": {"pitch": 0.05, "cd": 0.08, "max": 2},
	"weapon/switch": {"pitch": 0.04, "cd": 0.15, "max": 1},
	"impact/wood": {"pitch": 0.1, "cd": 0.03, "max": 4},
	"impact/plaster": {"pitch": 0.1, "cd": 0.03, "max": 4},
	"impact/glass": {"pitch": 0.08, "cd": 0.05, "max": 3},
	"impact/metal": {"pitch": 0.08, "cd": 0.04, "max": 3},
	"impact/flesh": {"pitch": 0.1, "cd": 0.03, "max": 3},
	"impact/ground": {"pitch": 0.1, "cd": 0.03, "max": 4},
	"build/place": {"pitch": 0.06, "cd": 0.08, "max": 2},
	"build/hammer": {"pitch": 0.05, "cd": 0.25, "max": 2},
	"build/demolish": {"pitch": 0.04, "cd": 0.2, "max": 2},
	"build/invalid": {"cd": 0.25, "max": 1, "pos": false},
	"build/upgrade": {"pitch": 0.04, "cd": 0.2, "max": 2},
	"door/open": {"pitch": 0.05, "cd": 0.15, "max": 2},
	"door/close": {"pitch": 0.05, "cd": 0.15, "max": 2},
	"door/bash": {"pitch": 0.08, "cd": 0.12, "max": 3},
	"structure/break": {"pitch": 0.06, "cd": 0.1, "max": 3},
	"structure/crumble": {"pitch": 0.08, "cd": 0.08, "max": 3},
	"enemy/moan": {"vol": -2.0, "pitch": 0.08, "cd": 1.2, "max": 3, "steal": false},
	"enemy/attack": {"pitch": 0.08, "cd": 0.2, "max": 3},
	"enemy/hit": {"pitch": 0.08, "cd": 0.1, "max": 3},
	"enemy/death": {"pitch": 0.06, "cd": 0.1, "max": 3},
	# Experiment 003: the bomber (positional; the fuse beep repeats faster and faster).
	"enemy/bomber_fuse": {"cd": 0.15, "max": 2, "steal": false},
	"enemy/bomber_blast": {"pitch": 0.04, "cd": 0.3, "max": 2, "far": true},
	"structure/blast": {"pitch": 0.05, "cd": 0.2, "max": 2, "far": true},
	"ambient/wind_day": {"bus": "Ambient", "pos": false, "loop": true},
	"ambient/night": {"bus": "Ambient", "pos": false, "loop": true},
	"ambient/tension": {"bus": "Ambient", "pos": false, "loop": true},
	"ambient/distant": {"bus": "Outdoor", "pitch": 0.05, "cd": 8.0, "max": 1, "far": true, "steal": false},   # Exp 005: muffled indoors
	"ui/click": {"bus": "UI", "pitch": 0.02, "cd": 0.03, "max": 2, "pos": false},
	"ui/hover": {"bus": "UI", "vol": -2.0, "pitch": 0.03, "cd": 0.04, "max": 1, "pos": false},
	"ui/open": {"bus": "UI", "cd": 0.08, "max": 1, "pos": false},
	"ui/close": {"bus": "UI", "cd": 0.08, "max": 1, "pos": false},
	"ui/error": {"bus": "UI", "cd": 0.25, "max": 1, "pos": false},
	"stinger/invasion": {"bus": "Music", "cd": 5.0, "max": 1, "pos": false, "steal": false},
	"stinger/dawn": {"bus": "Music", "cd": 5.0, "max": 1, "pos": false, "steal": false},
	"music/menu": {"bus": "Music", "pos": false, "loop": true},
	# Experiment 005 (A): names the audio inbox fills (docs/experiment-005/AUDIO.md).
	"player/step_snow": {"pitch": 0.06, "cd": 0.12, "max": 3, "pos": false, "tpl": false},
	"player/step_wood": {"pitch": 0.06, "cd": 0.12, "max": 3, "pos": false, "tpl": false},
	"player/step_cement": {"pitch": 0.06, "cd": 0.12, "max": 3, "pos": false, "tpl": false},
	"enemy/step_snow": {"pitch": 0.08, "cd": 0.05, "max": 4, "steal": false, "tpl": false},
	"enemy/step_wood": {"pitch": 0.08, "cd": 0.05, "max": 4, "steal": false, "tpl": false},
	"home/fireplace_light": {"pitch": 0.04, "cd": 0.5, "max": 1, "tpl": false},
	"home/fireplace_out": {"pitch": 0.04, "cd": 0.5, "max": 1, "tpl": false},
	"ambient/owl": {"bus": "Outdoor", "pitch": 0.04, "cd": 6.0, "max": 1, "far": true, "steal": false, "tpl": false},
	"ambient/wolf": {"bus": "Outdoor", "pitch": 0.03, "cd": 6.0, "max": 1, "far": true, "steal": false, "tpl": false},
	"ambient/house_creak": {"bus": "Ambient", "pitch": 0.03, "cd": 6.0, "max": 1, "steal": false, "tpl": false},
	"ambient/forest": {"bus": "Outdoor", "pos": false, "loop": true, "tpl": false},
	"ambient/fireplace": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},
	"ambient/room_tone": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},
	"ambient/basement_tone": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},
	"ambient/room_store": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},      # Exp 008: per-place room tones
	"ambient/room_clinic": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},
	"ambient/room_library": {"bus": "Ambient", "pos": false, "loop": true, "tpl": false},
	"voice/eli_new_game": {"bus": "Voice", "pos": false, "cd": 1.0, "max": 1, "steal": false, "tpl": false},
	"voice/eli_continue": {"bus": "Voice", "pos": false, "cd": 1.0, "max": 1, "steal": false, "tpl": false},
	"music/dawn": {"bus": "Music", "vol": -8.0, "pos": false, "loop": true, "tpl": false},
	# Played through play_first with the old sound as the fallback (one-line hooks).
	"home/light_switch": {"pitch": 0.05, "cd": 0.1, "max": 1, "pos": false, "tpl": false},
	"car/start": {"cd": 1.0, "max": 1, "pos": false, "tpl": false},
	"build/dig": {"pitch": 0.06, "cd": 0.2, "max": 2, "tpl": false},
	# Exp 007: played through play_first when the audio inbox provides them
	# (the code falls back to existing sounds otherwise).
	"build/drill": {"pitch": 0.05, "cd": 0.3, "max": 1, "tpl": false},
	"poi/search": {"pitch": 0.08, "cd": 0.3, "max": 2, "tpl": false},
	"poi/chop": {"pitch": 0.08, "cd": 0.2, "max": 2, "tpl": false},
	"poi/force": {"pitch": 0.05, "cd": 0.4, "max": 1, "tpl": false},
	"poi/pickup": {"pitch": 0.08, "cd": 0.1, "max": 2, "pos": false, "tpl": false},
	"security/alarm": {"cd": 2.0, "max": 2, "far": true, "tpl": false},
	"security/sensor_beep": {"pitch": 0.03, "cd": 0.5, "max": 2, "tpl": false},
	"security/turret_reload": {"pitch": 0.04, "cd": 0.3, "max": 2, "tpl": false},
}

## The scene host gets an AudioListener3D that follows the point the current
## camera looks at (a top-down camera is far from the action). It never takes
## over from another current listener. Set false before attach() to disable.
static var auto_listener := true
## Counters for tests and the developer menu.
static var stats := {"played": 0, "skipped": 0, "stolen": 0}

static var _root_id := 0
static var _host_id := 0
static var _persist_id := 0
static var _music := ""
static var _last := {}
static var _last_variant := {}
static var _warned := {}
static var _defs := {}
static var _rng := RandomNumberGenerator.new()
static var _custom := {}         ## Exp 005: "<override root>|<key>" -> any custom/ file for the name


## Players for play() are created under `root` (the scene root). Call again
## after a scene change; null detaches (sounds then fall back to the
## SceneTree root with a warning).
static func attach(root: Node) -> void:
	var valid := root != null and is_instance_valid(root)
	_root_id = root.get_instance_id() if valid else 0
	if valid:
		AudioMix.ensure_buses()          # Exp 005 (A): Outdoor and Voice buses
	var old := _node(_host_id)
	if old != null and (not valid or old.get_parent() != root):
		old.queue_free()
		_host_id = 0
	_warned.erase("#root")


## Plays a one-shot. `at`: Vector3 (world) or Vector2 (plan x, y) makes it
## positional for names marked pos; null plays it flat.
static func play(name: String, at: Variant = null, volume_db := 0.0) -> void:
	var key := key_of(name)
	if key == "":
		_warn_once(name, "Sfx: unknown sound '%s'" % name)
		return
	var def := _def(key)
	if def["loop"]:
		_warn_once(name, "Sfx: '%s' is a loop; use Sfx.music or Ambience" % name)
		return
	if def["bus"] == "UI":
		_play_ui(name, key, def, volume_db)
		return
	if not _cooldown_ok(key, def):
		return
	var positional: bool = def["pos"] and (at is Vector3 or at is Vector2)
	var host := _scene_host()
	if host == null or not host.is_inside_tree():
		return
	var player := _take(host, "P" if positional else "F", key, def, POSITIONAL_MAX if positional else FLAT_MAX)
	if player == null:
		stats["skipped"] += 1
		return
	var c := _clip(name, key)
	if c.is_empty():
		return
	_start(player, c["stream"], key, def, volume_db + float(c["db"]))
	if positional:
		_place(player as AudioStreamPlayer3D, at, def["far"])
	player.play(float(c["from"]))
	_stop_at(player, c)
	_last[key] = Time.get_ticks_msec()
	stats["played"] += 1


## Exp 005 (A): plays the first of `names` that has a file (a new recorded
## sound, then the old one as the fallback). Returns the name played or "".
static func play_first(names: Array, at: Variant = null, volume_db := 0.0) -> String:
	for n in names:
		if available(n):
			play(n, at, volume_db)
			return n
	return ""


## Plays on the UI bus, flat, under the SceneTree root (works in menus and
## while the tree is paused).
static func ui(name: String) -> void:
	var key := key_of(name)
	if key == "":
		_warn_once(name, "Sfx: unknown sound '%s'" % name)
		return
	var def := _def(key)
	if def["loop"]:
		_warn_once(name, "Sfx: '%s' is a loop; use Sfx.music or Ambience" % name)
		return
	_play_ui(name, key, def, 0.0)


## Cross-fades to the looping track `name` on the Music bus; "" fades out.
## Asking for the track that is already playing does nothing.
static func music(name: String) -> void:
	if name == _music:
		return
	var key := key_of(name)
	if name != "" and (key == "" or not _def(key)["loop"] or _def(key)["bus"] != "Music"):
		_warn_once(name, "Sfx: '%s' is not a music track" % name)
		return
	var host := _persistent_host()
	if host == null or not host.is_inside_tree():
		return
	var c := _clip(name, key) if name != "" else {}
	if name != "" and c.is_empty():
		_warn_once("#nofile:" + name, "Sfx: no file for the track '%s'" % name)
		return
	_music = name
	for p in host.get_children():
		if p.get_meta("sfx_kind", "") == "M" and p.playing:
			_fade(p, 0.0, true)
	if name == "":
		return
	var player := _music_player(host)
	_start(player, AudioInbox.looped(c["stream"]), key, _def(key), float(c["db"]))
	player.volume_linear = 0.0
	player.play(float(c["from"]))
	_fade(player, db_to_linear(float(_def(key)["vol"]) + float(c["db"])), false)
	stats["played"] += 1


## Every logical sound with a template file, sorted (variants listed individually).
static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in DEFS:
		if _def(k)["tpl"]:
			out.append_array(variants(k))
	out.sort()
	return out


## Exp 005 (A): every logical name, with or without a file (the F10 list).
static func all_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in DEFS:
		out.append_array(variants(k))
	out.sort()
	return out


## Exp 005 (A): what plays for `name` (a logical name or a group variant):
## {"stream", "from", "to", "db", "source"}; `to` 0 plays to the end, `db`
## is added to the volume, source is "custom", "inbox" or "template".
## custom/ wins for a name when any of its files has an override there, then
## the audio inbox (the name's own pool, else its group's, else an alias),
## then the generated template. {} when there is nothing to play.
static func clip(name: String) -> Dictionary:
	var key := key_of(name)
	return _clip(name, key) if key != "" else {}


## Exp 005 (A): true when `name` has something to play (no random pick).
static func available(name: String) -> bool:
	var key := key_of(name)
	if key == "":
		return false
	if _has_custom(key) or _def(key)["tpl"]:
		return true
	return AudioInbox.pool_name(name) != "" or AudioInbox.pool_name(key) != ""


## Exp 005 (A): where `name` plays from now: "custom", "inbox", "template" or "".
static func source_of(name: String) -> String:
	var key := key_of(name)
	if key == "":
		return ""
	if _has_custom(key):
		return "custom"
	if AudioInbox.pool_name(name) != "" or AudioInbox.pool_name(key) != "":
		return "inbox"
	return "template" if _def(key)["tpl"] else ""


# ---------------------------------------------------------------- additive helpers

## The DEFS key for a name: itself, or its group for "<group>_<n>"; "" if unknown.
static func key_of(name: String) -> String:
	if DEFS.has(name):
		return name
	var cut := name.rfind("_")
	if cut > 0:
		var group := name.substr(0, cut)
		var index := name.substr(cut + 1)
		if GROUPS.has(group) and index.is_valid_int() and int(index) >= 1 and int(index) <= int(GROUPS[group]):
			return group
	return ""


static func has(name: String) -> bool:
	return key_of(name) != ""


static func is_loop(name: String) -> bool:
	var key := key_of(name)
	return key != "" and bool(_def(key)["loop"])


## The files a name can play: a group's variants, or the name itself.
static func variants(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	if GROUPS.has(name):
		for i in range(1, int(GROUPS[name]) + 1):
			out.append("%s_%d" % [name, i])
	elif has(name):
		out.append(name)
	return out


## How many instances of a name (or its group) are playing right now.
static func active_count(name: String) -> int:
	var key := key_of(name)
	var n := 0
	for host in [_node(_host_id), _node(_persist_id)]:
		if host == null:
			continue
		for c in host.get_children():
			if c.has_meta("sfx_kind") and c.get_meta("sfx_key", "") == key and c.playing:
				n += 1
	return n


static func current_music() -> String:
	return _music


## Tests: detach, stop the music at once, forget cooldowns, warnings and counters.
static func reset() -> void:
	attach(null)
	var host := _node(_persist_id)
	if host != null:
		for c in host.get_children():
			if c.get_meta("sfx_kind", "") == "M":
				if c.has_meta("sfx_tween"):
					var tw: Tween = c.get_meta("sfx_tween")
					if tw != null and tw.is_valid():
						tw.kill()
				c.stop()
	_music = ""
	_last.clear()
	_last_variant.clear()
	_warned.clear()
	_custom.clear()
	stats = {"played": 0, "skipped": 0, "stolen": 0}


# ---------------------------------------------------------------- internals

static func _def(key: String) -> Dictionary:
	if not _defs.has(key):
		var d: Dictionary = DEFAULT.duplicate()
		d.merge(DEFS[key], true)
		_defs[key] = d
	return _defs[key]


static func _node(id: int) -> Node:
	if id == 0:
		return null
	var o := instance_from_id(id)
	return o as Node if is_instance_valid(o) else null


static func _warn_once(id: String, text: String) -> void:
	if not _warned.has(id):
		_warned[id] = true
		push_warning(text)


static func _cooldown_ok(key: String, def: Dictionary) -> bool:
	var now := Time.get_ticks_msec()
	if _last.has(key) and now - int(_last[key]) < int(float(def["cd"]) * 1000.0):
		stats["skipped"] += 1
		return false
	return true


static func _variant(name: String, key: String) -> String:
	if name != key or not GROUPS.has(key):
		return name
	var count := int(GROUPS[key])
	var i := _rng.randi_range(1, count)
	if count > 1 and i == int(_last_variant.get(key, 0)):
		i = i % count + 1
	_last_variant[key] = i
	return "%s_%d" % [key, i]


## Exp 005 (A): see clip().
static func _clip(name: String, key: String) -> Dictionary:
	if not _has_custom(key):
		var c := AudioInbox.clip(name)
		if c.is_empty() and name != key:
			c = AudioInbox.clip(key)
		if not c.is_empty():
			return c
	var variant := _variant(name, key)
	var custom := _custom_file(variant)
	if not custom and not _def(key)["tpl"]:
		return {}
	var s := AssetResolver.get_audio(variant)
	if s == null:
		return {}
	return {"stream": s, "from": 0.0, "to": 0.0, "db": 0.0, "source": "custom" if custom else "template"}


## Any creator file in custom/audio/ for `key` or one of its group's variants.
static func _has_custom(key: String) -> bool:
	var ck := AssetResolver.override_root() + "|" + key
	if not _custom.has(ck):
		var found := false
		for v in variants(key):
			if _custom_file(v):
				found = true
				break
		_custom[ck] = found
	return _custom[ck]


static func _custom_file(logical: String) -> bool:
	for ext in AssetResolver.audio_override_formats():
		if FileAccess.file_exists(AssetResolver.audio_override_path(logical, ext)):
			return true
	return false


## Stops a clip that ends before its file does (a trimmed export, one sliced
## footstep), with a short fade so it doesn't click.
static func _stop_at(p: Node, c: Dictionary) -> void:
	var from := float(c.get("from", 0.0))
	var to := float(c.get("to", 0.0))
	if to <= from or not p.is_inside_tree():
		return
	var dur := (to - from) / maxf(float(p.get("pitch_scale")), 0.01)
	var fade := minf(CLIP_FADE, dur * 0.3)
	var tw := p.create_tween()
	tw.tween_interval(maxf(dur - fade, 0.0))
	tw.tween_property(p, "volume_db", float(p.get("volume_db")) - 40.0, fade)
	tw.tween_callback(p.stop)
	p.set_meta("sfx_tween", tw)


static func _tree_root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


static func _make_host(host_name: String) -> Node:
	var host := Node.new()
	host.name = host_name
	host.process_mode = Node.PROCESS_MODE_ALWAYS  # e.g. eating from the paused inventory
	return host


static func _scene_host() -> Node:
	var host := _node(_host_id)
	if host != null and host.is_inside_tree() and not host.is_queued_for_deletion():
		return host
	var root := _node(_root_id)
	if root == null or not root.is_inside_tree() or root.is_queued_for_deletion():
		root = _tree_root()
		if root == null:
			_warn_once("#noroot", "Sfx: no SceneTree; sound disabled")
			return null
		_warn_once("#root", "Sfx: no scene root attached (call Sfx.attach); using the SceneTree root")
	host = _make_host("SfxHost")
	if auto_listener:
		host.add_child(_Listener.new())
	root.add_child(host)
	_host_id = host.get_instance_id()
	return host


static func _persistent_host() -> Node:
	var host := _node(_persist_id)
	if host != null and host.is_inside_tree() and not host.is_queued_for_deletion():
		return host
	var root := _tree_root()
	if root == null:
		return null
	host = _make_host("SfxPersistent")
	root.add_child(host)
	_persist_id = host.get_instance_id()
	return host


static func _play_ui(name: String, key: String, def: Dictionary, volume_db: float) -> void:
	if not _cooldown_ok(key, def):
		return
	var host := _persistent_host()
	if host == null or not host.is_inside_tree():
		return
	var player := _take(host, "U", key, def, UI_MAX)
	if player == null:
		stats["skipped"] += 1
		return
	var c := _clip(name, key)
	if c.is_empty():
		return
	_start(player, c["stream"], key, def, volume_db + float(c["db"]))
	player.bus = _bus("UI")
	player.play(float(c["from"]))
	_stop_at(player, c)
	_last[key] = Time.get_ticks_msec()
	stats["played"] += 1


static func _new_player(host: Node, kind: String) -> Node:
	var p: Node
	if kind == "P":
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.max_db = 3.0
		p3.panning_strength = 0.8
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.set_meta("sfx_kind", kind)
	p.set_meta("sfx_key", "")
	p.set_meta("sfx_t", 0)
	host.add_child(p)
	return p


## A free player of `kind`, one to steal, or null (the name's cap is reached
## and it doesn't steal).
static func _take(host: Node, kind: String, key: String, def: Dictionary, cap: int) -> Node:
	var free_player: Node = null
	var oldest: Node = null
	var oldest_same: Node = null
	var same := 0
	var count := 0
	for c in host.get_children():
		if c.get_meta("sfx_kind", "") != kind:
			continue
		count += 1
		if not c.playing:
			if free_player == null:
				free_player = c
			continue
		var t: int = c.get_meta("sfx_t", 0)
		if oldest == null or t < int(oldest.get_meta("sfx_t", 0)):
			oldest = c
		if c.get_meta("sfx_key", "") == key:
			same += 1
			if oldest_same == null or t < int(oldest_same.get_meta("sfx_t", 0)):
				oldest_same = c
	if same >= int(def["max"]):
		if not def["steal"]:
			return null
		stats["stolen"] += 1
		return oldest_same
	if free_player != null:
		return free_player
	if count < cap:
		return _new_player(host, kind)
	stats["stolen"] += 1
	return oldest


static func _music_player(host: Node) -> AudioStreamPlayer:
	var quietest: AudioStreamPlayer = null
	var count := 0
	for c in host.get_children():
		if c.get_meta("sfx_kind", "") != "M":
			continue
		count += 1
		if not c.playing:
			return c
		if quietest == null or c.volume_linear < quietest.volume_linear:
			quietest = c
	if count < MUSIC_MAX:
		return _new_player(host, "M")
	return quietest


static func _bus(bus: String) -> StringName:
	if AudioServer.get_bus_index(bus) < 0 and (bus == AudioMix.OUTDOOR or bus == AudioMix.VOICE):
		AudioMix.ensure_buses()          # Exp 005 (A)
	return StringName(bus) if AudioServer.get_bus_index(bus) >= 0 else &"Master"


static func _start(p: Node, stream: AudioStream, key: String, def: Dictionary, volume_db: float) -> void:
	if p.has_meta("sfx_tween"):
		var tw: Tween = p.get_meta("sfx_tween")
		if tw != null and tw.is_valid():
			tw.kill()
		p.remove_meta("sfx_tween")
	p.stop()
	p.stream = stream
	p.bus = _bus(def["bus"])
	p.volume_db = float(def["vol"]) + volume_db
	var spread := float(def["pitch"])
	p.pitch_scale = 1.0 + _rng.randf_range(-spread, spread) if spread > 0.0 else 1.0
	p.set_meta("sfx_key", key)
	p.set_meta("sfx_t", Time.get_ticks_usec())


static func _place(p: AudioStreamPlayer3D, at: Variant, far: bool) -> void:
	var s: Dictionary = FAR if far else NEAR
	p.unit_size = s["unit"]
	p.max_distance = s["max_distance"]
	p.attenuation_filter_cutoff_hz = s["cutoff"]
	p.attenuation_filter_db = s["filter_db"]
	if at is Vector2:
		p.global_position = Vector3(at.x, LISTENER_HEIGHT, at.y)
	else:
		p.global_position = at


static func _fade(p: Node, to_linear: float, stop_after: bool) -> void:
	if p.has_meta("sfx_tween"):
		var old: Tween = p.get_meta("sfx_tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := p.create_tween()
	tw.tween_property(p, "volume_linear", to_linear, MUSIC_FADE).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(p.stop)
	p.set_meta("sfx_tween", tw)


## Follows the point the current camera looks at, so distance and panning
## are heard from the action rather than from a camera 20 m away.
class _Listener extends AudioListener3D:
	func _process(_delta: float) -> void:
		var vp := get_viewport()
		if vp == null:
			return
		var cam := vp.get_camera_3d()
		if cam == null:
			return
		var basis := cam.global_basis
		var origin := cam.global_position
		var fwd := -basis.z
		var p := origin
		if fwd.y < -0.05:
			var t := (LISTENER_HEIGHT - origin.y) / fwd.y
			if t > 0.0:
				p = origin + fwd * t
		global_transform = Transform3D(basis, p)
		if vp.get_audio_listener_3d() == null:
			make_current()
