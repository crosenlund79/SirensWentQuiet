class_name AudioInbox
extends RefCounted
## Experiment 005 (A): the audio inbox (docs/experiment-005/AUDIO.md).
##
## The user drops recordings with descriptive names into `assets/audio inbox/`
## (the documented drop folder; the first upload in `assets/audio/_inbox/` is
## read as well). Both are scanned recursively, and each file name is matched
## against RULES to a logical sound name ("Footsteps - wood floor.wav" ->
## player/step_wood). Numbered variants ("Door open 1".."4", "Shot 01".."03")
## form one random-variation pool. Nothing in the folders is moved, renamed,
## converted or rewritten.
##
##   AudioInbox.clip(name)        # a random clip of `name`'s pool, or {}
##   AudioInbox.has(name)         # the inbox has files for `name`
##   AudioInbox.report()          # mapped and unknown files (F10, docs)
##
## Precedence (Sfx.clip): a creator file in custom/audio/ (next to the game)
## wins for its name, then the inbox, then the generated template.
## Files that match no rule, or two rules equally well, are reported (a log
## line, the F10 Audio section) and never played for unrelated events.
##
## Playback details come from AudioAnalysis at first use: one-shots skip the
## silence that fixed-length exports carry at the start and end, footstep
## recordings are sliced into single steps, and each clip is normalised
## towards its rule's loudness target (clamped, see GAIN_RANGE).

## Scanned in this order; for each logical name the first folder that has
## files for it provides the whole pool.
const ROOTS := ["res://assets/audio inbox", "res://assets/audio/_inbox"]
const EXTENSIONS := ["wav", "ogg", "mp3"]
const GAIN_RANGE := Vector2(-12.0, 12.0)     ## normalisation never moves a clip further
const LEVEL_SECONDS := 10.0                  ## beds and loops: the level of their first seconds
## Names that borrow another name's pool when they have none of their own.
const ALIASES := {
	"player/footstep": "player/step_wood",   # the stairs and the old footstep group
	"music/dawn": "music/menu",              # the theme, softly at dawn
}

