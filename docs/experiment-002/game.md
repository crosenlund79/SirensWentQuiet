# Experiment 002 — Game loop (owner G)

The game root `res://src/game/game.tscn` (`SurvivalGame`) wires every module into one run and drives the loop:

**wake → assess needs → scavenge → return → build and prepare → survive the night → sleep → repeat.**

The modules own the mechanics (survival state, house world, construction, fog and expeditions, UI, audio). The game root decides *when* things happen. Small helpers next to it own the pacing:

| File | Purpose |
|---|---|
| `survival_game.gd` | Orchestrator: launch, clock and events, firing, interactions, flows, saving, dev and debug API |
| `invasion_director.gd` | Invasion wave pacing, fog-band spawn points, deterministic stragglers (pure logic) |
| `enemy_roster.gd` | The psychos in the world: spawning, moans, the dawn retreat, swing signals |
| `footsteps.gd` | Footstep rhythm and variants (pure logic) |
| `interaction_finder.gd` | What [E] acts on: the nearest interactable with a prompt within 1.6 m |
| `run_save.gd` | Composes and validates the save dictionary (SaveGame does the file IO) |
| `game_ui.gd` | Builds and owns the HUD, panels, expedition screen, intro and fade |
| `game_input.gd` | Forwards input to the root, also while the tree is paused |
| `screen_fade.gd` | Fade to black for sleep |
| `game_launch.gd` | Menu → game hand-off: `mode`, `notice`, `seed` |

No Autoloads. Nothing here depends on `src/modular/` or `src/illustrated/`.

## Controls

| Input | In play | Elsewhere |
|---|---|---|
| WASD / arrows | Move | — |
| Mouse | Aim (crosshair cursor) | Normal cursor in panels and build mode |
| LMB | Fire (one round per shot, 0.2 s interval) | Build mode places; panel buttons never fire |
| E | Use the nearest thing (bed, door, crate, collector), or head into the fog at the lot edge | — |
| I / Tab | Inventory (pauses) | I closes it |
| B | Build mode on/off (needs a hammer) | — |
| R, RMB, 1–7 | Build mode (handled by BuildMode) | — |
| Esc | Closes the open panel, else leaves build mode, else closes the dev menu, else opens the pause menu | — |
| F10 | Developer menu (does not pause) | Also while paused |
| Mouse wheel | Zoom | — |

## Flows

**Launch.**
- *New game* (`GameLaunch.mode = "new"`): `GameState.new_run(GameLaunch.seed)` and `world.build_new()`. The player wakes beside the bed (bed + 1.45 m south), facing the room. The intro overlay plays (the world is paused), then the initial save is written. That is the moment a new game replaces the previous run; the main menu asked first.
- *Continue*: `SaveGame.read()` → `run_save.gd` validates → `GameState.from_dict` → `world.load_data` → the player's position, facing and the dev time scale are restored.
  - If `read()` fell back to the `.bak` (`restored_from_backup`), the game says so in a toast and in `GameLaunch.notice`.
  - On any failure (no file, damaged file, missing or invalid state, a finished run, missing house data, `load_data` returning false), `GameLaunch.notice` becomes "The save could not be loaded: …" and the game returns to `GameLaunch.MENU_SCENE` without crashing.
  - Stub-era tolerance: a save whose `world` is an empty dictionary (written while `HouseWorld.save_data()` was a stub) loads the pristine house with a warning.

**Clock.** Each frame of normal play (no modal panel, not paused), `state.advance(delta × MINUTES_PER_SECOND × time_scale)`. The returned events are handled in order:
- `dawn`: water from the rain collectors (`state.on_dawn(n, e["at"])`, once per dawn event, else +1 water per collector), the dawn stinger, every remaining psycho retreats into the fog, an active invasion ends, autosave.
- `dusk`: a toast.
- `new_day`: a "Day N" toast and autosave (when safe).
- `invasion_due`: the invasion starts.

The night amount drives the lighting, the player's lights, the fog boundary and the ambience every frame.

**Firing.** LMB pulls the trigger only through unhandled input (a click on a button is never a shot), and never while a panel is open, the intro plays, the mouse is over UI (`gui_get_hovered_control()`), in build mode or when dead. `state.use_ammo()` then `world.shoot(...)`, the muzzle flash and casing from `world.fx`, recoil, and `weapon/handgun_fire` at the muzzle. Hits on a psycho play `enemy/hit`, and a kill plays `enemy/death`. With an empty gun: `weapon/dry_fire` (at most every 0.45 s) and an "Out of ammo" toast (at most every 2 s). The unlimited cheat keeps the count.

