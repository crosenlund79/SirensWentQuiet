# Experiment 002 — Fog and expeditions (owner E)

The lot is the only place you can walk. Everything past it is a fog bank; walking into the fog at the edge is a deliberate interaction that opens a **simulated** expedition (choices, consequences, resources, time). Contracts: `docs/experiment-002/SPEC.md` §7.7.

| File | What |
|---|---|
| `src/expedition/fog_boundary.gd` | `FogBoundary` (Node3D): fog bank, player-only walls, prompt, exit request, return point |
| `src/expedition/shaders/fog_card.gdshader` | one horizontal fog slice (stacked ×10) |
| `src/expedition/shaders/fog_volume.gdshader` | volumetric fog shader for the `FogVolume` (Forward+) |
| `src/expedition/shaders/fog_veil.gdshader` | full-screen fog veil behind the expedition screen |
| `src/expedition/expedition_data.gd` | `ExpeditionData`: destinations, events, rules, formatting (static, pure) |
| `src/expedition/expedition_run.gd` | `ExpeditionRun`: one deterministic expedition from departure to the result |
| `src/expedition/expedition_screen.gd` | `ExpeditionScreen` (CanvasLayer): list → gear → confirm → events → report |
| `src/expedition/fog_preview.tscn` | capture/preview scene (foundation world + fog + optional screen); not part of the game |
| `tests/expedition/` | rules (fuzz, gating, window, effects, determinism), boundary (prompt, physics, return point), screen flow |

## 1. The fog and the boundary

**LOT** = `Rect2(-4.5, -3.5, 23, 16)` (plan metres). Outside it is fog; the road (y 13.5–15), the mailbox and the end of the driveway lie in the fog by design.

**Look.** Two layers that complement each other:

- **Fog slices** (`fog_card.gdshader`): ten horizontal ring meshes around the lot (from 1.2 m inside the edge to 70 m out) at heights 0.06–7 m. Each pixel's density comes from
  - the signed distance `d` to the lot rectangle (the fog starts as ground-hugging wisps at the edge and is substantial ~3 m out);
  - a bank top that rises with distance (≈1.7 m at the edge to ≈7 m from 14 m out) and is lifted and dropped by large-scale "billow" noise, so the upper slices form bright crests over darker hollows;
  - three drifting octaves of a seamless noise texture (different directions and speeds); near the edge the density breaks into patchy wisps, further out it is a solid bank;
  - an opaque floor on the lowest slice from ~10 m out, so nothing beyond is ever visible;
  - a soft fade where a slice cuts through geometry (car, trees, enemies), scaled by the slice height.

  Colour is unshaded: lit tops / darker hollows (higher and denser reads brighter), day grey-blue, night a moonlit blue that stays **lighter than the night background** (luminous, not black). The slices render under software Vulkan and on any Forward+ GPU.
- **Volumetric fog** (`fog_volume.gdshader` on a box `FogVolume` reaching 60 m past the lot, 12 m tall): the same distance/height profile in 3D value noise. (A WORLD-shaped volume rendered nothing under software Vulkan; a global density did, so the box is used.) It is lit by the sun/moon and ambient light, so it takes the house's shadow and the moonlight; a faint emission at night. `setup(player, env)` writes only `volumetric_fog_*` fields on the environment (global density 0, so only the bank exists; length 72 m; anisotropy 0.2; ambient inject 1.1 by day → 1.8 at night). Switch off with `use_volumetric = false` before `setup`, or `set_volumetric(false)` at runtime (the slices stay).
- **Day/night**: `set_night_amount(t)` (0..1) tints the slices and the volume and raises the moonlight scatter.
- **Cues**: along the front path and the driveway the fog starts about 0.6 m later and is a touch brighter, so they run on into the fog a little before vanishing (kept subtle: a stronger push read as a dark column of asphalt). While the player is within ~2.6 m of the edge the fog near them clears slightly at foot level (the player stays readable) and glows a touch.

**Walls.** Four invisible `StaticBody3D` boxes (1 m thick, 3 m tall) just outside the LOT on **layer 6** (`lot_boundary`, bit 32) with mask 0. The player's mask includes 32; enemies' doesn't, so they walk in out of the fog.

**Interaction.**

- `prompt_text()` returns `"[E] Leave the property and head into the fog"` while the player's centre is within **0.7 m** of the edge (the player can get to 0.25 m), otherwise `""`.
- Approaching does nothing. The game calls `request_exit()` when interact is pressed; it emits `exit_requested(player_position)` only at the edge.
- `return_point(at)` gives a free spot 1.6 m inside the edge nearest to `at`. If it's blocked (house, a blocking prop such as the car or a tree, or anything solid found by a physics shape query on layers 1|2|5), it walks along the edge in both directions in 0.5 m steps, then tries 1 m and 2 m further in.