## The mapping table. A file maps to the rule it matches best:
##   all   every entry must match a word of the file name (a string, or a list
##         of alternatives); an entry matches a word that starts with it, case
##         ignored, so "footstep" matches "Footsteps" and "wood" "wooden".
##   none  no word of the file name may start with one of these.
##   kind  oneshot: trimmed to its sound and normalised to `db` (active RMS, dBFS)
##         step:    sliced into single footsteps, each normalised to `db`
##         loop:    looped in code, normalised to `db` (one file plays at a time)
##         bed:     a layer that cross-fades between its files, normalised to `db`
##         music, voice: the whole file, `gain` dB, no analysis
## The rule with more `all` entries wins; a tie between different names is
## ambiguous. When no rule matches the file name, its folder names are added
## to the words (a file in "Theme/" matches music/menu).
const RULES := [
	# footsteps (sliced into single steps, triggered by the gait)
	{"name": "player/step_snow", "all": [["footstep", "step"], "snow"], "none": ["enemy"], "kind": "step", "db": -27.0},
	{"name": "player/step_wood", "all": [["footstep", "step"], "wood"], "none": ["enemy"], "kind": "step", "db": -25.0},
	{"name": "player/step_cement", "all": [["footstep", "step"], ["cement", "concrete", "stone", "tile"]], "none": ["enemy"], "kind": "step", "db": -25.0},
	{"name": "enemy/step_snow", "all": ["enemy", ["footstep", "step"], "snow"], "kind": "step", "db": -27.0},
	{"name": "enemy/step_wood", "all": ["enemy", ["footstep", "step"], "wood"], "kind": "step", "db": -26.0},
	# weapons
	{"name": "weapon/handgun_fire", "all": [["handgun", "pistol"], ["shot", "fire", "gunshot"]], "none": ["reload", "dry"], "kind": "oneshot", "db": -13.0},
	{"name": "weapon/shotgun_fire", "all": ["shotgun", ["shot", "fire", "blast"]], "none": ["reload", "shell"], "kind": "oneshot", "db": -12.0},
	{"name": "weapon/reload", "all": ["reload"], "none": ["done", "finish", "ready", "shell"], "kind": "oneshot", "db": -19.0},
	{"name": "weapon/shotgun_reload", "all": ["shotgun", "reload"], "none": ["done", "finish", "ready", "shell"], "kind": "oneshot", "db": -19.0},   # Exp 006 (R)
	{"name": "weapon/reload_done", "all": ["reload", ["done", "finish", "ready"]], "kind": "oneshot", "db": -19.0},
	{"name": "weapon/shell_load", "all": ["shell"], "kind": "oneshot", "db": -20.0},
	{"name": "weapon/dry_fire", "all": [["dry", "empty"]], "kind": "oneshot", "db": -20.0},
	{"name": "weapon/switch", "all": ["weapon", ["switch", "holster", "draw", "equip"]], "kind": "oneshot", "db": -22.0},
	# impacts
	{"name": "impact/wood", "all": ["impact", "wood"], "none": ["enemy", "heavy"], "kind": "oneshot", "db": -18.0},
	{"name": "impact/plaster", "all": ["impact", ["plaster", "drywall"]], "kind": "oneshot", "db": -18.0},
	{"name": "impact/glass", "all": ["glass"], "kind": "oneshot", "db": -18.0},
	{"name": "impact/metal", "all": ["impact", "metal"], "none": ["enemy", "heavy"], "kind": "oneshot", "db": -18.0},
	{"name": "impact/flesh", "all": ["impact", ["flesh", "body"]], "kind": "oneshot", "db": -19.0},
	{"name": "impact/ground", "all": ["impact", ["ground", "dirt", "snow"]], "kind": "oneshot", "db": -19.0},
	# building and destruction
	{"name": "build/hammer", "all": [["building", "constructing", "construct", "hammer", "nail"]], "none": ["metal", "place", "demolish", "invalid"], "kind": "oneshot", "db": -18.0},
	{"name": "build/upgrade", "all": ["metal", ["hammer", "upgrade", "reinforce"]], "kind": "oneshot", "db": -17.0},
	{"name": "build/place", "all": [["place", "plank", "board"]], "none": ["boarded"], "kind": "oneshot", "db": -19.0},
	{"name": "build/demolish", "all": [["demolish", "demolition", "dismantle", "crowbar"]], "kind": "oneshot", "db": -18.0},
	{"name": "build/invalid", "all": [["invalid", "denied", "cannot"]], "kind": "oneshot", "db": -24.0},
	{"name": "structure/break", "all": [["destruction", "break", "smash"], ["wall", "wood", "timber"]], "none": ["glass"], "kind": "oneshot", "db": -16.0},
	{"name": "structure/crumble", "all": [["crumble", "debris", "rubble"]], "kind": "oneshot", "db": -19.0},
	{"name": "structure/blast", "all": [["blast", "explosion", "explode"]], "none": ["enemy", "bomber", "shotgun"], "kind": "oneshot", "db": -15.0},
	# doors
	{"name": "door/open", "all": ["door", "open"], "none": ["fridge", "car"], "kind": "oneshot", "db": -22.0},
	{"name": "door/close", "all": ["door", ["close", "shut", "slam"]], "none": ["fridge", "car"], "kind": "oneshot", "db": -20.0},
	{"name": "door/bash", "all": [["bash", "heavy", "pound", "bang", "kick"]], "kind": "oneshot", "db": -16.0},
	# enemies
	{"name": "enemy/moan", "all": ["enemy", ["vocal", "moan", "groan", "growl", "voice"]], "kind": "oneshot", "db": -21.0},
	{"name": "enemy/attack", "all": ["enemy", ["attack", "swipe", "swing", "snarl"]], "kind": "oneshot", "db": -19.0},
	{"name": "enemy/hit", "all": ["enemy", ["hit", "pain", "grunt", "hurt"]], "kind": "oneshot", "db": -20.0},
	{"name": "enemy/death", "all": ["enemy", ["death", "die", "dying"]], "kind": "oneshot", "db": -19.0},
	{"name": "enemy/bomber_fuse", "all": ["bomber", ["fuse", "beep"]], "kind": "oneshot", "db": -20.0},
	{"name": "enemy/bomber_blast", "all": ["bomber", ["blast", "explosion", "explode"]], "kind": "oneshot", "db": -13.0},
	# the player
	{"name": "player/hurt", "all": [["hurt", "pain"]], "none": ["enemy"], "kind": "oneshot", "db": -20.0},
	{"name": "player/eat", "all": [["eat", "chew"]], "kind": "oneshot", "db": -23.0},
	{"name": "player/drink", "all": [["drink", "gulp", "sip"]], "kind": "oneshot", "db": -23.0},
	{"name": "player/bandage", "all": [["bandage", "medkit"]], "kind": "oneshot", "db": -23.0},
	{"name": "player/sleep", "all": [["sleep", "yawn"]], "kind": "oneshot", "db": -23.0},
	{"name": "player/death", "all": [["death", "die"]], "none": ["enemy"], "kind": "oneshot", "db": -19.0},
	# the house (Exp 005: played when the files exist)
	{"name": "home/fireplace_light", "all": [["fireplace", "fire"], ["light", "ignite", "kindle"]], "none": ["switch"], "kind": "oneshot", "db": -22.0},
	{"name": "home/fireplace_out", "all": [["fireplace", "fire"], ["extinguish", "out", "douse"]], "kind": "oneshot", "db": -22.0},
	{"name": "home/light_switch", "all": [["light", "lamp"], "switch"], "none": ["weapon"], "kind": "oneshot", "db": -24.0},
	{"name": "car/start", "all": ["car", ["start", "engine", "ignition"]], "kind": "oneshot", "db": -18.0},
	{"name": "build/dig", "all": [["shovel", "dig"]], "kind": "oneshot", "db": -19.0},
	# interface
	{"name": "ui/click", "all": ["ui", "click"], "kind": "oneshot", "db": -24.0},
	{"name": "ui/hover", "all": ["ui", "hover"], "kind": "oneshot", "db": -31.0},
	{"name": "ui/open", "all": ["ui", "open"], "kind": "oneshot", "db": -24.0},
	{"name": "ui/close", "all": ["ui", "close"], "kind": "oneshot", "db": -24.0},
	{"name": "ui/error", "all": ["ui", "error"], "kind": "oneshot", "db": -24.0},
	# stingers and music
	{"name": "stinger/invasion", "all": [["stinger", "sting"], ["invasion", "threat", "attack"]], "kind": "oneshot", "db": -17.0},
	{"name": "stinger/dawn", "all": [["stinger", "sting"], ["dawn", "morning"]], "kind": "oneshot", "db": -21.0},
	{"name": "music/menu", "all": [["theme", "menu"]], "none": ["ui", "stinger"], "kind": "music", "gain": -8.0},
	{"name": "music/dawn", "all": ["music", ["dawn", "morning"]], "kind": "music", "gain": -8.0},
	# ambience: loops, beds and details
	{"name": "ambient/wind_day", "all": ["wind"], "none": ["night", "wolf", "howl"], "kind": "loop", "db": -32.0},
	{"name": "ambient/night", "all": ["night", ["wind", "bed", "loop", "ambience", "ambiance"]], "none": ["owl", "wolf"], "kind": "loop", "db": -34.0},
	{"name": "ambient/tension", "all": [["tension", "drone", "dread"]], "kind": "loop", "db": -31.0},
	{"name": "ambient/distant", "all": ["distant"], "kind": "oneshot", "db": -20.0},
	{"name": "ambient/distant_1", "all": ["distant", ["scrape", "metal"]], "kind": "oneshot", "db": -20.0},
	{"name": "ambient/distant_2", "all": ["distant", ["shriek", "scream"]], "kind": "oneshot", "db": -20.0},
	{"name": "ambient/distant_3", "all": ["distant", "siren"], "kind": "oneshot", "db": -20.0},
	{"name": "ambient/forest", "all": [["natural", "nature", "forest", "outdoor", "woods", "wilderness"]], "none": ["footstep", "step"], "kind": "bed", "db": -31.0},
	{"name": "ambient/fireplace", "all": [["fireplace", "hearth"]], "none": ["light", "ignite", "kindle", "extinguish", "out", "douse"], "kind": "bed", "db": -27.0},
	{"name": "ambient/room_tone", "all": [["room", "interior", "indoor"], ["tone", "ambience", "ambiance", "hum"]], "none": ["basement"], "kind": "bed", "db": -42.0},
	{"name": "ambient/basement_tone", "all": [["basement", "cellar"], ["tone", "ambience", "ambiance", "hum"]], "kind": "bed", "db": -40.0},
	{"name": "ambient/owl", "all": [["owl", "hoot"]], "kind": "oneshot", "db": -24.0},
	{"name": "ambient/wolf", "all": [["wolf", "wolves"]], "kind": "oneshot", "db": -23.0},
	{"name": "ambient/house_creak", "all": [["creak", "settling"]], "kind": "oneshot", "db": -30.0},
	{"name": "ambient/house_creak", "all": ["wood", "house"], "kind": "oneshot", "db": -30.0},
	# Eli's voice
	{"name": "voice/eli_new_game", "all": ["eli", "new"], "kind": "voice", "gain": 0.0},
	{"name": "voice/eli_continue", "all": ["eli", ["continue", "saved"]], "kind": "voice", "gain": 0.0},
]

