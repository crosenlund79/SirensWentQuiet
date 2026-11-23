# Experiment 002 — The First Days: shared spec and contracts

Single source of truth for module boundaries, APIs, numbers and file ownership during Experiment 002. The user's assignment (2026-11-23, "Experiment 002 — The First Days") is the authority. This file turns it into contracts. Rules: `docs/GODOT_CLAUDE_GUIDELINES.md`.

## 0. Goal in one paragraph

Turn Version A (true 3D voxels) into the first playable survival prototype: **wake → assess needs → scavenge → return → build and prepare → survive the night → sleep → repeat**.

- One house on one lot, ringed by dense fog. Walking into the fog is a deliberate interaction that opens a *simulated* expedition: no other playable location.
- The systems are a running clock, hunger, hydration, energy, health, a small inventory, nine bullets, simple construction and repair, periodic invasions, sleep, sound with creator overrides, menus, a cheat menu, and a real save that restores the damaged and rebuilt house.
- Keep every system small, and make them interact.

The three Experiment 001 demos stay playable from **Visual Experiments** in the main menu. They are history, not dependencies: no new code may depend on `src/modular/` or `src/illustrated/`.

## 1. Module map and file ownership

Each agent edits **only** its own paths. Changes needed elsewhere go in your final report as a request; don't make them yourself.

