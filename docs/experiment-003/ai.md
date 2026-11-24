# Experiment 003 — Enemies, difficulty and invasions (AI)

Owner: AI. Code: `src/ai/` (the body, behaviours, archetype data, looks, the weighted nav layer, the preview harness), `src/common/pursuit_brain.gd`, `src/game/invasion_director.gd`, `src/game/enemy_roster.gd`. Tests: `tests/ai/`, `tests/common/test_pursuit_brain.gd`, `tests/game/test_game_helpers.gd`. Contracts: SPEC-003 §5 and §8. It extends the invasion rules of `docs/experiment-002/game.md`, which still hold where this file doesn't change them.

No Autoloads. The Experiment 001 voxel demo still uses `VoxelEnemy`, unchanged.

## Architecture

One body, one shared behaviour core, archetypes as data plus a small hook.

| Piece | File | Job |
|---|---|---|
| `AIEnemy` | `src/ai/ai_enemy.gd` | The one enemy body (CharacterBody3D). Movement, swing timing (wind-up, then impact), damage, stagger, knockback, death and corpse, retreat, wave membership (meta `invader`). Signals: `wall_swing`, `player_swing`, `fuse_started`, `detonated`, `fizzled`, `died`. |
| `EnemyBehaviour` | `src/ai/enemy_behaviour.gd` | The per-archetype hook: `configure`, `goal`, `think`, `on_death`. The base class is the **chase** behaviour (psycho, runner, brute): hunt the player. |
| Bomber hook | `src/ai/bomber_behaviour.gd` | Target a weak point, fuse, blast; fizzle or pop when killed early. |
| `EnemyDefs` | `src/ai/enemy_defs.gd` | Archetype data and `stats(kind, level, invasion)` (difficulty and invasion scaling), blast fall-off. |
| `PursuitBrain` | `src/common/pursuit_brain.gd` | Shared navigation: path on the `GridNav`, bash walls on the path, swing at the goal, two stuck rules, repath on every nav revision. Per-instance tuning. |
| `WeightedNav` | `src/ai/weighted_nav.gd` | A path planner over the shared `GridNav` with the archetype's own bash cost. |
| `EnemyLooks` | `src/ai/enemy_looks.gd` + `shaders/` | Placeholder looks: the `VoxelRig` scaled and tinted, the brute's club, the bomber's pack and light. |
| Roster | `src/game/enemy_roster.gd` | The enemies in the world: `spawn_type`, moans, the dawn retreat, brute strikes, blasts between enemies, signals for the game. |
| Director | `src/game/invasion_director.gd` | Threat-budget waves, groups, spawn points, stragglers. |
| Preview | `src/ai/ai_preview.tscn` | The harness (see below). |

**Shared behaviours** (all archetypes, through the body and the brain):

- **Target selection:** the behaviour's `goal()`. The player for chasers; a defence for the bomber; a fog point when retreating.
- **Navigation:** `PursuitBrain` on the world's `GridNav`, with a `WeightedNav` planner when the archetype's bash weight differs from the shared 12.
- **Obstacles:** raw WALL cells (walls, closed doors, barricades) are bashable; SOLID cells (furniture, props, crates) are never entered.
- **Attacking doors, barricades and walls:** a wall swing reaches the game as `roster.wall_swing`, and the game calls `world.enemy_strike` once per signal. The roster fires it `wall_strikes` times per swing (brute 3).
- **Reacting to breaches:** the brain repaths at once when `nav.revision` changes, so a new opening or a door being opened is used immediately (test `test_ai_chaser_uses_a_new_opening_at_once`).
- **Attacking the player:** `player_swing` once per `attack_interval` within `attack_range` and line of sight.
- **Damage, stagger, death:** `take_hit(dir)` is one bullet or pellet (from `HouseWorld.shoot`). `take_damage(n, dir, cause)` applies the archetype's knockback and stagger multipliers. Death collapses the rig; the corpse fades after `Tuning.ENEMY_CORPSE_TIME`.
- **Waves:** the director builds them and the roster spawns them, with the meta `invader` = true.

`AIEnemy` **extends `VoxelEnemy`** only for type compatibility with the Experiment 002 code: `HouseWorld.shoot`'s `col is VoxelEnemy`, the game's typed `_on_wall_swing(e: VoxelEnemy, …)` handlers and `is VoxelEnemy` checks. It overrides `_ready`, `_physics_process`, `take_hit` and `_die`; VoxelEnemy's own brain setup and `_unstick` are unused. Once those type checks are duck-typed, it can derive from `CharacterBody3D` directly.