## Optional per-file adjustments in dB on top of the normalisation, by the
## file's name without extension (lower case). Empty by default.
const FILE_GAIN := {}

static var _scanned := false
static var _files := {}        ## logical name -> Array of {"path", "file", "variant", "root", "rule"}
static var _unknown: Array = [] ## {"path", "reason"}
static var _clips := {}        ## logical name -> Array of clips (built at first use)
static var _last := {}         ## logical name -> index of the last clip played
static var _analysis := {}     ## path -> AudioAnalysis result
static var _rng := RandomNumberGenerator.new()
static var roots_override: Array = []   ## tests: scan these folders instead of ROOTS


# ---------------------------------------------------------------- queries

## Scans the folders once per session (again with `force`).
static func scan(force := false) -> void:
	if _scanned and not force:
		return
	_scanned = true
	_files.clear()
	_unknown.clear()
	_clips.clear()
	_last.clear()
	var claimed := {}           # logical name -> the root that provides it
	for root in roots():
		var found := {}         # logical name -> files in this root
		for path in list_audio_files(root):
			var m := match_path(path, root)
			if m["name"] == "":
				_unknown.append({"path": path, "reason": m["reason"]})
				continue
			if not found.has(m["name"]):
				found[m["name"]] = []
			found[m["name"]].append({"path": path, "file": path.get_file(), "variant": m["variant"],
					"root": root, "rule": m["rule"]})
		for n in found:
			if claimed.has(n):
				for f in found[n]:
					_unknown.append({"path": f["path"], "reason": "shadowed: %s already comes from %s" % [n, claimed[n]]})
				continue
			claimed[n] = root
			var files: Array = found[n]
			files.sort_custom(func(a, b): return a["variant"] < b["variant"] if a["variant"] != b["variant"] else a["file"] < b["file"])
			_files[n] = files
	var total := 0
	for n in _files:
		total += (_files[n] as Array).size()
	if total > 0 or not _unknown.is_empty():
		print("AudioInbox: %d files mapped to %d sounds, %d unknown or ambiguous" % [total, _files.size(), _unknown.size()])
	for u in _unknown:
		push_warning("AudioInbox: '%s' not used (%s)" % [u["path"], u["reason"]])