| Owner | Paths (exclusive) | Purpose |
|---|---|---|
| **S** Survival + save | `src/survival/**`, `src/save/**`, `tests/survival/**`, `tests/save/**`, `docs/experiment-002/survival.md` | Clock, stats, inventory, items, costs and cheats semantics, sleep planning, invasion schedule, expedition result application, death; save file IO |
| **V** Voxel world + construction | `src/voxel/**`, `src/world/**`, `src/build/**`, `tests/voxel/**`, `tests/world/**`, `tests/build/**`, `docs/experiment-002/world.md`, `docs/experiment-002/VOXEL_RESOLUTION.md`, `docs/experiment-001/voxel.md` (only if the demo's behaviour changes) | The house world (structure voxels, design vs current state, objects, nav, collision, shooting and enemy strikes, cutaway, roof, yard), its persistence, the 0.2 m resolution investigation, construction mode, repair, upgrade, demolish, exit rule, no-power night lighting |
| **P** Props (hybrid look) | `src/props/**`, `assets/graphics/props/**`, `tools/art/props/**`, `tests/props/**`, `docs/experiment-002/props.md` | Conventional stylized 3D meshes for furniture, doors, barricades, storage, rain collector, candles and lanterns, yard props and vegetation, forked from Experiment 001's modular kit (copy, never import `src/modular`) |
| **U** UI | `src/ui/**`, `src/menu/**`, `src/launcher/**`, `tests/ui/**`, `docs/experiment-002/ui.md` | UI theme, main menu, settings (+ persistence), pause menu, HUD, inventory panel, developer menu (F10), sleep dialog, death screen, intro, confirm dialog, Visual Experiments menu |
| **A** Audio | `src/audio/**`, `assets/audio/**`, `tools/audio/**`, `tests/audio/**`, `docs/experiment-002/audio.md`, **plus** `src/common/asset_resolver.gd` (add `get_audio` only) and `tests/common/test_asset_resolver.gd` | Sound playback API, ambience, generated template sounds, creator audio overrides |
| **E** Expeditions | `src/expedition/**`, `tests/expedition/**`, `docs/experiment-002/expeditions.md` | Fog bank and lot boundary, boundary interaction, destinations, events, resolution, expedition screens |
| **G** Game loop | `src/game/**`, `tests/game/**`, `tools/survival_playtest.*`, `docs/experiment-002/game.md` | Game scene root, wiring, firing and ammo, interactions, invasion director, sleep, expedition and death flows, autosave, pause, dev API, end-to-end playtest |
| **Lead** | everything else: `project.godot`, `default_bus_layout.tres`, `src/common/**` (except A's addition), `tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_versions_smoke.gd`, `README.md`, `docs/PROJECT_BRIEF.md`, `docs/BACKLOG.md`, this SPEC | Contracts and integration |

The foundation commit gives every module a **working stub or core** with the exact class names and APIs below. Owners replace or extend their stubs, keeping the APIs. Additive changes are fine; report them. If you must change a signature, keep the old one working and report it.

## 2. Scenes and flow

- **Main scene:** `res://src/menu/main_menu.tscn` (U), with New Game · Continue · Settings · Visual Experiments · Quit.
- **New Game:** asks for confirmation if a save exists, then sets `GameLaunch.mode = "new"` and changes to `res://src/game/game.tscn` (G).
- **Continue:** disabled, with a short reason, when `SaveGame.info()["valid"]` is false. Otherwise sets `GameLaunch.mode = "continue"` and changes to the game scene.
- **Visual Experiments:** `res://src/launcher/launcher.tscn` (the Experiment 001 launcher, kept). Esc / Back returns to the main menu. The demos' Esc still returns to the launcher.
- **In game:**
  - **Esc** closes the open panel or build mode; otherwise it opens the pause menu (Resume · Save · Settings · Main Menu). The tree is paused while pause, inventory, sleep, expedition or death screens are open. The developer menu does not pause.
- **Death:** the death screen shows days survived. The save is deleted (the run is over), and the screen leads back to the main menu.
- No Autoloads (guideline 1). Cross-scene state uses small static classes: `GameLaunch`, `GameSettings`, `AssetResolver`, `Sfx`.

## 3. Input actions (lead adds them to `project.godot`)

Existing: `move_*` (WASD/arrows), `fire` (LMB), `zoom_in`/`zoom_out` (wheel), `toggle_help` (H/F1), `toggle_stats` (F3), plus the demo-only `toggle_day_night` (N), `reset_level` (R) and `back_to_launcher` (Esc).

New:

| Action | Keys | Use |
|---|---|---|
| `interact` | E | bed, doors, crates, collectors, fog boundary |
| `inventory` | I, Tab | inventory panel |
| `build_mode` | B | construction mode on/off |
| `build_rotate` | R | rotate the piece in build mode |
| `secondary` | RMB | cancel or step back in build mode |
| `pause` | Esc | pause menu / close panel |
| `dev_menu` | F10 | developer (cheat) menu |

Number keys 1–7 select pieces in build mode; BuildMode reads them as raw keys, with no actions.

## 4. Physics layers

1 environment · 2 walls · 3 player · 4 enemies · 5 low_obstacles · **6 lot_boundary** (new).

- **Player mask:** 1|2|5|6. **Enemy mask:** 1|2|4|5. Enemies ignore the lot boundary and walk in out of the fog.
- **Voxel chunks:** layer 2. **Tall furniture:** layer 1 (it stops bullets via the physics ray). **Low furniture:** layer 5.
- **Closed doors:** layers 1|2. They block bodies and stop bullets, which make a wood impact but do no damage.
- **Barricades:** layer 2. They block bodies, but bullets pass between the planks.
- **Crates and collectors:** layer 1.
- **Bullet physics ray mask:** 1|8, plus voxel ray traversal (as in Version A).

## 5. Coordinates, lot and house

- Plan metres as in Experiment 001: plan (x, y) maps to `Vector3(x, h, y)`, and north is −Z.
- `HousePlan` is unchanged: the 14 × 9 m house at (0, 0), and the YARD `Rect2(-7, -6, 28, 21)` as GridNav bounds.
- **LOT** (walkable property) = `Rect2(-4.5, -3.5, 23.0, 16.0)`. Outside it, but inside YARD, is the fog band where enemies spawn and arrive. The road (y 13.5–15) and the mailbox lie inside the fog by design.
- **Building grid** (construction resolution):
  - wall-like pieces: 1 m segments between integer plan points, along x or y;
  - free-standing objects: 0.5 m cells with 90° rotation.
  - Voxel damage resolution stays separate (0.1 m storage; see V's investigation).

## 6. Core numbers (`SurvivalTuning`, owner S; others read them)

**Time**
- `MINUTES_PER_SECOND = 1.0` game minutes per real second; the dev menu can scale this.
- The run starts on **Day 1, 07:00**.
- `night_amount()` is 0 between 07:00 and 19:30, ramps up between 19:30 and 21:00, is 1 between 21:00 and 05:00, and ramps down between 05:00 and 07:00 (smoothstep).
- Dawn event: 06:00. Dusk event: 20:00.
- Expeditions may depart between 05:00 and 18:00 and must return by 20:00. Otherwise the screen explains: "You'd be coming back in the dark".

**Stats** (0–100; per game hour)
- Decay while awake: hunger −1.25, hydration −1.9, energy −4.5.
- While asleep: hunger and hydration decay ×0.6, energy +12.5.
- Starting values: health 100, hunger 75, hydration 70, energy 85.
- Hunger ≤ 0 costs health −4/h; hydration ≤ 0 costs health −6/h. At ≤ 15 the HUD warns.
- Energy ≤ 15 sets move speed ×0.75; energy ≤ 0 sets ×0.6.
- Regeneration: +1.5/h awake and +3/h asleep, while hunger > 50 and hydration > 50.
- Death at health ≤ 0, unless `cheats.invulnerable`.

**Items** (`Items.DEFS`, owner S)
- `canned_food`: hunger +30, hydration +4
- `snacks`: hunger +12
- `water`: hydration +30
- `ammo`: 9 mm rounds
- `wood` (planks): cap 40, +20 per crate
- `nails`: cap 80, +40 per crate
- `scrap` (scrap metal): cap 20, +10 per crate
- `bandage`: health +20
- `medkit`: health +50
- Tools: `hammer` (needed to build and repair), `crowbar` (stockroom and forced-entry options), `flashlight` (needed for the Medical Clinic; lowers risk in dark places), `backpack` (+50 % loot).
- Tools are capped at 1 each (a second crowbar ends up in `left_behind`). Food, water, ammo and medical items have no cap.

**Starting inventory:** ammo 9, canned_food 3, snacks 2, water 4, wood 6, nails 12, bandage 1, hammer 1.

**Combat**
- One round per shot. Firing with 0 ammo plays `weapon/dry_fire` and toasts "Out of ammo".
- Enemy hit on the player: 12 × (1 + 0.1 × (invasion index − 1)).
- Psychos have HP 3 + floor((k − 1) / 2) and speed ×(1 + 0.05 (k − 1)) in invasion k.

**Invasions**
- The first is on **Day 3 at 22:00**, then every **3 days** (`INVASION_INTERVAL_DAYS`).
- Size: 3 + 2 (k − 1), capped at 11. Spawns are staggered 25–40 s apart from points in the fog band.
- It ends when every invader is dead, or at 06:00 when the survivors retreat into the fog. After that the next one is scheduled.
- From 12:00 on an invasion day the HUD warns: "Something is coming tonight."
- Non-invasion nights from Day 2: 35 % chance of one straggler at a random time between 23:00 and 03:00.
- No enemies by day.

**Construction** (V; costs are paid through `GameState.pay`)

| Piece | Cost | Notes |
|---|---|---|
| Wooden wall (per 1 m) | 4 wood + 6 nails | Voxel, 0.2 m thick, full height; click-drag for runs |
| Barricade (per 1 m) | 2 wood + 4 nails | Object, HP 12 |
| Door (in a 1 m wall segment) | 4 wood + 6 nails + 1 scrap | Object, HP 18; cuts the segment and installs a frame and leaf; the player opens and closes it |
| Doorway | free | Cuts a 1 m opening |
| Storage crate | 3 wood + 4 nails | Object; raises material caps |
| Rain collector | 2 wood + 2 nails + 3 scrap | Object; +1 water every dawn |
| Repair a 1 m section | 1 wood per 150 missing voxels + 1 nail per 60 (rounded up) | Objects: lost-HP fraction × cost, minimum 1 wood |
| Upgrade (metal sheathing, per 1 m section) | 3 scrap + 4 nails | Outer layer becomes hard metal |
| Demolish | free | Refunds half the cost of player-built pieces |

- Enemy wall damage is 1 per swing. Building and repairing need `hammer`.
- **Exit rule:** after any change, a walkable path must still exist from the bed to the lot edge, counting doors as passable and walls and barricades as blocking. Otherwise the change is refused with "That would seal the last way out."

## 7. Contracts (APIs)

Names are exact. "Stub" means the foundation has a minimal working version.

### 7.1 Survival (S): `src/survival/`

```gdscript
class_name Items            # static data
const DEFS := {id: {"name", "category": "food|water|ammo|material|medical|tool", "desc",
                     "hunger", "hydration", "health", "cap", "cap_per_crate"}}
static func name_of(id) -> String ; static func category(id) -> String ; static func ids(category := "") -> Array

class_name Inventory extends RefCounted
signal changed
var counts := {}            # id -> int (never negative, never non-int)
var storage_crates := 0     # set by the game from the world (affects caps)
func count(id) -> int ; func cap(id) -> int (0 = uncapped) ; func space_for(id) -> int
func add(id, n) -> int      # returns how many fit (rest is refused)
func remove(id, n) -> bool  # all-or-nothing
func has_all(cost: Dictionary) -> bool
func to_dict() -> Dictionary ; func from_dict(d) -> void

class_name GameState extends RefCounted
signal changed
signal died(cause: String)
var total_minutes: float    # since Day 1 00:00 (one clock; day and time derive from it)
var health, hunger, hydration, energy: float
var inventory: Inventory
var cheats := {"invulnerable": false, "unlimited": false}
var run := {"seed", "invasions_done", "invasion_active", "next_invasion_at", "expeditions", "log": []}
var dead := false ; var death_cause := ""
static func new_run(seed := 0) -> GameState
func day() -> int ; func minute_of_day() -> float ; func clock_text() -> String  # "07:45"
func night_amount() -> float ; func is_night() -> bool
func advance(minutes: float, asleep := false) -> Array  # applies decay exactly once; returns crossed events
     # [{"type": "dawn"|"dusk"|"invasion_due"|"new_day", "at": total_minutes}]
func can_pay(cost: Dictionary) -> bool ; func pay(cost: Dictionary) -> bool   # unlimited cheat: free
func use_ammo(n := 1) -> bool          # unlimited: always true, nothing deducted
func use_item(id) -> String            # eat/drink/heal; returns the feedback text, "" if not usable
func damage(amount: float, cause: String) -> void ; func heal(amount: float) -> void
func move_speed_scale() -> float
func plan_sleep(requested_minutes: float) -> Dictionary # {"minutes", "interrupted": bool, "reason"}
func until_morning_minutes() -> float  # minutes until the next 06:00
func invasion_due_soon() -> bool       # HUD warning window
func invasion_size() -> int ; func invasion_enemy_hp() -> int ; func invasion_speed_scale() -> float ; func enemy_damage() -> float
func start_invasion() -> void ; func end_invasion(survived: bool) -> void
func apply_expedition(result: Dictionary) -> Array    # applies once (guarded by result["id"])
# Added by S (see docs/experiment-002/survival.md): warnings(), can_sleep(), can_use(id), on_dawn(collectors, at),
# roll_straggler(day) -> ABSOLUTE total_minutes or -1, summary(), force_invasion_now(), next_invasion_text(),
# apply_expedition_report(result). Answer "invasion_due" with start_invasion(); call on_dawn per dawn event;
# plan_sleep may end early with reason "straggler"; a restored state never has an invasion running.
func days_survived() -> int
func to_dict() -> Dictionary ; static func from_dict(d: Dictionary) -> GameState  # null if invalid
```

### 7.2 Save (S): `src/save/`

```gdscript
class_name SaveGame
const PATH := "user://savegame.dat" ; const SCHEMA := 1
static var path_override := ""         # tests
static func write(data: Dictionary) -> Error  # adds schema/game_id/saved_at; tmp file + verify + rename; keeps .bak
static func read() -> Dictionary              # {"ok": bool, "error": String, "data": Dictionary}; falls back to .bak
static func info() -> Dictionary              # {"exists", "valid", "schema", "saved_at", "summary"}
static func delete_save() -> void
```

The game composes the save as `{"summary": {...}, "state": GameState.to_dict(), "world": HouseWorld.save_data(), "game": {player, director, ...}}`. Godot binary Variant (`store_var`, no objects) inside the file. Missing or invalid data → `ok: false` with a readable error, never a crash. A valid save needs `state` to be a Dictionary; `world` and `game` default to `{}`. `read()` may return `restored_from_backup: true` with a `backup_reason` (show it via `GameLaunch.notice`). `SaveGame.last_error` explains a failed `write()`.

**Limitation (by design):** you can't save while enemies are alive, and autosave only happens at safe transitions (wake / new day, return from an expedition, end of an invasion). Live encounters are therefore never saved. Invasions are scheduled by time, so a save before one restores it correctly.

### 7.3 World (V): `src/world/house_world.gd`

```gdscript
class_name HouseWorld extends Node3D
signal structure_changed           # voxels or objects changed (collision + nav already updated)
signal object_destroyed(kind: String, at: Vector3)
var grid: VoxelGrid ; var nav: GridNav ; var fx: VoxelFx ; var chunks: VoxelWorld
func setup(lighting: VoxelLighting) -> void   # call before add_child
func build_new() -> void                      # pristine house (+ starting front and back doors)
func save_data() -> Dictionary ; func load_data(d: Dictionary) -> bool   # instead of build_new
func update_view(player_pos: Vector3, camera: Camera3D, delta: float) -> void  # cutaway, roof fade
func aim_ray(from: Vector3, dir: Vector3) -> Vector3
func shoot(origin: Vector3, dir: Vector3, exclude: Array, muzzle := Vector3.INF) -> Dictionary
     # resolves voxels/objects/enemies/ground, carves, fx, tracer; returns {"kind", "pos", "collider"}
func enemy_strike(attacker_pos: Vector3, target: Vector2) -> void  # bite a wall or damage an object
func interactables() -> Array          # Node3D with interact_prompt() -> String and interact(game) -> void
func bed_position() -> Vector3
func count_objects(kind: String) -> int
func repair_all() -> void              # dev: restore design voxels and full object HP
func damage_summary() -> Dictionary    # {"missing_voxels": int, "damaged_objects": int}
func is_blocked(p: Vector2) -> bool    # body collision probe (tests)
func exit_path_exists() -> bool        # the exit rule
```

The interactable duck type is `interact_prompt() -> String` ("" hides) and `interact(game: Node) -> void`. The bed calls `game.open_sleep()`.

### 7.4 Build (V): `src/build/build_mode.gd`

```gdscript
class_name BuildMode extends Node3D
signal message(text: String, ok: bool)
signal changed
var active := false
func setup(world: HouseWorld, state: GameState, camera: Camera3D, player: Node3D) -> void
func set_active(on: bool) -> void    # shows and hides its own palette UI (uses UiTheme)
func handles_input() -> bool         # true while active (the game does not fire)
```

### 7.5 Props (P): `src/props/prop_kit.gd`

```gdscript
class_name PropKit
static func make(type: String, size: Vector3, opts := {}) -> Node3D   # visual only, no collision
     # origin = floor centre of the footprint; front faces -Z (north) before rotation;
     # opts: {"facing": "N|E|S|W", "seed": int, "damage": 0..1, "lit": bool}
static func has(type: String) -> bool
static func types() -> PackedStringArray
```

- **Types:**
  - every `HousePlan.FURNITURE` type and every `HousePlan.PROPS` type;
  - `door` (1 m frame + leaf; child `Leaf` pivoted at its hinge so V can swing it);
  - `barricade` (1 m planks; `damage` removes planks);
  - `crate`, `rain_collector`, `candle`, `lantern`, `bush`, `wall_ghost` (neutral block used for previews).
- **Emissive parts:** these respond to the shader instance parameter `lit` (0–1).

### 7.6 Audio (A): `src/audio/`

```gdscript
class_name Sfx                         # static
static func attach(root: Node) -> void # where players are created (scene root)
static func play(name: String, at: Variant = null, volume_db := 0.0) -> void  # Vector3 = positional
static func ui(name: String) -> void   # UI bus
static func music(name: String) -> void  # Music bus, looped; "" stops (crossfade)
static func names() -> PackedStringArray
class_name Ambience extends Node       # wind / night loops, distant noises in the fog
func set_night_amount(t: float) -> void ; func set_tension(t: float) -> void
```

- Buses (`default_bus_layout.tres`, lead): Master → SFX, UI (sends to SFX), Ambient, Music.
- `AssetResolver.get_audio(logical) -> AudioStream`:
  - override: `custom/audio/<logical>.ogg`;
  - fallback: `res://assets/audio/<dir>/template_<name>.ogg`;
  - invalid → `push_warning` + fallback.
- **Logical names** (A may add more, never rename these):
  - player: `player/footstep_1..4`, `player/hurt`, `player/eat`, `player/drink`, `player/bandage`, `player/sleep`, `player/death`
  - weapon: `weapon/handgun_fire`, `weapon/dry_fire`
  - impacts: `impact/wood`, `impact/plaster`, `impact/glass`, `impact/metal`, `impact/flesh`, `impact/ground`
  - building: `build/place`, `build/hammer`, `build/demolish`, `build/invalid`, `build/upgrade`
  - doors and structure: `door/open`, `door/close`, `door/bash`, `structure/break`, `structure/crumble`
  - enemies: `enemy/moan_1..2`, `enemy/attack`, `enemy/hit`, `enemy/death`
  - ambience: `ambient/wind_day`, `ambient/night`, `ambient/distant_1..3`
  - UI: `ui/click`, `ui/hover`, `ui/open`, `ui/close`, `ui/error`
  - stingers: `stinger/invasion`, `stinger/dawn`
  - music: `music/menu`

### 7.7 Expeditions (E): `src/expedition/`

```gdscript
class_name FogBoundary extends Node3D
signal exit_requested(at: Vector3)
const LOT := Rect2(-4.5, -3.5, 23.0, 16.0)
func setup(player: Node3D, env: Environment) -> void   # may enable/tune volumetric fog on env
func set_night_amount(t: float) -> void
func prompt_text() -> String          # non-empty while the player stands at the edge
func request_exit() -> void           # the game calls this when interact is pressed with a prompt
func return_point(at: Vector3) -> Vector3

class_name ExpeditionScreen extends CanvasLayer
signal finished(result: Dictionary)   # the game applies it exactly once
signal cancelled
func open(state: GameState) -> void
```

**Result:**

```
{"id": String (unique), "destination": id, "name": String, "minutes": int,
 "gained": {id: n}, "consumed": {id: n}, "lost": {id: n}, "left_behind": {id: n},
 "damage": float, "events": [String], "summary": String}
```

All counts are non-negative ints. `gained` already respects caps (the excess is in `left_behind`). `consumed` and `lost` never exceed what the player had.

### 7.8 UI (U): `src/ui/`, `src/menu/`

```gdscript
class_name UiTheme       # static: theme() -> Theme, colours, make_panel(), make_title(), make_button()
class_name GameSettings  # static: load_settings(), save_settings(), apply(); master/sfx/ambient/music (0..1), fullscreen
class_name GameHud extends CanvasLayer
  func setup(state: GameState) -> void ; func set_prompt(text: String) -> void
  func toast(text: String, kind := "info") -> void      # info | good | warn | bad
  func set_banner(text: String) -> void ; func set_mode(mode: String) -> void  # play | build
class_name PauseMenu extends CanvasLayer      # signals resume_requested, save_requested, main_menu_requested
  func open(save_block_reason: String) -> void ; func close() -> void ; var is_open
class_name SettingsPanel extends CanvasLayer  # signal closed ; func open()
class_name InventoryPanel extends CanvasLayer # signal closed ; func open(state: GameState)
class_name DevMenu extends CanvasLayer        # func setup(state: GameState, game: Node) ; func toggle()
class_name SleepDialog extends CanvasLayer    # signal sleep_chosen(minutes: float) ; signal closed ; func open(state)
class_name DeathScreen extends CanvasLayer    # signal main_menu_requested ; func open(days: int, cause: String)
class_name IntroOverlay extends CanvasLayer   # signal done ; func play()
class_name ConfirmDialog extends CanvasLayer  # signal answered(yes: bool) ; func ask(text, yes_text, no_text)
```

**Developer menu → game API** (duck-typed methods on the game root; G implements them):
`dev_spawn(n)`, `dev_trigger_invasion()`, `dev_repair_house()`, `dev_advance(minutes)`, `dev_skip_to(hour)`, `dev_set_time_scale(x)`, `dev_info() -> String`.

Stats, inventory and cheats are edited directly on `GameState`. The menu shows an always-visible **CHEATS ACTIVE** badge (via HUD or itself) while any cheat is on.

### 7.9 Game root (G): `src/game/`

`game.tscn` with `SurvivalGame` (Node3D). Public methods (duck-typed callers):

- `open_sleep()`, `toast(text, kind)`
- `can_save() -> String` ("" if allowed), `save_now() -> String`
- `request_main_menu()`
- the dev API (§7.8)
- a `debug_*` set for tests and the playtest

`GameLaunch` (static, `src/game/game_launch.gd`): `static var mode := "new"` (`"new"` | `"continue"`), and `static var notice := ""`: a one-shot message for the main menu (e.g. "The save could not be loaded: ..."), which the menu shows and clears.

## 8. Visual and UX direction

- **Look:** keep Experiment 001 Version A's atmosphere. Structure stays voxel (walls, floors, foundation, roof). Furniture, doors, lamps, appliances, storage, vegetation and props are conventional stylized meshes (B's best qualities). Characters keep the voxel rig.
- **No grid power:** the sirens went quiet and the grid failed. Night light comes from candles, battery lanterns, the gun-mounted light, moonlight and fog glow. There are no ceiling lights, so the fixtures stay dark.
- **One visual language:** dark translucent panels, warm off-white text, one amber accent (the siren), small caps headings, the same button style everywhere (`UiTheme`). Indicators are small and legible, with no big debug panels. The FPS line hides behind F3.
- **Fog:** a dense bank at the lot edge that hides everything beyond, day and night. The road and the driveway run into it.

## 9. Testing, captures and performance

- **Tests:**
  - run with `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd [-- --filter=<name>]`;
  - every module adds focused tests in its own folder;
  - `tests/test_versions_smoke.gd` (the three demos) must keep passing.
- **Rendering checks:**
  - `tools/capture.sh`, `tools/playtest.sh` and `tools/compare.sh` use Xvfb + lavapipe (software Vulkan, about 1 fps);
  - use `CAPTURE_ENGINE_ARGS="--fixed-fps 30"` and `LP_NUM_THREADS=1` so parallel agents don't starve each other.
- **Honesty:** never claim human play or real-GPU frame rates.
- **Godot:** 4.7.2 at `/usr/local/bin/godot`. In a new worktree, run `godot --headless --path . --import` once.

## 10. Out of scope for Experiment 002

Large outdoor areas, more house maps, classes, multiplayer, procedural worlds, structural integrity, multi-floor construction, power and plumbing networks, farming, complex crafting, weapon mods, skill trees, more enemy types, explosive enemies, traders/NPCs, story, cinematics, weather simulation, unlock progression. Also no exports or installers.
