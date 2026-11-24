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
##   range        m; a pellet whose first hit lies beyond it is spent (a short tracer, no damage)
##   reload       "magazine": the whole magazine after reload_time, firing is blocked meanwhile
##                "shell": one round per reload_time until full; firing interrupts it
##   reload_time  s (per magazine, or per shell)
##   muzzle       muzzle tip in the rig's gun-node space (VoxelRig.gun; the barrel points along -Y)
##   fire_sound   Sfx names, the first one that exists is played
##   fire_db      volume offset for the fire sound

const DEFS := {
	"handgun": {
		"name": "Handgun", "ammo": "ammo", "capacity": 12, "interval": 0.2, "damage": 1,
		"pellets": 1, "spread": 1.0, "range": 40.0, "reload": "magazine", "reload_time": 1.4,
		"muzzle": Vector3(0, -0.26, 0),
		"fire_sound": ["weapon/handgun_fire"], "fire_db": 0.0,
	},
	"shotgun": {
		"name": "Shotgun", "ammo": "shells", "capacity": 5, "interval": 0.9, "damage": 1,
		"pellets": 6, "spread": 9.0, "range": 14.0, "reload": "shell", "reload_time": 0.5,
		"muzzle": Vector3(0, -0.8, -0.005),
		"fire_sound": ["weapon/shotgun_fire", "weapon/handgun_fire"], "fire_db": 3.0,
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