**Enemies.**
- A wall swing calls `world.enemy_strike` and plays `door/bash` if a door is within 1 m of the target, else `impact/wood`. The camera shakes slightly within 6 m.
- A player swing calls `state.damage(state.enemy_damage(), "psycho")` with a camera nudge and `enemy/attack`. If health actually dropped, it also plays `player/hurt` and calls `hud.flash_damage()` (if it exists).
- Each psycho moans (the `enemy/moan` group, positional) every 6–14 s.
- An `AudioListener3D` follows the player at ear height, so positional sounds are heard from the player, not from the camera 20 m above.

**Invasions** (`invasion_director.gd`).
- The invasion starts at `invasion_due`, or from the dev menu (`state.force_invasion_now()` if it exists): `state.start_invasion()`, the `stinger/invasion`, `ambience.set_tension(1)` and a "They're coming." toast.
- `state.invasion_size()` invaders spawn with `invasion_enemy_hp()` and `invasion_speed_scale()`. The first comes 2.5 s after the start, the rest 25–40 real seconds apart, at HousePlan spawn points in the fog band (outside the LOT, inside the YARD), at least 7 m from the player.
- The HUD banner shows "They're here · N left" during the invasion, and "Something is coming tonight." from 12:00 on an invasion day (`state.invasion_due_soon()`).
- **End.** When all have spawned and none are alive: `end_invasion(true)`, the toast "They're gone… for now", tension 0 and an autosave. At 06:00 the survivors retreat (they walk to the nearest fog point, then fade out), and the invasion ends the same way.
- **Stragglers.** On non-invasion nights from Day 2, one psycho comes with a 35 % chance, at a time between 23:00 and 03:00. The decision is deterministic from the run seed and the day (`state.roll_straggler(day)` takes over if S adds it). A straggler also cuts sleep short.
- Retreating psychos are not threats. They don't block sleep, saving or expeditions, and their swings are ignored.

**Interactions.** The nearest interactable with a non-empty `interact_prompt()` within 1.6 m, else the fog boundary's `prompt_text()`, goes to `hud.set_prompt`. E calls `interact(game)` or `boundary.request_exit()`.

**Sleep.**
- The bed calls `open_sleep()`. It is refused with "You can't sleep with them out there" while any psycho is a threat or an invasion is active, and with `state.can_sleep()`'s reason ("You're not tired.", …). Otherwise the sleep dialog opens (paused).
- `sleep_chosen(m)`, where -1 means `until_morning_minutes()`, runs `state.plan_sleep(m)`, which also stops at tonight's straggler (reason `"straggler"`, its `text` becomes the wake toast).
- Then: `player/sleep`, fade to black, **one** `state.advance(minutes, true)`, its events processed, fade in.
- If interrupted: "You wake to something at the door." The invasion has already started, because the advance lands exactly on the due minute. Otherwise it autosaves on waking.
- Sleeping through an invasion is impossible: `plan_sleep` truncates, and sleep is refused while one is active.

**Expeditions.**
- `boundary.exit_requested` is refused while threats exist ("Not with them out there."). Otherwise the world pauses (no clock) and `ExpeditionScreen.open(state)` opens.
- `finished(result)` is accepted only while the screen is open, so it is applied once even if the signal repeats. `state.apply_expedition(result)` (itself guarded by `result.id`) advances the time once, and its events are processed. The player is placed at `boundary.return_point(at)`, facing the house, then an autosave.
- `cancelled` resumes and nudges the player 1 m back into the lot.

**Build mode.**
- B calls `build.set_active(...)`, after `build.setup(world, state, camera, player)` at assembly.
- `hud.set_mode("build"|"play")`. `build.message` becomes a toast. Esc leaves build mode.
- `world.structure_changed` sets `state.inventory.storage_crates = world.count_objects("crate")`.