Helpers: `edge_distance(p: Vector2)` (static), `is_player_at_edge()`, `lanes()` (static), `noise_texture()` (static, shared with the screen veil).

## 2. Destinations

| Destination | Time | Danger (tier, no gear) | Needs | Recommended | Events (weight) | Chance of 2 events |
|---|---|---|---|---|---|---|
| Nearby Homes (`homes`) | 2 h 30 min | 0.80 (Low) | – | backpack | boarded_house 3, collapsed_floor 2, locked_car 2, dogs 2, lone_psycho 1, tracks 1, fog_bank 1 | 40 % |
| Grocery Store (`grocery`) | 3 h 30 min | 1.00 (Moderate) | – | backpack, crowbar | storage_door 3, lone_psycho 2, dogs 1, locked_car 1, tracks 1, fog_bank 1 | 65 % |
| Hardware Store (`hardware`) | 4 h | 1.00 (Moderate) | – | crowbar, backpack | timber_rack 3, storage_door 2, collapsed_floor 1, lone_psycho 1, locked_car 1, tracks 1, fog_bank 1 | 55 % |
| Medical Clinic (`clinic`) | 5 h | 1.30 (High) | flashlight | ammo, crowbar | dark_pharmacy 4, waiting_room 3, dogs 1, tracks 1, fog_bank 1 | 100 % |

Loot tables (`[item, min–max, chance]`; the **locked** table is added when the crowbar is brought):

- **Nearby Homes**: canned food 1–2 (85 %), snacks 1–3 (70 %), water 1–3 (85 %), planks 2–5 (55 %), nails 4–10 (50 %), bandage 1 (35 %), rounds 2–4 (15 %), crowbar (12 %), flashlight (20 %), backpack (15 %). Locked garages: planks 3–5 (80 %), nails 6–12 (70 %), scrap 1–3 (50 %), canned food 1–2 (50 %).
- **Grocery Store**: canned food 2–4 (95 %), snacks 2–4 (85 %), water 2–4 (100 %), bandage 1 (20 %), backpack (8 %). Stockroom: water 2–3 (85 %), canned food 1–3 (75 %), snacks 1–2 (50 %).
- **Hardware Store**: planks 6–12 (100 %), nails 8–16 (95 %), scrap 2–5 (75 %), crowbar (50 %), hammer (60 %), flashlight (25 %). Stockroom: scrap 3–6 (90 %), nails 8–14 (80 %), planks 5–9 (75 %). (Planks to nails stay close to the 4 : 6 cost of a wall.)
- **Medical Clinic**: bandages 2–4 (100 %), first-aid kits 1–2 (60 %), rounds 3–6 (30 %), water 1–2 (40 %). Drug cage: first-aid kit 1 (90 %), bandages 1–3 (70 %), rounds 2–5 (40 %).

Every reward is an `Items.DEFS` id with a use in the game. Tools are found at most once and only when you don't own one (a tool lost on this trip can be replaced).

Measured averages over 400 seeds (08:00 departure, options varied per seed, empty storage; a throwaway headless script, not committed), items gained per trip:

| | bare-handed | crowbar + flashlight + backpack + 6 rounds |
|---|---|---|
| Homes (≈ 2 h 50 min) | 1.7 canned, 1.8 snacks, 2.3 water, 2 planks, 3.6 nails, 0.7 rounds; hurt in 18 % of trips | 3.8 canned, 2.6 snacks, 3.4 water, 8.5 planks, 16 nails, 1.5 scrap, 1 round; hurt 10 % |
| Grocery (≈ 3 h 40 min) | 2.7 canned, 2.3 snacks, 3 water; hurt 28 % | 7 canned, 5.1 snacks, 8.7 water; hurt 30 %, 0.6 rounds spent |
| Hardware (≈ 4 h 10 min) | 8.6 planks, 11 nails, 2.7 scrap; hurt 23 % | 22.7 planks, 32 nails, 11 scrap; hurt 17 %, crowbar lost 5 % |
| Clinic (≈ 5 h 10 min) | 2.8 bandages, 0.9 medkits, 1.7 rounds; hurt 28 %, flashlight lost 12 % | 6.7 bandages, 3 medkits, 5.1 rounds (0.8 spent); hurt 24 % |

