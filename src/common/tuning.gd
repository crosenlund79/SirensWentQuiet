class_name Tuning
extends RefCounted
## Shared gameplay numbers for Experiment 001, in meters and seconds.
## All three versions read these so player, weapon, enemies and spawning
## stay comparable. Rendering-specific numbers live in each version.

# --- Player ---------------------------------------------------------------
const PLAYER_SPEED := 4.0            ## m/s top speed
const PLAYER_ACCEL := 28.0           ## m/s^2 toward the input direction
const PLAYER_RADIUS := 0.25          ## collision radius (m)
const PLAYER_HEIGHT := 1.75          ## visual height (m, 3D)
const CLEARANCE_HEIGHT := 1.6        ## collision top / minimum hole height for passage (m)

# --- Handgun (hitscan, unlimited ammo, hold to fire) ------------------------
const FIRE_INTERVAL := 0.2           ## seconds between shots
const SHOT_RANGE := 40.0             ## m
const SHOT_DAMAGE := 1               ## damage to enemies per hit
const MUZZLE_HEIGHT := 1.3           ## 3D gun height (m)
const TALL_THRESHOLD := 1.2          ## furniture at least this tall blocks bullets

# --- Enemies ("psychos") ---------------------------------------------------
const ENEMY_HP := 3
const ENEMY_SPEED := 1.4             ## m/s, deliberately slow
const ENEMY_RADIUS := 0.25
const ENEMY_ATTACK_RANGE := 0.85     ## m, centre to centre with the player
const ENEMY_ATTACK_INTERVAL := 1.1   ## s between swings (player or wall)
const ENEMY_WALL_DAMAGE := 1         ## wall damage per swing
const ENEMY_REPATH_INTERVAL := 0.6   ## s
const ENEMY_HIT_STAGGER := 0.3       ## s of stagger after being shot
const ENEMY_KNOCKBACK := 0.35        ## m pushed back per hit
const ENEMY_CORPSE_TIME := 4.0       ## s a corpse stays before fading out

# --- Spawning ----------------------------------------------------------------
const SPAWN_FIRST_DELAY := 2.0
const SPAWN_INTERVAL := 4.0
const MAX_ENEMIES := 6
const SPAWN_MIN_DISTANCE := 7.0      ## m from the player

# --- Destruction --------------------------------------------------------------
## Hit points of one 1 m wall section in the section-based versions (B, C).
## The voxel version (A) is calibrated so that opening a walk-through hole
## takes a comparable number of shots (roughly 10-20).
const WALL_SECTION_HP := 10