### The stuck problem (BACKLOG) — fixed in PursuitBrain

The old rule saw "stuck" only when the body stopped moving. In a half-open gap (cells OPEN but not walkable), the body bounces between the jambs, so it never stood still and never bashed.

The new **progress rule** acts when the remaining path to the goal hasn't shrunk by 0.3 m for 2.5 s, the goal hasn't moved by more than 1 m, and nothing was swung at. The brain then bashes the nearest raw WALL within reach + 0.25 m. If there is none, it repaths and sidesteps for 0.45 s. `result["stalled"]` reports it; the bomber uses it as its own fallback.

The position rule stays. A moving goal resets the baseline, so chasing a player along a wall never triggers a wall swing (tested). The new test `test_progress_rule_bashes_out_of_an_oscillating_half_open_gap` **fails on the old brain** and passes on the new one. The existing brain tests still pass.

Brain tuning per instance: `speed`, `attack_range`, `attack_interval`, `reach`, `attack_goal` (false: walk there and report `arrived`), `arrive_radius`, `bash` and `planner`. The defaults are the Experiment 002 psycho, so the Experiment 001 demos behave as before.

### Bash cost per archetype (WeightedNav)

`GridNav` gives every bashable cell the weight 12. `WeightedNav.for_nav(nav, w)` keeps a second `AStarGrid2D` with weight `w` on the same bashable cells, so walkable and solid cells stay identical.

- There is one layer per (nav, weight), stored in the nav's metadata and holding the nav only weakly.
- It follows `nav.revision` incrementally: changed rows are found by comparing row slices of the raw occupancy, and only the 3×3 neighbourhoods of changed cells are recomputed. It reads `GridNav._raw` through `get()`, and rebuilds fully if that isn't available (see Requests).
- The runner uses 60, so it detours to an open door or a hole when one exists. The brute uses 4, so it goes straight through. The psycho uses the shared nav (12).

## Archetypes (`EnemyDefs.DEFS`)

| | psycho | runner | brute | bomber |
|---|---|---|---|---|
| Cost (threat budget) | 1 | 1.5 | 3 | 4 |
| Speed (m/s) | 1.4 | 2.6 | 1.0 | 1.6 |
| HP (Normal, invasion 1) | 3 | 2 | 8 | 2 |
| Behaviour | chase | chase | chase | bomber |
| Bash weight (shared = 12) | 12 | 60 (detours to openings) | 4 (bashes through) | 40 (never bashes) |
| Strikes per wall/door/barricade swing | 1 | 1 | **3** | 0 |
| Player damage × `state.enemy_damage()` | 1.0 | 0.6 | 1.8 | 0 (the blast instead) |
| Attack range / interval | 0.85 m / 1.1 s | 0.85 m / 0.75 s | 1.0 m / 1.6 s | — |
| Knockback / stagger multiplier | 1 / 1 | 1.4 / 1.2 | **0.12 / 0.3** | 0.8 / 0.8 |
| Collision radius | 0.25 | 0.22 | 0.29 | 0.25 |
| Look | Experiment 002 (looks A–D) | look B, 0.8 × 1.04 × 0.8, pale tint | look C, ×1.4 / 1.28, charcoal tint, plank club | look D, khaki tint, glowing pack and pulsing light |
| X-ray silhouette through walls | pale red | pale blue | red | bright orange |
| Moans | yes | yes | yes | no (it beeps) |

The psycho keeps Experiment 002's feel and numbers exactly: same speed, HP, attack range and interval, bash weight and single strike, and the same `VoxelRig` material.

**Scaling** (`EnemyDefs.stats(kind, level, invasion)`):

- **HP:** `round(hp × Difficulty.enemy_hp × (1 + 0.25 × floor((invasion − 1) / 2)))`, at least 1. That is the same scale as K's `state.enemy_hp_scale()`. The psycho on Normal gets 3, 3, 4, 4, 5 …, exactly Experiment 002's progression.
  - Normal, invasion 1: psycho 3, runner 2, brute 8, bomber 2.
  - Hard, invasion 1: 4, 3, 10, 3. Easy: 2, 2, 6, 2.
