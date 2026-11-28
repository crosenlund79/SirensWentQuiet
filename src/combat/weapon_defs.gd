class_name WeaponDefs
extends RefCounted
## Weapon definitions (SPEC-003 §2). Owner: K. Pure data plus the pellet
## pattern; the runtime is WeaponHandler, the magazine state lives in
## GameState.weapons, the reserve is the inventory ammo item.
##
## Fields:
##   ammo         inventory item fed into the magazine
##   capacity     magazine size
##   interval     s between shots (also the minimum time from a trigger pull to the next)
##   damage       hits per pellet on an enemy (HouseWorld.shoot deals one; see `damage`)
##   pellets      rays per trigger pull, each through HouseWorld.shoot
##   spread       full cone angle in degrees; every pellet lies within spread / 2 of the aim line
##   range        m; the ray's length (Exp 013: RANGE for every gun)
##   reload       "magazine": the whole magazine after reload_time, firing is blocked meanwhile
##                "shell": one round per reload_time until full; firing interrupts it
##   reload_time  s (per magazine, or per shell)
##   muzzle       muzzle tip in the rig's gun-node space (VoxelRig.gun; the barrel points along -Y)
##   casing_back  m behind the muzzle where the spent casing is ejected
##   fire_sound   Sfx names, the first one that exists is played
##   fire_db      volume offset for the fire sound
##   sounds       optional {SOUNDS kind: [Sfx names]} tried before the shared
##                SOUNDS names (Exp 006 (R): the shotgun's own reload sound)

## Exp 013 fields:
##   range is the same long reach for every gun (RANGE): a shot flies until it
##   hits something or leaves the area; spread is accuracy, not range
##   spread_ads   cone while aiming down the sights (RMB)
##   recoil       kick on the rig (VoxelRig/EliRig.recoil), recoil_recovery per s
##   cam_kick     camera nudge per shot
##   casing       "pistol" | "shell" | "rifle" (the spent case's look)
##   eject        "fire": the case flies at the shot; "cycle": at the pump/bolt
##   cycle        s after the shot when the pump/bolt works (0: none); cycle_time its length
##   cycle_sound  Sfx names for the pump/bolt (first existing one plays)
##   ads_move     walking speed factor while aiming

const RANGE := 150.0                 ## m: leaves the area (HouseWorld.shoot clamps to 4 x SHOT_RANGE)

const DEFS := {
	"handgun": {
		"name": "Handgun", "ammo": "ammo", "capacity": 12, "interval": 0.2, "damage": 1,
		"pellets": 1, "spread": 2.4, "spread_ads": 0.7, "range": RANGE, "reload": "magazine", "reload_time": 1.4,
		"muzzle": Vector3(0, -0.26, 0), "casing_back": 0.15,
		"recoil": 0.8, "recoil_recovery": 12.0, "cam_kick": 0.18,
		"casing": "pistol", "eject": "fire", "cycle": 0.0, "cycle_time": 0.0, "ads_move": 0.8,
		"fire_sound": ["weapon/handgun_fire"], "fire_db": 0.0,
	},
	"shotgun": {
		"name": "Pump shotgun", "ammo": "shells", "capacity": 5, "interval": 0.95, "damage": 1,
		"pellets": 8, "spread": 11.0, "spread_ads": 7.5, "range": RANGE, "reload": "shell", "reload_time": 0.5,
		"muzzle": Vector3(0, -0.8, -0.005), "casing_back": 0.45,
		"recoil": 1.7, "recoil_recovery": 4.0, "cam_kick": 0.7,
		"casing": "shell", "eject": "cycle", "cycle": 0.28, "cycle_time": 0.38, "ads_move": 0.75,
		"cycle_sound": ["weapon/shotgun_pump", "weapon/shell_load"],
		"fire_sound": ["weapon/shotgun_fire", "weapon/handgun_fire"], "fire_db": 3.0,
		"sounds": {"reload_start": ["weapon/shotgun_reload"]},      # Exp 006 (R); falls back to weapon/reload
	},
	"rifle": {
		"name": "Hunting rifle", "ammo": "rifle_rounds", "capacity": 5, "interval": 1.15, "damage": 3,
		"pellets": 1, "spread": 3.0, "spread_ads": 0.25, "range": RANGE, "reload": "shell", "reload_time": 0.65,
		"muzzle": Vector3(0, -0.92, -0.005), "casing_back": 0.55,
		"recoil": 1.25, "recoil_recovery": 6.0, "cam_kick": 0.45,
		"casing": "rifle", "eject": "cycle", "cycle": 0.35, "cycle_time": 0.45, "ads_move": 0.65,
		"cycle_sound": ["weapon/rifle_bolt", "weapon/reload_done"],
		"fire_sound": ["weapon/rifle_fire", "weapon/shotgun_fire", "weapon/handgun_fire"], "fire_db": 4.0,
		"sounds": {"reload_start": ["weapon/rifle_reload"], "shell": ["weapon/rifle_load", "weapon/shell_load"]},
	},
}