static func roots() -> Array:
	return roots_override if not roots_override.is_empty() else ROOTS


## True when the inbox has files for `name` (not counting aliases).
static func has(name: String) -> bool:
	scan()
	return _files.has(name)


## The pool `name` plays from: its own, else its alias's ("" if none).
static func pool_name(name: String) -> String:
	scan()
	if _files.has(name):
		return name
	var alias: String = ALIASES.get(name, "")
	return alias if alias != "" and _files.has(alias) else ""


## The files mapped to `name` (paths).
static func files_of(name: String) -> PackedStringArray:
	scan()
	var out := PackedStringArray()
	for f in _files.get(name, []):
		out.append(f["path"])
	return out


## Every logical name with inbox files, sorted.
static func names() -> PackedStringArray:
	scan()
	var out := PackedStringArray(_files.keys())
	out.sort()
	return out


## The rule entry for a logical name ({} if none).
static func rule_of(name: String) -> Dictionary:
	for r in RULES:
		if r["name"] == name:
			return r
	return {}


## A random clip of `name`'s pool (never the same one twice in a row when
## there is a choice): {"stream", "from", "to", "db", "source": "inbox",
## "path"}. `to` 0 means "to the end". {} when the inbox has nothing.
static func clip(name: String) -> Dictionary:
	var pool := pool_name(name)
	if pool == "":
		return {}
	var clips := clips_of(pool)
	if clips.is_empty():
		return {}
	var i := _rng.randi_range(0, clips.size() - 1)
	if clips.size() > 1 and i == int(_last.get(pool, -1)):
		i = (i + 1 + _rng.randi_range(0, clips.size() - 2)) % clips.size()
	_last[pool] = i
	return clips[i]


