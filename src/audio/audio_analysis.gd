class_name AudioAnalysis
extends RefCounted
## Experiment 005 (A): measures a sound at runtime, so the user's recordings
## can be used as they are (docs/experiment-005/AUDIO.md §4).
##
##   AudioAnalysis.analyse(stream)              # {"length", "start", "end", "loud_db", "active_db"}
##   AudioAnalysis.analyse(stream, true)        # ... plus "steps": [[from, to, active_db], ...]
##
## The stream is decoded in script with AudioStreamPlayback.mix_audio (any
## format the engine plays: imported WAV in any compression, MP3, Ogg), at a
## raised rate scale, which is plenty for a loudness envelope. Nothing is
## written back: the user's files stay untouched.
##
## - start / end: where the sound begins and ends (leading noise, a decaying
##   tail and trailing silence of fixed-length exports are skipped), in seconds.
## - active_db: RMS over the windows within 20 dB of the loudest window, the
##   measure the loudness targets in AudioInbox.RULES use.
## - steps: single footsteps found in a recording of several (onsets with
##   hysteresis; each step runs to the end of its sound, at most MAX_STEP).

const ONSET_DB := 30.0        ## start: the first window within this of the loudest ...
const ATTACK := 0.04          ## ... then back along its rising edge, at most this far
const TAIL_DB := 48.0         ## end: the last window within this of the loudest
const FLOOR_DB := -75.0       ## never treat anything quieter as sound
const PRE_ROLL := 0.012       ## seconds kept before an onset
const POST_ROLL := 0.06       ## seconds kept after the sound ends
const ACTIVE_RANGE_DB := 20.0
const MAX_DECODE := 90.0      ## seconds decoded at most (long music is not analysed)
## Footstep slicing.
const STEP_WINDOW := 0.005
const MIN_STEP_GAP := 0.22    ## seconds between two onsets at least
const MAX_STEP := 0.55        ## a step window is never longer
const MIN_STEP := 0.05
const QUIET_HOLD := 0.04      ## seconds below the low threshold that re-arm the detector
const QUIET_STEP_DB := 9.0    ## steps this much quieter than the median step are dropped


## Decodes `stream` and returns its envelope: linear RMS per `window`
## seconds of source time. Empty if the stream can't be decoded.
static func envelope(stream: AudioStream, window := 0.01, rate_scale := 4.0, max_seconds := MAX_DECODE) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	if stream == null:
		return env
	var pb := stream.instantiate_playback()
	if pb == null:
		return env
	var mix_rate := AudioServer.get_mix_rate()
	var per := maxi(int(round(window * mix_rate / rate_scale)), 1)    # frames per window
	var max_frames := int(minf(max_seconds, MAX_DECODE) * mix_rate / rate_scale)
	pb.start(0.0)
	var acc := 0.0
	var n := 0
	var total := 0
	var guard := 0
	while pb.is_playing() and total < max_frames and guard < 100000:
		guard += 1
		var buf: PackedVector2Array = pb.mix_audio(rate_scale, 4096)
		if buf.is_empty():
			break
		for v in buf:
			var m := (v.x + v.y) * 0.5
			acc += m * m
			n += 1
			if n == per:
				env.append(sqrt(acc / n))
				acc = 0.0
				n = 0
		total += buf.size()
	pb.stop()
	if n > per / 2:
		env.append(sqrt(acc / n))
	return env


## Measures `stream`. With `steps`, also slices it into single footsteps.
## `max_seconds` < the length measures only the start (levels of long beds;
## "end" is then the length).
static func analyse(stream: AudioStream, steps := false, max_seconds := MAX_DECODE) -> Dictionary:
	var length := stream.get_length() if stream != null else 0.0
	var window := STEP_WINDOW if steps else (0.01 if length <= 12.0 else 0.05)
	var rate := 4.0 if steps else (8.0 if length <= 12.0 else 64.0)
	var env := envelope(stream, window, rate, max_seconds)
	var out := analyse_envelope(env, window, steps)
	out["length"] = length
	if length > 0.0:
		out["end"] = length if max_seconds < length else minf(float(out["end"]), length)
	return out


