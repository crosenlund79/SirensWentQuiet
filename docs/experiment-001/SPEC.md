# Experiment 001 — Shared specification and contracts

**Sirens Went Quiet** (working title) · Visual Technology Experiment 001: *three ways to build a destructible house*.

This file is the lead's shared spec. It keeps the three versions **comparable** while each one shows its technology at its best. The user's brief is the authority; this document translates it into concrete numbers and contracts. Engineering rules: `docs/GODOT_CLAUDE_GUIDELINES.md`.

| Version | Folder | Scene (exact path) | Technique |
|---|---|---|---|
| A | `src/voxel/` | `res://src/voxel/voxel_demo.tscn` | True volumetric voxels, chunked mesh rebuilds |
| B | `src/modular/` | `res://src/modular/modular_demo.tscn` | Grid-aligned reusable 3D modules with damage states |
| C | `src/illustrated/` | `res://src/illustrated/illustrated_demo.tscn` | Illustrated top-down 2D (ink-and-wash style of The Witchening Tales) |

The launcher (`res://src/launcher/launcher.tscn`) opens each scene. **Godot 4.7** (4.7.2 stable), **Forward+** renderer, window 1600×900, stretch `canvas_items`/`expand`.

## 1. The shared scenario

### House
`src/common/house_plan.gd` (`HousePlan`) is the single floor plan: 14 m × 9 m modern single-storey wooden house, five rooms (bedroom, bathroom, kitchen, living room, utility), 2 exterior doors, 3 interior doors, an open kitchen–living connection, 8 windows, furniture, a small yard (28 m × 21 m) with a few props (abandoned car, dead trees, tipped bin, dead streetlight, road strip). **Build every version from this data** (iterate `WALLS`, `OPENINGS`, `FURNITURE`, `PROPS`, `LIGHTS`, `ROOMS`) rather than re-typing coordinates, so layouts stay identical. You may add purely decorative detail (clutter, picture frames, debris, grass tufts) that doesn't block movement.

- Units: meters. Plan X = east, plan Y = south. North is screen-up in all versions.
- 3D mapping: plan `(x, y)` → `Vector3(x, height, y)`; north = −Z.
- 2D mapping: plan `(x, y)` → `Vector2(x, y) * PX_PER_M` (choose `PX_PER_M`, e.g. 64).
- Wall height 2.6 m; exterior walls 0.3 m thick, interior 0.2 m; door openings 1 m × 2.1 m (open doorways; leaves, if drawn, stand open and never block); window sill 0.9 m (bathroom 1.4 m), head 2.1 m.
- Furniture with `height >= Tuning.TALL_THRESHOLD` (1.2 m) stops bullets; lower pieces are shot over. Pieces with `blocks: false` (rugs, deck, paths) never collide.
- Furniture is **not** required to be destructible.

### Player
WASD movement (`move_*` actions), mouse aiming, hold LMB (`fire`) to shoot one handgun at `Tuning.FIRE_INTERVAL`, unlimited ammo, hitscan to `Tuning.SHOT_RANGE`. Speed `Tuning.PLAYER_SPEED` (4 m/s), radius 0.25 m. The player **cannot die** and doesn't collide with enemies (no getting trapped). Visible feedback: muzzle flash, tracer, recoil kick, body turns toward the aim, simple walk motion (bob/sway or limb swing). A distinct readable silhouette: dark jacket with one warm accent colour, a backpack strap or similar. **At night the player carries a weapon light** (cone toward the aim) plus a faint self-light so they stay readable. That's presentation, not a new mechanic.

### Enemies ("psychos")
One type: disturbed-looking ordinary people (hunched, shambling, torn everyday modern clothes, pale skin). The look is deliberately ambiguous: not zombies, monsters or soldiers. `Tuning.ENEMY_HP` 3, speed 1.4 m/s (slow), radius 0.25 m. They spawn outside via `EnemySpawner` (first after 2 s, then every 4 s, max 6 alive, ≥ 7 m from the player at one of `HousePlan.SPAWN_POINTS`), walk toward the player, and swing harmlessly when within reach (show a swing, maybe a tiny camera nudge, **no damage**). Hit reaction: flash, short stagger (`ENEMY_HIT_STAGGER`), knockback (`ENEMY_KNOCKBACK`). Death: visibly collapse, stay `ENEMY_CORPSE_TIME`, then fade or sink away (no collision while dead). Enemies collide with walls/furniture and with each other.