## Every clip of `name` (loads and analyses its files on first use).
static func clips_of(name: String) -> Array:
	scan()
	if _clips.has(name):
		return _clips[name]
	var out := []
	for f in _files.get(name, []):
		out.append_array(_make_clips(f))
	_clips[name] = out
	return out


## Loads and analyses a pool now (beds at start-up, so later cross-fades don't stall).
static func prepare(name: String) -> void:
	var pool := pool_name(name)
	if pool != "":
		clips_of(pool)


## Loads and analyses every pool except music (the game does it while it
## loads, so the first door or shot doesn't stall a frame). Returns ms spent.
static func prepare_all() -> float:
	var t0 := Time.get_ticks_usec()
	scan()
	for n in _files:
		var f: Dictionary = (_files[n] as Array)[0]
		if int(f["rule"]) >= 0 and RULES[f["rule"]].get("kind", "") == "music":
			continue
		clips_of(n)
	return (Time.get_ticks_usec() - t0) / 1000.0


## Mapped and unknown files: {"mapped": {name: [file, ...]}, "unknown": [{"path", "reason"}]}.
static func report() -> Dictionary:
	scan()
	var mapped := {}
	for n in _files:
		var list := []
		for f in _files[n]:
			list.append(f["path"])
		mapped[n] = list
	return {"mapped": mapped, "unknown": _unknown.duplicate(true)}


## Short text for the developer menu.
static func report_text() -> String:
	var r := report()
	var lines := PackedStringArray()
	var names_sorted: Array = r["mapped"].keys()
	names_sorted.sort()
	for n in names_sorted:
		var files: Array = r["mapped"][n]
		var first: String = (files[0] as String).get_file().get_basename()
		lines.append("%s ← %s%s" % [n, first, " (+%d)" % (files.size() - 1) if files.size() > 1 else ""])
	for u in r["unknown"]:
		lines.append("[color=#e0a060]unused: %s — %s[/color]" % [(u["path"] as String).get_file(), u["reason"]])
	if lines.is_empty():
		lines.append("The audio inbox is empty.")
	return "\n".join(lines)


## Tests: forget the scan, the clips and the analysis.
static func reset() -> void:
	_scanned = false
	_files.clear()
	_unknown.clear()
	_clips.clear()
	_last.clear()
	_analysis.clear()


# ---------------------------------------------------------------- matching

## Audio files under `root`, recursively, as loadable paths. In an exported
## game the folder lists "X.wav.import" (or ".remap") instead of "X.wav".
static func list_audio_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(root):
		return out
	var seen := {}
	for f in DirAccess.get_files_at(root):
		var name := f
		for suffix in [".import", ".remap"]:
			if name.ends_with(suffix):
				name = name.trim_suffix(suffix)
		if EXTENSIONS.has(name.get_extension().to_lower()) and not seen.has(name):
			seen[name] = true
			out.append(root.path_join(name))
	for d in DirAccess.get_directories_at(root):
		if not d.begins_with("."):
			out.append_array(list_audio_files(root.path_join(d)))
	return out


## The words of a name: lower case, split at anything but letters and digits.
static func words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cur += ch
		elif cur != "":
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


## Splits a trailing variant number off a file's base name:
## "Door open 3" -> ["Door open", 3]; "Handgun Shot 01" -> [.., 1]; "Snow" -> ["Snow", 0].
static func split_variant(base: String) -> Array:
	var w := base.strip_edges()
	var i := w.length()
	while i > 0 and w[i - 1] >= "0" and w[i - 1] <= "9":
		i -= 1
	if i == w.length() or i == 0 or w.length() - i > 3:
		return [w, 0]
	var sep := w[i - 1]
	if not (sep in [" ", "_", "-", "."]):
		return [w, 0]
	return [w.substr(0, i).strip_edges().rstrip(" _-."), int(w.substr(i))]


## Maps one file to a logical name: {"name", "variant", "rule", "reason"}.
## `root` is the scanned folder (its subfolders' names may help).
static func match_path(path: String, root := "") -> Dictionary:
	var split := split_variant(path.get_file().get_basename())
	var stem: String = split[0]
	var r := match_words(words(stem))
	if r["name"] == "" and r["reason"] == "no rule matches":
		var rel := path.get_base_dir().trim_prefix(root) if root != "" else path.get_base_dir()
		var w := words(stem)
		w.append_array(words(rel))
		var r2 := match_words(w)
		if r2["name"] != "" or r2["reason"] != "no rule matches":
			r = r2
	r["variant"] = split[1]
	return r