**Panels.**
- I/Tab opens the inventory panel and pauses.
- The open panel handles Esc / I itself (U's modals consume them) and emits its signal; the game follows: `resume_requested` and `closed` unpause. With no panel open, Esc leaves build mode, else closes the dev menu, else opens the pause menu: `open(can_save())` with Resume, Save, Settings and Main Menu.
- Save calls `save_now()` synchronously and hands the result to `pause.report_save(...)`. "Save and quit" (`save_requested`, then `main_menu_requested`) therefore leaves only after a successful save.
- Settings: `settings_requested` stays unconnected, so the pause menu opens its own SettingsPanel and returns to itself.
- The tree is paused while the pause, settings, inventory, sleep, expedition or death screens are open. All UI nodes are `PROCESS_MODE_ALWAYS`.
- F10 toggles the developer menu (no pause).
- Crosshair cursor in play (`AssetResolver "common/crosshair"`), normal cursor otherwise.

**Death.** `state.died` stops input and leaves build mode, closes panels, hides the HUD, plays `player/death` and **deletes the save**. After 1.4 s it pauses and opens `DeathScreen.open(days_survived, cause)`, whose button leads to the main menu.

## Saving

`can_save()` returns "" or the reason: not ready, dead, asleep, on an expedition, during an invasion, or with enemies alive.

`save_now()` writes:

```
{"summary": state.summary() or {day, clock, health, days_survived, text},
 "state": state.to_dict(), "world": world.save_data(),
 "game": {"version": 1, "player": {"pos": [x, z], "yaw": y}, "time_scale": t,
          "director": {"stragglers_done": [...]}}}
```

SaveGame adds `game_id`, `schema` and `saved_at`. A failed write returns `"Saving failed: " + SaveGame.last_error`. (Saves from the foundation stub era kept the game dictionary in `game_data`; it is still read as a fallback.)

**Autosave** happens only at safe transitions, and is skipped (logged as `skip:<reason>`) when `can_save()` refuses:
- after the intro of a new run;
- at a new day and at dawn;
- on waking;
- after an expedition;
- after an invasion ends.

It never happens mid-sleep, mid-expedition, during an invasion or while a psycho is alive. Live encounters are therefore never saved. That is the SPEC's design limitation.

## Developer API (called by the DevMenu)

| Method | Effect |
|---|---|
| `dev_spawn(n)` | n psychos at the fog points nearest the player (at least 6 m away) |
| `dev_trigger_invasion()` | Starts an invasion now (`state.force_invasion_now()` first if it exists) |
| `dev_repair_house()` | `world.repair_all()` |
| `dev_advance(minutes)` | Through `state.advance`, with event and straggler handling |
| `dev_skip_to(hour)` | To the next occurrence of that hour |
| `dev_set_time_scale(x)` | Game minutes per real second ×x (0–600), saved with the run |
| `dev_info()` | Day/time/scale, enemies, invasion progress, next invasion, tonight's straggler, house damage, save status |

Without `force_invasion_now`, a dev-triggered invasion takes the place of the next scheduled one (ending it moves the schedule 3 days on).

## Debug API (tests and the playtest)

`debug_state/world/player/ui/director/roster/modal/prompt`, `debug_player_pos`, `debug_teleport_player(p)`, `debug_fire_at(p, h)` (respects ammo like LMB), `debug_spawn_enemy(p, invader)`, `debug_living_enemies`, `debug_enemy_positions`, `debug_kill_enemies`, `debug_open(panel)`, `debug_close` (Esc), `debug_interact` (E), `debug_sleep(minutes)` (awaitable), `debug_start_expedition`, `debug_finish_expedition(result)`, `debug_cancel_expedition`, `debug_save`, `debug_reload` (Continue), `debug_set_spawn_gap(v)`, `debug_straggler_time(day)`.

Records: `left_to`, `last_toast`, `autosave_log`, `last_sleep`, `last_expedition`, `shots_fired`.

Signals: `sleep_finished(plan)`, `invasion_started`, `invasion_ended(reason)`, `autosaved(reason)`.

Settable before the node enters the tree: `stay_in_scene` (record scene changes instead of doing them), `skip_intro`, `aim_with_mouse`, `fade_time`, `death_delay`.

User args, for captures: `--skip-intro`, `--hour=21.5`, `--seed=N`, `--save-path=/abs/file` (keeps captures away from the player's save).

## Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=game`

- `tests/game/test_survival_game.gd`, the game scene against the present modules:
  - a new run boots through the intro and saves;
  - ammo is used and stops at 0, and the cheat keeps it;
  - no firing through panels or in build mode;
  - an enemy hit hurts, and invulnerability blocks it;
  - shooting kills;
  - sleep: refused with enemies, advances time once, crosses dawn, is interrupted by an invasion and cut short by a straggler;
  - an expedition is applied once with time advanced once, can be cancelled, and is refused with enemies;
  - save → continue restores the state and position;
  - a bad save bounces to the menu with a notice;
  - the autosave rules;
  - death deletes the save and shows the death screen;
  - the dev API;
  - the dawn retreat;
  - stragglers are deterministic;
  - the bed prompt, the panels and the fog prompt.
- `tests/game/test_game_helpers.gd`: footsteps, the interaction finder, save composition and validation, invasion pacing.

## Playtest

`tools/survival_playtest.sh [out dir] [--render-always]` runs `tools/survival_playtest.gd` twice, as two separate processes under Xvfb with the real renderer, at `--fixed-fps 30`. The save goes to `<out>/playtest_save.dat`, never the player's save.

Input is real:
- key events: WASD, E, I, B, number keys, Esc, F10;
- mouse motion and clicks on the actual buttons, found by their text;
- the mouse aimed at psychos with LMB held.

The debug API reads state. It acts only where input can't reasonably reach, and each such use is printed as a note: the shortened invasion spawn gaps and the fallbacks (time skip, cheats, kill, repair) when a button isn't there. Part 1 fixes the run seed (`GameLaunch.seed = 1123`) so expedition rolls and stragglers repeat.

**Part 1:**
1. New Game from the main menu; wake on Day 1.
2. Inventory (I).
3. Walk bedroom → living room → front door → yard.
4. Fog edge prompt, E.
5. Drive the expedition screen with its own buttons (destination, gear, confirm, "Head into the fog"), answer an event with its number key, Continue, Return home.
6. Resources gained, time advanced once.
7. Eat and drink with the inventory's Use buttons.
8. B, number keys and clicks to build.
9. Night with the dev menu: "Night 20:00", "×10" until dark, "×1" (buttons scrolled into view with the wheel).
10. Walk to the bed, E, click a sleep option.
11. Dev-menu "Next invasion", shooting with the mouse.
12. Damage (shooting the south wall if the invasion left little), then repair (build-mode repair if reachable, else the dev menu).
13. Save from the pause menu, write `part1_state.json`, Main Menu, Quit.

**Part 2:**
1. Continue from the main menu.
2. Compare the voxel hash, `damage_summary`, object counts and positions, inventory, stats, clock and player position against part 1's file.
3. Invulnerable and unlimited cheats through the dev menu buttons, with their effects observed.
4. `AssetResolver.get_audio` with a corrupt override returns the template (skipped while `get_audio` doesn't exist).

Screenshots:

| Shot | File |
|---|---|
| Main menu | `01_main_menu` |
| Waking | `02_wake_day1` |
| Inventory | `03_inventory` |
| Daytime house | `04_day_house` |
| Fog boundary | `05_fog_boundary` |
| Expedition selection, gear, confirm, event, outcome, report | `06_expedition_selection`, `06b`…`06f` |
| Construction mode | `07_construction_mode` |
| Nighttime house | `08_night_house` |
| Invasion | `09_invasion` |
| Damaged house | `10_damaged_house` |
| Repaired house | `11_repaired_house` |
| Continued game | `14_continued` |

## Optional extras the game uses when present (`has_method` guards)

| Module | Extra | Used for |
|---|---|---|
| GameState (S) | `summary() -> Dictionary` | Save summary for the menu |
| GameState (S) | `on_dawn(collectors, at) -> Dictionary` | Water added at dawn (else +1 per collector) |
| GameState (S) | `can_sleep() -> String` | Refusal reason, "" = allowed |
| GameState (S) | `roll_straggler(day: int) -> float` | Absolute minute of that night's straggler, or -1 (else `invasion_director.gd`'s own roll) |
| GameState (S) | `force_invasion_now()` | Dev-triggered invasion replaces the next scheduled one |
| GameHud (U) | `flash_damage()`, `show_saved()` | Damage flash and autosave indicator |
| PauseMenu (U) | `report_save(error)` | Save result shown in the menu |
| IntroOverlay (U) | `is_playing` | No firing during the intro |
| Doors (V) | `is_door()` or `kind == "door"` | `door/bash` instead of `impact/wood` on enemy swings |

`debug_close()` (tests) closes a panel through its `close()` and then updates the game's own state, so it works whether or not `close()` emits `closed`.

## Limitations

- No live encounter is ever saved (by design). A save made before an invasion restores it, because invasions are scheduled by time.
- Invasion spawn gaps are real seconds, independent of the dev time scale.
- Stragglers crossed during a long time skip that ends in daylight never appear: they "came and went".
- Eating, drinking and bandaging sounds are the inventory panel's. Impact sounds for bullets are left to `world.shoot` (to check once V lands).
- The game keeps its own `AudioListener3D` at the player's head; Sfx's auto listener never takes over from it.
- The game toasts autosaves only through an optional `hud.show_saved()`.