For scale: a day costs about 1 canned food and 1.5 bottles of water (SPEC §6), so a bare-handed homes run feeds you for about two days.

## 3. Events

About ten short events, 2–3 options each; 1–2 per expedition, drawn without repetition from the destination's weighted pool. Every event has at least one option that needs no gear. `hurt` chances are multiplied by the destination's danger (×1.25 when exhausted).

| Event | Title | Tags | Where | Options |
|---|---|---|---|---|
| `storage_door` | Behind the door | fight | grocery, hardware | *Leave with what you have* (−40 min, loot ×0.7) / *Keep searching, quietly* (+30 min, loot ×1.2, hurt 35 %, 8–16) / *Investigate: force the door* (crowbar; +20 min, locked table again, hurt 45 %, 8–18) |
| `dogs` | Dogs | fight | homes, grocery, clinic | *Back away and go around* (+25 min, hurt 10 %, 4–8) / *Fire a warning shot* (1 round, spent) / *Walk straight through* (hurt 50 %, 8–16) |
| `lone_psycho` | One of them | fight | homes, grocery, hardware | *Shoot it* (2 rounds, spent; loot ×1.15; hurt 8 %, 5–10) / *Sneak around it* (+20 min, hurt 30 %, 8–16) / *Leave now* (−30 min, loot ×0.7) |
| `dark_pharmacy` | The pharmacy | dark | clinic | *Search it by flashlight* (flashlight; +20 min, loot ×1.25, hurt 25 %, 6–12) / *Grab what's near the door* (−15 min, loot ×0.8) / *Pry open the drug cage* (crowbar; +25 min, locked table again, hurt 30 %, 8–15) |
| `waiting_room` | The waiting room | fight, dark | clinic | *Fight your way through* (3 rounds, spent; loot ×1.1, hurt 25 %, 8–16) / *Run for the side corridor* (+10 min, hurt 45 %, 10–20, 30 % to lose the flashlight) / *Back out and leave* (−60 min, loot ×0.5, hurt 12 %, 5–10) |
| `tracks` | Footprints | – | all | *Follow the footprints* (+40 min, stash: rounds/water/canned food, hurt 20 %, 6–12) / *Leave them be* |
| `collapsed_floor` | The cellar | dark | homes, hardware | *Climb down with the flashlight* (flashlight; +30 min, half the search table again, hurt 10 %, 4–8) / *Climb down in the dark* (+30 min, same bonus, hurt 45 %, 6–14) / *Leave it* |
| `locked_car` | A locked car | – | homes, grocery, hardware | *Smash the window* (+5 min, a bag: rounds/water/snacks/bandage, hurt 25 %, 4–10) / *Pry the boot open* (crowbar; +10 min, the bag plus scrap/nails, hurt 5 %) / *Walk on* |
| `fog_bank` | The fog | dark | all | *Wait for it to thin* (+45 min) / *Feel your way along the kerb* (+10 min, loot ×0.9, hurt 25 %, 4–9) / *Light the way* (flashlight; +5 min) |
| `boarded_house` | A boarded house | – | homes | *Pry the boards off* (crowbar; +25 min, planks, nails, food, water) / *Climb in through an upstairs window* (+20 min, food and water, hurt 30 %, 5–12) / *Leave it be* |
| `timber_rack` | The timber rack | – | hardware | *Jump clear* (hurt 35 %, 6–14) / *Brace it with the crowbar* (crowbar; planks 4–8, 35 % to lose the crowbar) / *Back away and search elsewhere* (+15 min, loot ×0.85) |

The storage-door text names the place ("…behind the supermarket's storage-room door").

## 4. Rules

**Departure window** (`ExpeditionData.availability`, from `SurvivalTuning`):