## The best rule for a set of words: {"name", "rule", "reason"}.
static func match_words(w: PackedStringArray) -> Dictionary:
	var best := -1
	var winners := {}
	var best_rule := -1
	for i in RULES.size():
		var rule: Dictionary = RULES[i]
		var score := _score(rule, w)
		if score < 0:
			continue
		if score > best:
			best = score
			winners = {rule["name"]: true}
			best_rule = i
		elif score == best:
			winners[rule["name"]] = true
	if best < 0:
		return {"name": "", "rule": -1, "reason": "no rule matches"}
	if winners.size() > 1:
		var names_sorted: Array = winners.keys()
		names_sorted.sort()
		return {"name": "", "rule": -1, "reason": "ambiguous: " + ", ".join(names_sorted)}
	return {"name": RULES[best_rule]["name"], "rule": best_rule, "reason": ""}


static func _score(rule: Dictionary, w: PackedStringArray) -> int:
	for bad in rule.get("none", []):
		if _has_word(w, [bad]):
			return -1
	for need in rule["all"]:
		if not _has_word(w, need if need is Array else [need]):
			return -1
	return (rule["all"] as Array).size()


static func _has_word(w: PackedStringArray, options: Array) -> bool:
	for word in w:
		for o in options:
			if word.begins_with(o):
				return true
	return false


# ---------------------------------------------------------------- clips

static func _make_clips(f: Dictionary) -> Array:
	var stream := load_stream(f["path"])
	if stream == null:
		push_warning("AudioInbox: '%s' could not be loaded" % f["path"])
		return []
	var rule: Dictionary = RULES[f["rule"]] if int(f["rule"]) >= 0 else {}
	var kind: String = rule.get("kind", "oneshot")
	var trim := float(FILE_GAIN.get((f["file"] as String).get_basename().to_lower(), 0.0))
	var base := {"stream": stream, "from": 0.0, "to": 0.0, "db": 0.0, "source": "inbox", "path": f["path"]}
	if kind == "music" or kind == "voice":
		base["db"] = float(rule.get("gain", 0.0)) + trim
		if kind == "music":
			base["stream"] = looped(stream)
		return [base]
	var a := analysis(f["path"], stream, kind == "step", LEVEL_SECONDS if kind == "bed" or kind == "loop" else AudioAnalysis.MAX_DECODE)
	var target := float(rule.get("db", -20.0))
	if kind == "step":
		var out := []
		for s in a.get("steps", []):
			var c := base.duplicate()
			c["from"] = s[0]
			c["to"] = s[1]
			c["db"] = _gain(target, float(s[2])) + trim
			out.append(c)
		if out.is_empty():
			# no steps found: the whole sound as one step
			base["from"] = a.get("start", 0.0)
			base["to"] = minf(float(a.get("end", 0.0)), float(a.get("start", 0.0)) + AudioAnalysis.MAX_STEP)
			base["db"] = _gain(target, float(a.get("active_db", target))) + trim
			out.append(base)
		return out
	base["db"] = _gain(target, float(a.get("active_db", target))) + trim
	if kind == "oneshot":
		base["from"] = float(a.get("start", 0.0))
		var end := float(a.get("end", 0.0))
		base["to"] = end if end < stream.get_length() - 0.02 else 0.0
	elif kind == "loop":
		base["stream"] = looped(stream)
	return [base]


static func _gain(target: float, measured: float) -> float:
	if is_inf(measured) or is_nan(measured):
		return 0.0
	return clampf(target - measured, GAIN_RANGE.x, GAIN_RANGE.y)


## The analysis of a file (cached for the session).
static func analysis(path: String, stream: AudioStream = null, steps := false, max_seconds := AudioAnalysis.MAX_DECODE) -> Dictionary:
	var key := "%s#%s#%d" % [path, "steps" if steps else "", int(max_seconds)]
	if not _analysis.has(key):
		if stream == null:
			stream = load_stream(path)
		_analysis[key] = AudioAnalysis.analyse(stream, steps, max_seconds) if stream != null else {}
	return _analysis[key]


## Loads an inbox file: the imported resource, or (a file not imported yet)
## straight from disk.
static func load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


## A looping copy of `stream` (the imported resource itself stays one-shot,
## so a user file needs no import settings).
static func looped(stream: AudioStream) -> AudioStream:
	if stream == null or is_looping(stream):
		return stream
	var s := stream.duplicate() as AudioStream
	if s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


static func is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false