- **Speed:** ×{easy 0.92, normal 1.0, hard 1.08} (or a `Difficulty` key `enemy_speed`, if K adds one) × (1 + 0.05 per invasion, at most +30 %). The per-invasion step is Experiment 002's.
- **Melee damage:** `state.enemy_damage()` (K: it already includes the difficulty and the invasion) × the archetype's `damage_scale`. The vest applies inside `state.damage`.
- **Blast:** `blast_damage` = 60 × `Difficulty.enemy_damage` (Easy 42, Normal 60, Hard 78) at the centre, falling linearly to 0 at 4 m (`EnemyDefs.blast_damage_at(dist, peak, reach)`). The vest applies inside `state.damage(…, "blast")`.

## The suicide bomber

It **ignores the player**: its brain has `attack_goal = false` and `bash = false`, and its goal is never the player.

1. **Target.** It calls `world.weak_points(from, player_pos)`. The player's position only feeds C's proximity bonus, which raises defences near the player; the player is never a target. It takes the first usable entry. C's entries carry the stand point on the outside face (`pos`), the `target`, `seg` and `object`. It skips:
   - an open or broken object;
   - a walk-through target;
   - a stand point inside the house;
   - a stand point its planner can't reach;
   - a target another bomber has claimed.

   It **commits** to the target and re-picks only if the target is destroyed or becomes walk-through before it arrives (tested). The foundation format (`pos` = the target) is still understood as a fallback.
2. **Fuse.** At the stand point it stops and faces the target. `fuse_started(enemy, at, 2.5)` fires (the roster forwards it for the HUD). The pack light pulses faster and faster (3 → 11 Hz), the rig trembles, and a beep plays through `Sfx.play` with gaps shrinking from 0.7 s to 0.25 s.
   - The sound name is `enemy/bomber_fuse` once it exists. Until then it uses the existing `ui/error` (see Requests).
   - If it stalls twice (5 s) without reaching the face but is within 1.3 m of a wall, it fuses at that wall instead.
3. **Blast.** `world.explode(stand point at 1.0 m, 1.6, 24)`, C's recommended use: one blast breaches a wooden or house wall or a wooden door; stone needs two. The world draws the flash, fireball, debris, dust and scorch and plays its own sounds; `enemy/bomber_blast` is added if it exists. The result is kept in `behaviour.last_blast` (`breach`, `opened`, …). Then `detonated(at, 4.0, blast_damage)` fires.

   The roster hurts the other enemies: 8 hits at the centre, falling linearly to 0 at 4 m. A psycho 1 m away dies; a brute is hurt. The game hurts the player (Integration). The bomber vanishes.
4. **Killed early** (the design choice):
   - **before the fuse is lit, it fizzles**: sparks and smoke, `fizzled(enemy, at)`, and **no damage at all**;
   - **while the fuse burns, it pops**: `detonated(at, 1.6, 15 × enemy_damage)` with **no structural damage**, and 2 hits at the centre to other enemies.

   Shooting it early is always worth it. `roster.kill_all()` (dev) kills it quietly: no pop.
5. **Fair warning:** the glowing orange pack and pulsing light (very visible at night), a bright orange x-ray silhouette through walls, no moaning, the beeping fuse, `fuse_started` for a HUD warning, and `roster.enemy_spawned(e, "bomber")` for an early "bomber!" notice.

Its targeting is demonstrably different. In `test_ai_bomber_goes_for_a_wall_not_the_player_unlike_a_psycho`, with both doors open and the player 0.1 m from its path, the bomber walks past and blows the world's first usable weak point, a weakened wall. Afterwards `breach` is true, the target point is walk-through, and a walk-only path leads in. A psycho from the same spot attacks the player.

On the intact house the world ranks the closed front door first. One blast destroys the door and opens the doorway; the wooden-framed wall beside it holds.

## Director (`src/game/invasion_director.gd`)

- **Budget** = `Difficulty.threat_budget` + `threat_budget_step` × (invasion − 1): Easy 3 + 1.5k, Normal 4 + 2.5k, Hard 5 + 3.5k.
- **Composition** (`compose(level, invasion, seed)`, pure and deterministic):
  - **Order:** one psycho first; then weighted picks (psycho 3, runner 2, brute 1.4, bomber 1.2) that fit the budget left; then, from invasion 2, leftover budget upgrades psychos to runners.
  - **Unlocks:** runners from `special_from_invasion`, brutes from max(`special_from_invasion`, 2) so the very first wave never has one, bombers from `bomber_from_invasion` (Easy 4, Normal 3, Hard 2).
  - **Caps:** at most 1 + (k − first) / 2 brutes and the same for bombers. The head count is at most Experiment 002's invasion size × `enemy_count` (Easy 2, Normal 3, Hard 4 in invasion 1), so **the first waves stay small**.
  - **Placement:** bombers never come in the first third of a wave.