**Movement decisions come from the shared `PursuitBrain`** (one per enemy, on the version's `GridNav`). Each physics frame:
```gdscript
var r := brain.update(delta, my_plan_pos, player_plan_pos)
# r.move: unit Vector2 in plan space (multiply by Tuning.ENEMY_SPEED); r.face: facing
# r.swing: "" | "player" | "wall"   (reported once per ENEMY_ATTACK_INTERVAL)
# r.target: plan point being swung at. For "wall": damage your wall at r.target
#           by Tuning.ENEMY_WALL_DAMAGE (voxel: carve a small bite at a random
#           height 0.2–1.5 m around that point, aimed at opening a passage).
```
Do not write other AI. No tactics, cover, formations or extra sensing.

### Navigation and destruction contract (important)
`GridNav` (0.25 m cells over `HousePlan.YARD`) stores a **raw** state per cell: `OPEN`, `WALL` (destructible), `SOLID` (furniture/props). Initialise with `HousePlan.rasterize_into(nav)`. When your geometry changes:
1. Update the raw cells covering the changed area **from your real geometry** (B/C: a destroyed section's `span_rect` → `OPEN`; A: for each affected cell, `WALL` if any wall voxel remains between 0.15 m and `Tuning.CLEARANCE_HEIGHT` (1.6 m) in the voxel columns whose centres fall inside the cell's 0.25 m footprint, else `OPEN`; never overwrite `SOLID`. *As built: Version A samples the whole footprint, because the single cell-centre column misses most of a 3-voxel wall and could open nav while siding still blocks.*)
2. Call `nav.refresh_region(rect)`. Pursuers repath at once.
3. Collision must change in the same frame (no invisible barriers left; no open nav over remaining collision).

Sampling is **centre-of-cell**: cell (i, j) is centred at `YARD.position + (i, j) * 0.25`. A body needs a cell plus its 8 neighbours clear, so a passage must be about 0.6 m wide and 1.6 m tall. Character collision shapes: radius 0.25, top at 1.6 m (3D: a capsule or cylinder from about 0.05 to 1.6 m, so they can step through ragged holes whose bottom edge is near the floor). Visual height is still about 1.75 m.

**Wall toughness should feel comparable**: a 1 m section takes about 10 handgun hits (`Tuning.WALL_SECTION_HP`) in B and C. In A, opening a walk-through hole should take roughly 10–25 well-placed shots, and single shots must visibly bite chunks out. Windows are walls with glass: the first hits shatter the glass visibly, and the window section then takes damage like a wall. Floors don't need to be destructible.

### Weapon and hits
Hitscan from the muzzle toward the aim point and beyond. 2D: straight line in plan space. 3D: aim ray from the camera through the cursor against **visible** geometry and enemies (ignore anything your cutaway currently hides). The bullet goes from the muzzle (`Tuning.MUZZLE_HEIGHT`) toward that 3D point, so aiming low or high on a wall chooses the impact height. Hits: the first enemy, wall, tall furniture or prop along the ray. Enemy hit → `SHOT_DAMAGE`. Wall hit → version-specific damage at the impact point. Impact feedback must be material-appropriate (wood splinters, plaster dust, glass, sparks on metal, dust on ground).

### Day / night (comparison tool, not a cycle)
- **Day:** overcast late afternoon. Cool, slightly desaturated, soft directional shadows, quiet and uneasy. All interior fixtures off.
- **Night:** moonlit blue-black ambient. `HousePlan.LIGHTS` with `night_on` glow warm (the bathroom one flickers via summed sines), plus the player's weapon light. Dark but **playable**: walls, enemies and openings stay readable.
- The `DemoHud` owns the state: connect `night_changed(night)` and also read `hud.is_night` at start. Transitions may tween over about 0.5 s.

### Camera
- **A and B (identical for comparability):** perspective `Camera3D`, vertical FOV 40°, pitch −56° (looking north, yaw 0), following the player at distance 20 m (look target = player at 1 m height), smooth follow, zoom with `zoom_in`/`zoom_out` between 11 m and 32 m. The interior must stay readable: no roof while the player is inside or always cut away, plus fading or cutting walls between camera and player (e.g. a screen-space circular cutout or height cutaway). Choose what makes your technology look best.
- **C:** strict top-down `Camera2D`, smooth follow, default view about 22 m wide, zoom range about 12–34 m wide.

### HUD and controls (shared)
Every version adds `DemoHud.new()` (set `title`, optional `subtitle`, optional `stats_text`, e.g. voxel count or rebuild ms). It shows the controls reference, FPS and draw calls, and handles **N** day/night, **R** reset (reload scene), **Esc** back to the launcher, **H** help, **F3** stats. Versions handle WASD, mouse, LMB and zoom themselves. No other HUD: no health bars, inventory or ammo.

## 2. Shared code (lead-owned, read-only for version agents)

| File | What it gives you |
|---|---|
| `src/common/tuning.gd` (`Tuning`) | All shared numbers (speeds, HP, intervals, spawn rhythm) |
| `src/common/house_plan.gd` (`HousePlan`) | Floor plan data + helpers: `wall_rect`, `span_rect`, `wall_spans`, `openings_on`, `window_sill`, `room_at`, `rasterize_into` |
| `src/common/grid_nav.gd` (`GridNav`) | Raw cells, `mark_rect`, `cells_in_rect`, `refresh_region`, `find_path`, `is_walkable`, `segment_walkable`, `segment_clear` |
| `src/common/pursuit_brain.gd` (`PursuitBrain`) | Enemy decisions (above) |
| `src/common/enemy_spawner.gd` (`EnemySpawner`) | `tick(delta, alive, player_pos) -> Vector2 or null` |
| `src/common/asset_resolver.gd` (`AssetResolver`) | `get_texture("voxel/wood_planks", mipmaps)`: user override or template fallback |
| `src/common/demo_hud.gd` (`DemoHud`) | Shared HUD, day/night state, reset, launcher, crosshair cursor |

Need a change in shared code? **Don't edit it.** Note it in your final report (or work around it locally in your folder). The lead integrates.

Physics layers (same names in 2D and 3D): 1 `environment` (floors, tall furniture, props), 2 `walls` (destructible), 3 `player`, 4 `enemies`, 5 `low_obstacles` (furniture lower than 1.2 m: blocks bodies, not bullets). Bullets: mask 1|2|4. Player body mask 1|2|5. Enemy body mask 1|2|4|5.

## 3. Smoke-test contract

`tests/test_versions_smoke.gd` runs the same checks on every version: launch, movement, day/night, killing an enemy, shooting a walk-through hole into the south wall at plan (8.5, 9.0), collision and navigation updating, the player walking through it, an enemy entering through it rather than the front door, reset and return to the launcher. Each version's **scene root** implements these methods, with positions in plan meters:

```gdscript
func debug_hud() -> DemoHud
func debug_player_pos() -> Vector2
func debug_teleport_player(p: Vector2) -> void
func debug_fire_at(target: Vector2, height: float) -> void   # one real shot from the player's gun, now, ignoring the fire cooldown
func debug_set_spawning(on: bool) -> void
func debug_spawn_enemy(p: Vector2) -> Node
func debug_living_enemies() -> int
func debug_enemy_positions() -> PackedVector2Array          # living enemies only
func debug_nav() -> GridNav
func debug_blocked_at(p: Vector2) -> bool                   # real collision blocks a short horizontal probe through p at waist height
func debug_is_night() -> bool                               # the version's applied lighting state
```
Versions must run **headless without errors** (no rendering there: guard viewport-texture reads; particles and lights are fine).

## 4. Assets and art

- Claude-made art: `assets/graphics/<version>/template_<name>.png`. Load **only** via `AssetResolver.get_texture("<version>/<name>")`, so `custom/graphics/<version>/<name>.png` overrides it after a game restart, in the project or next to an exported Windows/Linux build. Never write into `custom/`.
- Generator scripts for template art live in `tools/art/<version>/` (Python 3 + numpy + Pillow are available; no scipy). Commit the generated PNGs **and** their `.import` files. For textures sampled in 3D, set `mipmaps/generate=true` in the `.import` file and reimport. Overrides get mipmaps through `get_texture(name, true)`.
- Procedural meshes and shaders built in code are fine. Keep the number of PNG files modest: a convincing small sample, not hundreds of assets. Document the list of logical names in your version's README.
- Reference style (C mainly, inspiration for all): `/home/user/crosenlund79/phasmoonspeed/docs/VISUAL_STYLE_DNA.md` and `tools/art/*.py` in that read-only checkout. Don't modify it.

## 5. Commands

```bash
# after adding scripts with class_name or new PNGs:
godot --headless --path . --import
# all tests (or add -- --filter=voxel / modular / illustrated)
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
# real-renderer screenshot through the game camera (software Vulkan under Xvfb; slow but faithful)
tools/capture.sh res://src/voxel/voxel_demo.tscn /abs/path/shot.png 6 --night --hide-help
```
`tools/capture.sh` passes extra args to the scene (`OS.get_cmdline_user_args()`). Versions may add their own `--scenario=<name>` (e.g. pre-damaged walls, enemies placed, camera framing) to show off destruction in screenshots. Software rendering is slow, so judge performance by draw calls, mesh sizes and rebuild timings, not by the FPS shown under lavapipe.

## 5b. Performance

The house is small. Target a solid 60 fps on a typical desktop GPU. Voxels: chunked `ArrayMesh` + per-chunk collision rebuilt only for dirty chunks, no node per voxel, and no thousands of rigid bodies (debris is particles or a capped handful of short-lived pieces). Show a useful number in `stats_text`.

## 6. Out of scope (from the user's brief)

Structural integrity, construction or building UI, moving walls, crafting, inventory, survival stats, save/load, progression, extra enemy types, waves or hordes, advanced AI, multiplayer, **sound or music**, narrative, large outdoor areas, procedural houses, executables and exports. No Autoload singletons. No new gameplay mechanics in the name of creative freedom: creativity goes into rendering, materials, lighting, destruction feel and readability.