- depart only between **05:00 and 18:00** (inclusive); before 05:00: "It's still dark out there. You can set out from 05:00."; after 18:00: "Too late to set out. You'd be coming back in the dark.";
- the **expected return** (now + the destination's nominal time) must be by **20:00**, else "You'd be coming back in the dark (around 20:40). Leave by 16:30.";
- not while an invasion is active; requirements must be owned ("Needs a flashlight. The clinic has no windows.").

A disabled destination stays in the list (so you can read it), marked *Unavailable: …*, and its "Choose gear" button is disabled with the reason. The actual trip can overrun the estimate (events add time, travel varies ±15 min); the report says "You got back after dark." if it ends after 20:00.

**Gear** (the gear screen; `sanitize_gear` clamps to what you own):

- **Rounds**: 0..owned. In a *fight* event, if you get hurt and still have a round (and the option didn't already shoot), you fire once to get clear: the injury is halved and one round is spent. Options such as *Shoot it* need and spend N rounds. Unspent rounds come home. Spent rounds are `consumed`.
- **Crowbar**: opens the destination's locked table on arrival (garages, stockroom, drug cage) and unlocks forced-entry options. It can be lost at the hardware store (*Brace it*).
- **Flashlight**: required for the clinic (always brought there); halves the chance of injury in *dark* events and unlocks light options. It can be lost in the clinic's waiting room.
- **Backpack**: +50 % on every stackable item you carry back (stochastic rounding).
- The hammer stays home (building needs it), so it can never be lost on a trip.

A tool left at home can't be lost; a missing tool's options are disabled with the reason ("Needs a crowbar", "You left the crowbar at home", "You lost the flashlight", "Needs 2 rounds (you have 1)").

**Risk tier** shown on the list and gear screens: `danger(dest, gear, energy)` = base danger × 0.78 with ≥ 3 rounds (0.9 with 1–2) where fights can happen × 0.9 with a flashlight where dark places exist × 1.25 at energy ≤ 15. Tiers: < 0.9 Low, < 1.15 Moderate, < 1.45 High, else Severe. With gear the clinic drops from High to Moderate.

**Resolution** (`ExpeditionRun`):

- Three RNG streams seeded from `hash("swq|<run.seed>|<run.expeditions>|<destination>|<stream>")`: *events* (which events), *outcome* (injury/loss rolls and event bonus loot, fixed draws per choice) and *loot* (search, locked table, travel jitter, backpack rounding). So the events you meet don't depend on the gear you pick, and the same state, gear and choices always give the same result.
- Loot: the main table × the product of the options' `loot` multipliers (clamped 0.3–1.6), + the locked table (crowbar), + event bonuses, then the backpack.
- Time: nominal + travel jitter (−15..+15) + options' minutes, clamped to 60 .. nominal + 150. Integer minutes.
- Damage: sum of injuries, capped at **40** per expedition.
- `gained` = min(found, `inventory.space_for(id)` at departure); the rest goes to `left_behind` (only materials are capped). `consumed` (rounds) ≤ brought ≤ owned; `lost` (tools) only if brought and owned.
- Never touches the `GameState`; the game applies the result with `GameState.apply_expedition` (once, guarded by `id`).

## 5. Result

SPEC §7.7 schema plus three additive fields:

```
{"id": "exp-<seed>-<n>-<destination>-<depart total minutes>", "destination": id, "name": String,
 "minutes": int, "gained": {id: n}, "consumed": {id: n}, "lost": {id: n}, "left_behind": {id: n},
 "damage": float, "events": [String], "summary": String,
 "brought": {"ammo": n, tool: 1},      # additive: the gear taken
 "depart_at": float, "return_at": float} # additive: total minutes
```

Counts in the report and lines use countable names (`ExpeditionData.count_text`: "1 round", "3 cans of food", "2 bottles of water"). `events` lists one line per answered event (with "Hurt (−N health)", "N rounds used", "Lost the …"), the crowbar line ("The crowbar opened the stockroom.") and "Storage full: left behind …". `summary` is one sentence naming the biggest finds: "Back after 4 h 34 min with nails, scrap metal and planks. Hurt (-7 health)."

## 6. The expedition screen

`ExpeditionScreen` (CanvasLayer, layer 60, `process_mode = ALWAYS`, `UiTheme`). The game pauses the world while it's open.

1. **Fade in** from fog-grey (0.7 s): a full-screen drifting fog veil (`fog_veil.gdshader`, darker at night), then the panel.
2. **Destinations**: list on the left (name, approximate time, risk, or *Unavailable: …*), details on the right (description, time and return clock, risk and "with the right gear", possible finds, needs, recommended, warnings for low health or exhaustion). *Turn back* emits `cancelled`.
3. **Gear**: a rounds slider (0..owned) and checkboxes for crowbar, flashlight and backpack (missing ones disabled, required ones locked on), each with its effect; on the right the live risk tier and what you bring.
4. **Confirm**: time, return clock, gear, risk, warnings. *Head into the fog* → "You walk into the fog." (≈2 s).
5. **Events** (1–2): title, short text, numbered option buttons (keys 1–3), disabled options show why, hints ("2 rounds", "+30 min", "cuts the trip short"); then the outcome with its consequences (hurt, rounds used, lost) and *Continue*.
6. **Report**: summary, time away (left/back clocks), found, used, lost, injuries, left behind (storage full), what happened. *Return home* emits `finished(result)` exactly once and fades out.

Keyboard: focus starts on the useful button of each step; arrows/Tab move, Enter activates, Esc steps back (list → `cancelled`), keys 1–3 choose options. Input is ignored during fades, so a double click can't answer twice. Sounds through `Sfx.ui("ui/open" | "ui/click" | "ui/error" | "ui/close")`.

Public helpers (tests, preview, the game if useful): `select_destination`, `to_gear`, `set_ammo`, `set_tool`, `to_confirm`, `depart`, `choose_option`, `continue_on`, `return_home`, `cancel`, `back`, `brought_gear`, `step`, `is_open`, `instant` (no fades).

**Wiring for the game (G):** on `boundary.exit_requested(at)`: pause the tree, `screen.open(state)`. On `finished(result)`: `state.apply_expedition(result)`, move the player to `boundary.return_point(at)`, unpause, autosave. On `cancelled`: unpause.

## 7. Preview and captures

`src/expedition/fog_preview.tscn` builds the foundation world (HouseWorld, VoxelLighting, VoxelPlayer, VoxelCamera, GameHud) with a FogBoundary, and can open the screen at any step. User args: `--night[=t]`, `--pos=x,y`, `--zoom=d`, `--novol`, `--clock=HH:MM`, `--seed=n`, `--give=id:n,...`, `--screen=list|gear|confirm|event|outcome|report`, `--dest=id`, `--pick=i`, `--picks=i,j`; debug: `--nocards`, `--voldens=x`, `--globalfog=x`.

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/fog_day.png 0.7
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/fog_night.png 0.7 --night
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/report.png 0.4 --pos=6.5,7.8 --clock=09:10 --screen=report --seed=2026 --dest=hardware --give=crowbar:1,backpack:1,wood:26 --picks=0,2
```

Checked visually under software Vulkan only (about 1 fps): the fog at the south edge by day and at night with the prompt, the whole ring at zoom 26, and the list, gear, event and report steps.

## 8. Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=expedition`

- `test_expedition_rules`: data consistency; **fuzz** (400 random states, inventories near their caps, random gear and choices): schema, int minutes, bounded damage, positive int counts, valid ids, caps, left-behind only when full, consumed/lost ≤ owned and ≤ brought, unique ids, determinism, no state mutation; applying many results keeps the inventory valid; ids unique through a run; seed sensitivity; events independent of gear; clinic gating; departure window; option gating and reasons; option effects (rounds consumed, early exit shorter, forced door finds more); the flashlight lowers dark-place injuries and rounds lower fight injuries (statistically, 199 seeds); backpack and storage caps; tool loss only when brought.
- `test_expedition_fog_boundary`: prompt only within 0.7 m; exit only on request at the edge; physics (a body on layer 3 with mask including 32 stops at the east and south edges; an enemy-mask body walks through); return points free and near; fog layers, night tint and volumetric settings.
- `test_expedition_screen`: Turn back → `cancelled` once; full flow (including the gear widgets) → `finished` once with the resolver's result, state untouched, the game can apply it; unavailable destinations explain and block; disabled options say why; Esc steps back; the animated flow (fades, travel pause) works while the tree is paused.

## 9. Tuning

Numbers live at the top of `expedition_data.gd` (`BACKPACK_BONUS`, `MAX_DAMAGE`, `MIN_MINUTES`, `TRAVEL_JITTER`, `LOOT_MULT_RANGE`, `LOW_ENERGY*`, `DARK_FLASHLIGHT_SCALE`, `FIGHT_AMMO_SCALE`, risk bounds) and in the `DESTINATIONS`/`EVENTS` tables. Fog: `FogBoundary.LAYERS`, `LAYER_ALPHA`, `RING_*`, `VOLUMETRIC`, and the shader uniforms (colours, `wind`, `lane_push`).

## 10. Limitations

- The economy is a first pass, judged from the measured averages above, not from play.
- Loot doesn't remember what you already took (destinations never deplete); there's no notion of distance between trips or of a "known" map.
- Found items only count at the end: a round found on the trip can't be fired in a later event of the same trip.
- The `unlimited` cheat isn't special-cased: rounds brought are still deducted as `consumed` when spent (`GameState.apply_expedition` decides).
- The volumetric part needs Forward+; under the Compatibility renderer only the slices show. Volumetric fog quality and cost depend on the project's volumetric fog volume size (Godot defaults); it was only checked under software Vulkan (lavapipe), never on a real GPU.
- Fog slices are big transparent rings (10 layers): cheap on a GPU, but they are full-screen overdraw at the screen edges.
- Destinations' text is English only.
