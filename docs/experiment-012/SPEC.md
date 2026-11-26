# Experiment 012 — The World Is Watching: contracts

The requirements are in `ASSIGNMENT.md` (§ numbers follow the user's message). This file covers who owns what and the interfaces between the parts.

- **Branch:** `exp012/the-world-is-watching` (from `1ed8ba2`).
- **Checkpoint:** `playtest/exp012-the-world-is-watching`.

**Working rules:**
- Rapid delivery: focused smoke tests per area, no big repeated suites.
- Never write to `custom/`.
- Never move, rename or delete the user's audio files.
- No Autoloads.
- No model identifiers in commits, code or docs.

## Agents and ownership

| Agent | § | Owns |
|---|---|---|
| **C** (characters and rendering) | 29–34 | `src/character/*`, `src/voxel/voxel_rig.gd` (rig fixes), the flashlight (equipment and hotbar light nodes, `game_hotbar.gd`), quality presets (`GameSettings`, settings panel, the lighting/snow/sky hooks), the FPS display, the look-cache stutter, the UI font (`ui_theme.gd`, a new font file in `assets/fonts/`) |
| **V** (visibility) | 15–19 | `src/visibility/*`; a new discovered-area memory (fog of war) at home and in POIs; line of sight and the vision cone for dynamic objects (enemies, corpses, items in rooms); the proximity sense; doors in cutaways; the fog-boundary slowdown (`src/expedition/fog_boundary.gd` and player movement) |
| **E** (enemies) | 11–14 (+ 25 for corpses) | detection reactions, shouts as noise events (`ai_enemy.gd`, `enemy_behaviour.gd`, `src/noise/`); names (a new `src/ai/human_names.gd`); the downed toast; persistent searchable corpses (a new `src/ai/corpse.gd`), their loot tables and persistence at home and in POIs |
| **G** (hordes and sieges) | 9, 10 | whole-group spawning in `invasion_director.gd` / `enemy_roster.gd`; a new `src/siege/` (the siege director, tactics, enemy barricades); siege eligibility through `StoryState` |
| **S** (story) | 2–8, 35–37 | a new `src/story/` (story state, director, the four encounters, cinematics, the ropes and the fireplace aftermath, Architect staging, story audio, door-impact sync); the sleep hook in `survival_game.gd`; the Architect audio mapping (`story/*` logical names) |
| **L** (looting, POIs, travel, UI rows) | 20–28 | regional map routing and travel time (`src/map/`, `src/travel/`, `src/region/`), the map vehicle model, double walls for secured rooms (`src/poigen/`), the kitchen chairs (`src/props`, home furniture), interaction icons and highlight (`interaction_finder.gd`, HUD prompt), full-inventory searching, fixed-size loot and storage windows (`poi_loot_panel.gd`, `storage_panel.gd`, `inventory_panel.gd`), compact item rows with tooltips, the mostly-depleted marker |
| **A** (audio audit and F10) | 8 (leak), 38–43 | `docs/audio/AUDIO_REQUIREMENTS.md`; straightforward missing triggers; the main-menu Architect-audio leak (discovery and pooling in `audio_inbox.gd`, `sfx.gd`, `psycho_voice.gd`, `menu_siege.gd`, export behaviour); stopping story audio on menu return or load; the **tabbed F10** (`dev_menu.gd` structure) with the Debug tab and a generic Audio tab |
| **Lead** | 44–48 | the SPEC, integration, smoke checks, the build, the report |

**Hot shared files:** `survival_game.gd`, `dev_menu.gd`, `game_poi.gd`, `ai_enemy.gd`, `enemy_roster.gd`, `game_hud.gd`, `game_state.gd`.
- Keep to your own functions.
- Add new functions and files rather than rewriting other people's.
- Add one registration line where a list must grow.
- Put large new logic in your own new files.

## Shared interfaces

### Story state (S)

`GameState.story: Dictionary` is saved as the top-level key `"story"`. It is missing in old saves, which means a fresh state.

`StoryState` (static, `src/story/story_state.gd`):
- `ch1(state) -> Dictionary` returns `{"done": [ints 1..4], "next": int (1..4, 5 = finished), "next_at": float (total_minutes when the next is eligible), "rope": "" | "kept" | "burned", "siege_at": float (-1 = not yet), "sieges": int}`.
- `architect_introduced(state) -> bool` is true after Encounter 1.
- `siege_eligible(state) -> bool` is true once Encounter 4 is done and `total_minutes >= siege_at`. G calls it.
- `note_siege(state)` records that a siege happened.

**Previews never write the state:** they run on a duplicate, or they snapshot and restore the house, inventory and story.

### Enemy identity (E)

- **`AIEnemy.display_name: String`:** for humanoids it comes from `HumanNames.for_seed(appearance, sex)`, where sex is taken from `HumanoidLooks.look(kind, appearance).body.sex`. Because the name depends only on the seed, it persists automatically.
- **`AIEnemy.kind_label() -> String`:** "Psycho", "Runner", "Brute" or "Bomber". The Architect is never an AIEnemy.
- **No duplicate names:** the roster avoids a duplicate full name among the living (`HumanNames.unique_seed(...)` or a re-pick).
- **Shouts:** `NoiseEvent.emit(game, pos, radius, "shout")`. Listeners react to the approximate origin; seeing Eli is what starts a chase.

### Corpses (E)

A dead enemy becomes a `Corpse`: a static, settled rig (no AI, no animation and no physics after settling) plus a loot dictionary, the name, kind and appearance.

**Persistence:**
- **At home:** `state.home["corpses"]`, a list of `{pos, yaw, kind, app, name, items}`.
- **In POIs:** the visit record's `"corpses"` list, in the same shape.
- **Cleanup:** a fully looted corpse may be removed. An unlooted one never despawns.

**Searching:** through the same interaction and loot panel as containers (L's fixed-size panel), respecting full-inventory rules (§25).

### Hordes and sieges (G)

**`InvasionDirector`** creates every member of a wave at the start. The members spawn at several out-of-sight points (roads, woods, gardens, around the lot) at varied distances, each moving on its own. A kill never spawns anyone.

**`SiegeDirector`** (`src/siege/`):
- **Starting:** it starts from the normal invasion slot when `StoryState.siege_eligible`, or from F10.
- **Groups:** it assigns members to groups with tactics: encircle, breach, contain, trap or pressure.
- **Perception:** it uses the approximate last-known position of Eli and the entrances that have been seen.
- **Barricades:** it places counterable, destructible barricades (existing construction pieces or props) at doorways.
- **Steering:** it steers enemies through a small additive API on `AIEnemy`, such as `set_goal(pos: Vector2, why: String)` and `clear_goal()`. E and G both edit `ai_enemy.gd`; additive functions only.

### Story audio (S, guarded by A)

The user's recordings map to logical names in the `story/` namespace:
- `story/architect_*` for the voice files;
- `story/follower_bark`, `story/follower_howl`, `story/follower_breath`, `story/follower_bin` and `story/follower_bat` for the followers, each with variants.

**Guarding:**
- No generic selection (psycho voices, menu siege, ambience beds, random pools) may ever draw a `story/*` name or a file under them. A enforces and tests this.
- `StoryAudio.stop_all()` is called on returning to the menu, on loading and when a cinematic ends.

### Visibility (V)

**What V decides:** V decides whether each dynamic thing is seen. That covers enemies (roster), corpses and loose POI items.
- It hides their visual (rig or mesh) without disabling their logic or their sounds.
- The vision cone follows Eli's aim or facing, and line of sight is checked against the voxel world. Both are cached and throttled.

**Discovered areas:**
- **At home:** `state.home["seen"]`.
- **In POIs:** the visit record's `"seen"`.

Both use a compact coarse grid or room ids.

### F10 (A, with everyone)

A turns `dev_menu.gd` into tabs. Suggested: Story, Player, World, Enemies, Building, POIs, Audio, Debug.
- **Registering a section:** each agent adds its own `_build_e12_<agent>_section(box: VBoxContainer)` function and one line in `_build()`:
  `_build_e12_x_section(box)   # Exp 012 (X) -> tab: Story`
- **Routing:** the lead routes these lines into tabs at integration. A provides `_tab(name: String) -> VBoxContainer`.

## Testing

**Per area:** a focused test file `tests/e12/test_<area>.gd`, kept light.

**Running tests:**
- `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=<name>`
- The runner fails a test on any script error.

**Before handing back,** run the existing tests nearest to the files you changed.