## The analysis of an envelope (pure; tests feed synthetic envelopes).
static func analyse_envelope(env: PackedFloat32Array, window: float, steps := false) -> Dictionary:
	var out := {"length": env.size() * window, "start": 0.0, "end": 0.0, "loud_db": -INF,
			"active_db": -INF, "steps": []}
	if env.is_empty():
		return out
	var db := PackedFloat32Array()
	db.resize(env.size())
	var loud := -INF
	for i in env.size():
		db[i] = linear_to_db(maxf(env[i], 1e-7))
		loud = maxf(loud, db[i])
	out["loud_db"] = loud
	out["end"] = env.size() * window
	if loud <= FLOOR_DB:
		return out
	out["active_db"] = _active_db(env, db, 0, env.size(), loud)
	var on := maxf(loud - ONSET_DB, FLOOR_DB)
	var tail := maxf(loud - TAIL_DB, FLOOR_DB)
	var first := 0
	while first < db.size() and db[first] < on:
		first += 1
	# Fixed-length exports often start with a decaying tail or noise well
	# below the sound: skip it, but keep the attack's rising edge.
	var back := int(ATTACK / window)
	var f0 := first
	while first > 0 and f0 - first < back and db[first - 1] < db[first] and db[first - 1] > tail:
		first -= 1
	var last := db.size() - 1
	while last > first and db[last] < tail:
		last -= 1
	out["start"] = maxf(first * window - PRE_ROLL, 0.0)
	out["end"] = minf((last + 1) * window + POST_ROLL, env.size() * window)
	if steps:
		out["steps"] = _steps(env, db, window)
	return out


## Power mean of the windows within ACTIVE_RANGE_DB of `loud`, in dB.
static func _active_db(env: PackedFloat32Array, db: PackedFloat32Array, a: int, b: int, loud: float) -> float:
	var sum := 0.0
	var n := 0
	for i in range(a, b):
		if db[i] >= loud - ACTIVE_RANGE_DB:
			sum += env[i] * env[i]
			n += 1
	return linear_to_db(sqrt(sum / n)) if n > 0 else -INF


## Onsets with hysteresis between a high and a low threshold placed between
## the noise floor (20th percentile) and the loudest window.
static func _steps(env: PackedFloat32Array, db: PackedFloat32Array, window: float) -> Array:
	var sorted := db.duplicate()
	sorted.sort()
	var floor_db := sorted[int(sorted.size() * 0.2)]
	var loud := sorted[sorted.size() - 1]
	var span := loud - floor_db
	if span < 6.0:
		return []
	var hi := floor_db + span * 0.55
	var lo := floor_db + span * 0.3
	var onsets: Array[int] = []
	var armed := true
	var quiet := 0
	var hold := maxi(int(QUIET_HOLD / window), 1)
	var gap := int(MIN_STEP_GAP / window)
	for i in db.size():
		if armed and db[i] >= hi and (onsets.is_empty() or i - onsets[-1] >= gap):
			# walk back to where the rise began
			var s := i
			while s > 0 and db[s - 1] > lo and db[s - 1] < db[s] and i - s < int(0.03 / window):
				s -= 1
			onsets.append(s)
			armed = false
			quiet = 0
		elif not armed:
			quiet = quiet + 1 if db[i] < lo else 0
			if quiet >= hold:
				armed = true
	var out := []
	for k in onsets.size():
		var a := onsets[k]
		var limit := mini(onsets[k + 1] if k + 1 < onsets.size() else db.size(), a + int((MAX_STEP - PRE_ROLL) / window))
		var e := limit - 1
		while e > a and db[e] < lo:
			e -= 1
		var from := maxf(a * window - PRE_ROLL, 0.0)
		var to := minf((e + 1) * window + POST_ROLL * 0.5, limit * window)
		if to - from < MIN_STEP:
			continue
		var step_loud := -INF
		for i in range(a, e + 1):
			step_loud = maxf(step_loud, db[i])
		out.append([from, to, _active_db(env, db, a, e + 1, step_loud)])
	# Scuffs and noise far quieter than the typical step are dropped.
	if out.size() >= 3:
		var levels := []
		for s in out:
			levels.append(s[2])
		levels.sort()
		var typical: float = levels[levels.size() / 2]
		out = out.filter(func(s): return float(s[2]) >= typical - QUIET_STEP_DB)
	return out
