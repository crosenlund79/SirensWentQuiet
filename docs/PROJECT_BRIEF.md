# Project Brief — Single design and task handoff record

This file **records** decisions and approvals; it never grants them. Only the user can approve scope, in their message in the current conversation. **Undecided = ask, don't choose.**

## Game decisions (user-confirmed only)

- **Game title:** Sirens Went Quiet (working title)
- **Godot version (pin minor):** 4.7 (developed with 4.7.2 stable). Chosen by Claude under the user's 2026-11-23 instruction to make necessary technical decisions autonomously; the template had no prior version.
- **Premise:** Present day, after an unexplained catastrophe. The grid has failed, communication has stopped, and nobody has heard from another sane living human. The player defends one house on one lot ringed by dense fog. Hostile, disturbed people ("psychos") roam; their nature and the catastrophe stay undecided.
- **Core player loop (approved for Experiment 002):** wake → assess needs → scavenge (simulated expeditions through the fog) → return → build and prepare → survive the night → sleep → repeat.
- **Perspective / art direction:** Chosen by the user after Experiment 001 (message of 2026-11-23): **true 3D voxels for structure** (walls, floors, foundation, roof), combined with **conventional stylized 3D assets** where more appropriate (furniture, doors, lamps, appliances, storage, vegetation, characters and weapons). Fixed three-quarter camera. Modern setting, stylized, slightly eerie, hand-crafted, with a coherent hybrid look.
- **Confirmed mechanics and constraints (Experiment 002):**
  - WASD + mouse aim + LMB handgun, with **nine bullets** at the start;
  - one enemy type with periodic invasions;
  - voxel wall destruction;
  - simple construction, repair, upgrade and demolition;
  - real-time clock with gradual day/night; sleep;
  - hunger, hydration, energy and health; death ends the run;
  - a small inventory with a shared household materials pool;
  - four simulated expeditions with event choices;
  - sound with creator overrides;
  - main menu, settings, pause, developer (cheat) menu;
  - single-slot save and load that restores the damaged and rebuilt house.
- **Explicitly out of scope (Experiment 002):**
  - large outdoor areas, additional house maps, classes, multiplayer, procedural worlds;
  - structural-integrity simulation, multi-floor construction, power/plumbing networks;
  - farming, complex crafting, weapon mods, skill trees;
  - extra enemy types, explosive enemies, traders/NPCs;
  - story, cinematics, weather simulation, unlock progression;
  - exports and installers.
  - The Experiment 001 restrictions on sound, survival, saving and building are superseded for this objective.
- **Existing modules / boundaries:** see `docs/experiment-002/SPEC.md` §1.
  - `src/common/`: shared plan, tuning, grid nav, pursuit brain, asset resolver, demo HUD.
  - `src/voxel/` + `src/world/` + `src/build/`: voxel house and construction.
  - `src/props/`: conventional meshes.
  - `src/survival/` + `src/save/`: state and persistence.
  - `src/expedition/`: fog and expeditions.
  - `src/audio/`: sound.
  - `src/ui/` + `src/menu/` + `src/launcher/`: UI.
  - `src/game/`: game root.
  - Experiment 001 demos (`src/modular/`, `src/illustrated/`, and the voxel demo) stay under Visual Experiments as history, not dependencies.
  - No Autoloads: small static classes instead (`GameLaunch`, `GameSettings`, `AssetResolver`, `Sfx`).
- **Testing framework and commands:** A minimal headless GDScript runner (`tests/run_tests.gd`) instead of GUT/GdUnit4, following the user's instruction to keep testing to basic smoke tests for Experiment 001. It is kept for Experiment 002. Since 2026-11-23 it fails a test on any GDScript runtime error. Command: `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd`. Revisit if the project moves into production.
- **Target platforms:** Undecided (desktop assumed; runtime asset overrides cover Windows/Linux only).
- **Asset override notes:**
  - Graphics: `src/common/asset_resolver.gd` resolves `custom/graphics/<logical>.png` over `assets/graphics/<dir>/template_<name>.png` after a restart.
  - Audio (Experiment 002): `custom/audio/<logical>.ogg` over `assets/audio/<dir>/template_<name>.ogg`, through the same resolver.

## History

- **Experiment 001** (approved and delivered 2026-11-23, branch `claude/practical-heisenberg-mjc1xx`, commit `0bb3eb6`). Three playable visual prototypes plus `docs/experiment-001/COMPARISON.md`. Outcome: the user selected true 3D voxels (A) combined with conventional stylized 3D assets. The demos remain under Visual Experiments.

## Current approved development objective

**Status: Approved 2026-11-23, in progress.**

- **User approval (reference / summary):** User message of 2026-11-23, "Experiment 002 — The First Days: from visual experiment to playable survival prototype". One coordinated task with parallel specialist agents in isolated worktrees; the lead integrates and tests.
- **Objective (one):** Turn the voxel showcase into the first playable survival prototype with one complete, minimal, persistent survival loop.
- **In scope:**
  - **Menus and tools:** main menu (New Game, Continue, Settings, Visual Experiments, Quit); settings; pause menu; F10 developer menu with the requested cheats.
  - **World:** the hybrid voxel/mesh house; 0.2 m structural-voxel investigation; construction mode (wall runs, barricades, doors and doorways, a storage crate, a rain collector, repair, upgrade, demolish, last-exit rule); fog-bound lot with a boundary interaction.
  - **Survival:** four simulated expeditions with events and reports; real clock with gradual day/night; sleep (interrupted by invasions); hunger, hydration, energy and health with death; inventory with a household materials pool; nine-bullet start; periodic invasions that damage the house.
  - **Sound and saving:** a sound system with generated template sounds and creator overrides; single-slot save/load with autosave, schema version and safe writes.
  - **Delivery:** automated integrated playthrough, screenshots, documentation.
- **Out of scope:** As listed above. No merge to `main`, no tags, no exports without separate approval.
- **Acceptance criteria / done when:** the Definition of Done in the user's message holds in one coherent game:
  - the player lives in a house that is modifiable, destructible, repairable and reinforceable;
  - time passes; hunger and hydration matter; sleep works;
  - the fog leads to simulated missions with resources and consequences;
  - periodic enemies threaten the house; shooting and ammunition matter;
  - sound works with replaceable assets; the main menu and cheat menu exist;
  - save/load preserves meaningful progress, including the damaged and rebuilt house;
  - the 20-step integrated playtest scenario is run and reported honestly.
  - Work committed and pushed to the working branch.
- **Relevant module tests:** `tests/survival`, `tests/save`, `tests/world`, `tests/build`, `tests/voxel`, `tests/props`, `tests/ui`, `tests/audio`, `tests/expedition`, `tests/game`, `tests/common`.
- **Relevant integration/manual checks:**
  - `tests/test_versions_smoke.gd` (Experiment 001 demos still work);
  - the end-to-end survival playtest (`tools/survival_playtest.*`) across a real application restart;
  - screenshots from the game camera.

## Proposals awaiting user approval

None.