## Sounds the handler asks for, with the existing fallbacks used until the
## preferred names exist in Sfx (a request to the audio owner).
const SOUNDS := {
	"dry": ["weapon/dry_fire"],
	"reload_start": ["weapon/reload", "weapon/dry_fire"],
	"reload_done": ["weapon/reload_done", "weapon/dry_fire"],
	"shell": ["weapon/shell_load", "weapon/dry_fire"],
	"switch": ["weapon/switch", "weapon/dry_fire"],
}
const SOUND_DB := {"dry": 0.0, "reload_start": -6.0, "reload_done": -4.0, "shell": -8.0, "switch": -10.0}


## Exp 006 (R): the Sfx names for a handler sound `kind` of weapon `id`: its
## own ("sounds") first, then the shared SOUNDS names.
static func sound_names(id, kind: String) -> Array:
	var out: Array = []
	if has(id):
		out.append_array(DEFS[str(id)].get("sounds", {}).get(kind, []))
	out.append_array(SOUNDS.get(kind, []))
	return out


static func has(id) -> bool:
	return (typeof(id) == TYPE_STRING or typeof(id) == TYPE_STRING_NAME) and DEFS.has(str(id))


static func ids() -> Array:
	return DEFS.keys()


static func get_def(id) -> Dictionary:
	return DEFS[str(id)] if has(id) else {}


static func name_of(id) -> String:
	return str(DEFS[str(id)]["name"]) if has(id) else ""


static func capacity(id) -> int:
	return int(DEFS[str(id)]["capacity"]) if has(id) else 0


static func ammo_of(id) -> String:
	return str(DEFS[str(id)]["ammo"]) if has(id) else ""


## Weapons that take `ammo_id` (e.g. "ammo" -> ["handgun"]).
static func using_ammo(ammo_id: String) -> Array:
	var out := []
	for id in DEFS:
		if DEFS[id]["ammo"] == ammo_id:
			out.append(id)
	return out


## `n` unit directions inside a cone of full angle `spread_deg` around `dir`,
## uniform over the cone's cross-section (pellet pattern). n == 1 with spread 0
## returns `dir` itself. Deterministic for a seeded `rng`.
static func pellet_dirs(dir: Vector3, n: int, spread_deg: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var d := dir.normalized() if dir.length() > 1e-6 else Vector3.FORWARD
	var half := deg_to_rad(maxf(spread_deg, 0.0) * 0.5)
	var side := d.cross(Vector3.UP)
	if side.length() < 1e-4:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(d).normalized()
	for i in maxi(n, 0):
		if half <= 0.0:
			out.append(d)
			continue
		# uniform in the disc of radius tan(half) one unit along the aim line
		var r := tan(half) * sqrt(rng.randf())
		var a := rng.randf() * TAU
		out.append((d + side * (r * cos(a)) + up * (r * sin(a))).normalized())
	return out