- **Groups:** one enemy alone first, then pairs (waves of up to 7) or threes. Members of a group arrive 1.2–2.6 s apart from one shared fog point, so they come together. Groups are 25–40 real seconds apart (`gap_override` shortens this).
- **Spawn points, the dawn retreat and stragglers:** unchanged (fog band, at least 7 m from the player; stragglers are lone psychos).
- **The Experiment 002 call `begin(count, hp, speed, seed)` still works:** `count` psychos, one at a time.

Examples (seed 1123; the cost is in brackets):

| Level | Invasion | Budget | Head cap | Wave |
|---|---|---|---|---|
| easy | 1 | 3.0 | 2 | 2 psycho (2.0) |
| easy | 3 | 6.0 | 5 | 3 psycho, 1 brute (6.0) |
| easy | 4 | 7.5 | 7 | 2 psycho, 1 runner, 1 bomber (7.5) |
| normal | 1 | 4.0 | 3 | 1 psycho, 2 runner (4.0) |
| normal | 2 | 6.5 | 5 | 2 psycho, 1 runner, 1 brute (6.5) |
| normal | 4 | 11.5 | 9 | 3 psycho, 1 runner, 1 brute, 1 bomber (11.5) |
| normal | 6 | 16.5 | 13 | 4 psycho, 1 runner, 1 brute, 2 bomber (16.5) |
| hard | 1 | 5.0 | 4 | 4 psycho (4.0) |
| hard | 3 | 12.0 | 9 | 5 psycho, 1 brute, 1 bomber (12.0) |
| hard | 6 | 22.5 | 14 | 4 psycho, 3 runner, 2 brute, 2 bomber (22.5) |

Share of waves with a bomber over 200 seeds, by invasion 1–7:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Easy | 0 % | 0 % | 0 % | 30 % | 52 % | 53 % | 61 % |
| Normal | 0 % | 0 % | 45 % | 55 % | 65 % | 72 % | 80 % |
| Hard | 0 % | 38 % | 63 % | 64 % | 78 % | 89 % | 91 % |

API:

- `begin_wave(level, invasion, seed, kinds := [])`: `kinds` is a chosen composition (dev); unknown kinds are dropped.
- `tick(delta) -> int` and `tick_kinds(delta) -> Array` (kinds to spawn now; also `last_kinds`).
- `pick_spawn(player_pos)` and `spawn_opts(kind)` (roster options: level, invasion, invader).
- `wave`, `groups`, `budget`, `level`, `invasion`, `total`, `spawned`, `active`, `remaining_to_spawn()`, `all_spawned()`, `hurry(s)`, `gap_override`, `finish()`.
- Statics: `threat_budget`, `max_count`, `allowed`, `first_invasion`, `kind_cap`, `wave_cost`, `group_sizes`, `fog_points`, `nearest_fog_points`, `is_invasion_night`, `straggler_at`.

## Roster (`src/game/enemy_roster.gd`)

**The Experiment 002 API is unchanged:** `setup`, `spawn(at, hp, speed, invader) -> VoxelEnemy` (a psycho), `living()`, `invaders_alive()`, `present()`, `positions()`, `threats()`, `retreat_all(points)`, `kill_all()`, `is_threat(e)`, `wall_swing(enemy, target)` and `player_swing(enemy)`.

New:

- `spawn_type(kind, at, opts := {}) -> Node`. `opts`: `level` and `invasion` (default: the roster's `level` / `invasion` vars), `hp`, `speed` (scale), `invader`, `look`, `facing`.
- `living_by_kind() -> Dictionary`.
- Signals:
  - `enemy_spawned(enemy, kind)`;
  - `enemy_died(enemy, kind, cause)`, where `cause` is `shot`, `blast`, `detonated` or `quiet`;
  - `fuse_started(enemy, at, seconds)`;
  - `detonated(at, radius, damage)`.
- **`wall_swing` fires once per strike**, so a brute's swing is three `world.enemy_strike` calls with no change in the game.
  - This is the one way the brute is counted: the game keeps calling `world.enemy_strike(e.global_position, target)` with the default strength 1.
  - Don't also pass C's `strength` 3, or a brute hits 3 × 3.
- Blasts damage the other enemies before `detonated` is re-emitted.
- At dawn a bomber whose fuse burns doesn't retreat: it is committed.

## Integration (Phase B: exact calls)

The game works as it is: every enemy is now an `AIEnemy` psycho through `roster.spawn`, and all 22 game tests pass. To use the archetypes and the director, change `src/game/survival_game.gd` as follows.

1. **Roster defaults** (at assembly and whenever the invasion index changes; on load):
   ```gdscript
   roster.level = state.difficulty
   roster.invasion = state.invasion_index()
   ```
2. **Start an invasion** (`_start_invasion`): replace `director.begin(state.invasion_size(), state.invasion_enemy_hp(), state.invasion_speed_scale(), seed)` with
   ```gdscript
   director.begin_wave(state.difficulty, state.invasion_index(), seed)
   ```
   `tests/game/test_survival_game.gd` line ~420 then compares `debug_director().total` with `debug_director().wave.size()` instead of `s.invasion_size()`.
3. **Spawn the wave** (`_run_director`):
   ```gdscript
   for k in director.tick_kinds(delta):
       roster.spawn_type(k, director.pick_spawn(player.plan_pos()), director.spawn_opts(k))
   ```
4. **Player hits** (`_on_player_swing(e)`):
   ```gdscript
   var kind: String = e.kind if e is AIEnemy else "psycho"
   var scale: float = e.damage_scale if e is AIEnemy else 1.0
   state.damage(state.enemy_damage() * scale, kind)
   ```
5. **Blasts** (new): `roster.detonated.connect(_on_blast)`:
   ```gdscript
   func _on_blast(at: Vector3, radius: float, damage: float) -> void:
       var d := Vector2(at.x, at.z).distance_to(player.plan_pos())
       var hurt := EnemyDefs.blast_damage_at(d, damage, radius)
       if hurt > 0.0:
           state.damage(hurt, "blast")      # the vest applies inside
       camera.nudge(2.0 if radius > 2.0 else 1.0)
   ```
   Enemies killed by a blast arrive as `roster.enemy_died(e, kind, "blast")`; play `enemy/death` there if wanted (`_fire` only covers shots).
6. **HUD warnings** (new):
   - `roster.fuse_started.connect(func(e, at, s): hud.warn(...))`, a "Bomber!" banner for `s` seconds;
   - optionally `roster.enemy_spawned` with kind `"bomber"` for an early notice.
7. **F10:**
   - each type: `roster.spawn_type(kind, p, {"level": state.difficulty, "invasion": state.invasion_index()})` with `p` from `Director.nearest_fog_points(player.plan_pos(), 6.0)`;
   - an invasion with a chosen composition: `state.start_invasion()` (or `force_invasion_now()`), then `director.begin_wave(state.difficulty, state.invasion_index(), seed, ["bomber", "brute", …])`;
   - `dev_info()` can show `roster.living_by_kind()` and `director.wave`.
8. **Stragglers** may stay `roster.spawn(...)` (psychos), or use `roster.spawn_type("psycho", at, {"level": …, "invasion": …})` to scale them.
9. **Unchanged:** `_fire`'s `e is VoxelEnemy`, the banner count (`director.remaining_to_spawn() + roster.invaders_alive()`), the dawn retreat, `kill_all`, `debug_spawn_enemy`, saving (live encounters are never saved).

Nothing else is needed: the lighting's `night` reaches the archetype materials through `EnemyLooks.sync_night()`, which the enemies call themselves.

## Preview harness

`godot --path . res://src/ai/ai_preview.tscn` loads the real `HouseWorld`, the player (invulnerable: swings are only counted), the real roster and director.

| Keys | Action |
|---|---|
| WASD, mouse, LMB | Move, aim, shoot (`world.shoot`) |
| 1, 2, 3, 4 | Spawn a psycho, runner, brute or bomber at the mouse (or the nearest fog point if the mouse is on the house) |
| F1, F2, F3 | A wave on Easy, Normal or Hard |
| + / − | Invasion index |
| G | Fast waves (4–6 s groups) |
| O | Open or close the doors |
| B | Barricade the living-room window |
| K | Kill all |
| H | Repair the house |
| N | Day or night |
| Wheel | Zoom |

The status text lists the living enemies by type and the wave's composition and budget.

**Captures** use the real renderer:

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/ai/ai_preview.tscn <png> 200 --scenario=<name> [--night] [--kind=…] [--level=… --invasion=…]
```

The scene fast-forwards (time scale 3, rendering off), freezes at the scenario's moment, renders, writes the frame to the capture's `--out` itself and quits. The 2D caption is static.

Scenarios: `lineup`, `close --kind=<k>`, `runner_door`, `brute_barricade`, `bomber_walk`, `bomber_fuse`, `bomber_hole`, `wave`. Add `--check` without a capture to verify that a scenario reaches its moment headless.

## Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_ai` (also `--filter=test_pursuit_brain` and `--filter=test_game_helpers`).

- **`tests/ai/test_ai_director.gd`**
  - budgets follow the table;
  - compositions respect the budget, the head-count and per-kind caps and the unlocks, with bombers later in the wave, for every level, invasions 1–10 and 10 seeds;
  - no bombers before invasion 4 on Easy (200 seeds);
  - first waves are small;
  - waves are deterministic and vary by seed;
  - group pacing from shared fog points;
  - the legacy `begin` and dev compositions.
- **`tests/ai/test_ai_archetypes.gd`**
  - archetype stats and difficulty scaling (the psycho's 3, 3, 4, 4, 5);
  - every type spawns with its numbers and look (tint, club, pack and light);
  - knockback resistance;
  - **brute: 3 strikes per swing** (the door loses 3 HP per swing, a psycho's 1);
  - **runner: plans and takes the open back door** without a wall swing while a psycho's plan bashes;
  - a chaser uses a newly opened door at once;
  - `WeightedNav` is shared, patched incrementally and matches a fresh layer.
- **`tests/ai/test_ai_bomber.gd`**, on a real HouseWorld:
  - it ignores a nearby player, takes the world's first weak point (the front door), fuses for 2.5 s at its stand point and detonates: `breach` is true, the door is gone, voxels are removed and a walk-only path leads in;
  - **it goes for the world's first usable weak point (a weakened wall) while a psycho from the same spot attacks the player** (`breach`, the target point walk-through, a walk-only path in);
  - **killed before the fuse: it fizzles** (no blast, the house untouched);
  - **killed during the fuse: it pops** (1.6 m, 15 damage, no structural damage, no later full blast);
  - the blast hurts nearby enemies, not far ones;
  - its target is destroyed on the way: it picks another weak point and still blows it.
- **`tests/common/test_pursuit_brain.gd`**: the two existing tests, plus the oscillating half-open gap (fails on the old brain), no false swings while chasing a moving goal, and walking to a goal without attacking.
- **`tests/game/test_game_helpers.gd`**: the existing pacing test, plus the director → roster wave contract on a real HouseWorld.

## Requests for other owners

- **Lead (audio):**
  - `enemy/bomber_fuse`: a short positional beep (cooldown ≤ 0.2 s, max 2, **not** on the UI bus). The fallback `ui/error` is flat, so every bomber's beep is heard everywhere.
  - `enemy/bomber_blast`: positional, `far`. The fallback is `structure/break`.

  Both are picked up automatically once `Sfx.has(name)`.
- **Lead (GridNav):** a public read-only accessor for the raw occupancy (e.g. `raw_bytes() -> PackedByteArray`) or a `changed(rect)` signal. `WeightedNav` reads `_raw` through `get()` today, with a full-rebuild fallback.
- **C (world):** resolved in the merge. The bomber uses C's `weak_points(from, near)` entries and the recommended blast (radius 1.6, power 24 at the stand point).
- **Phase B:** the Integration steps above, and the test update in step 2.

## Known issues and limitations

- No human play. Balance (costs, weights, HP, blast numbers) is a first pass from the tests and the composition tables.
- Chasers converge on the same cheapest bash point (no spreading, apart from bomber claims), so crowds stack at one wall spot.
- The brute's collision radius (0.29 m) exceeds the nav clearance (0.25 m). In a tight gap it relies on the progress rule to bash it wider.
- Blast size follows C's measured numbers: one blast breaches wood and the house frame, two are needed for stone.
- Until Phase B connects `detonated`, a blast in the game damages the house and enemies but not the player.
- A runner bashes when no opening exists: it then takes the cheapest bash point at its high cost.
- Spawn gaps are real seconds, as in Experiment 002.
- Captures ran under software Vulkan (lavapipe); real-GPU cost of the bomber's light and the extra materials is unmeasured.
- Sounds were not auditioned by ear; the fuse uses the fallback `ui/error`.
