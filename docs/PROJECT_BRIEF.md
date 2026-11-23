# Project Brief — Single design and task handoff record

This file **records** decisions and approvals; it never grants them. Only the user can approve scope, in their message in the current conversation. **Undecided = ask, don't choose.**

## Game decisions (user-confirmed only)

- **Game title:** Sirens Went Quiet (working title)
- **Godot version (pin minor):** 4.7 (developed with 4.7.2 stable). Chosen by Claude under the user's 2026-11-23 instruction to make necessary technical decisions autonomously; the template had no prior version.
- **Premise / core player loop:** Modern-day post-event survival centred on one house; the deeper loop (scavenging, crafting, invasions, roguelike days) is context only and **not** approved for implementation.
- **Perspective / art direction:** Undecided. This is exactly what Experiment 001 compares (A: true 3D voxels, B: modular 3D, C: illustrated top-down 2D). Modern setting, stylized, slightly eerie, hand-crafted.
- **Confirmed mechanics and constraints:** For the experiment only: WASD + mouse aim + LMB handgun (unlimited ammo), slow "psycho" enemies, destructible walls in all three versions, day/night toggle, the player cannot die.
- **Explicitly out of scope:** See `docs/experiment-001/SPEC.md` §6 (structural integrity, building tools, crafting, inventory, survival, save/load, progression, extra enemies, advanced AI, multiplayer, sound/music, narrative, exports).
- **Existing modules / boundaries:** `src/common/` (shared plan, tuning, grid nav, pursuit brain, spawner, asset resolver, HUD), `src/launcher/`, and one isolated folder per version (`src/voxel/`, `src/modular/`, `src/illustrated/`).
- **Testing framework and commands:** A minimal headless GDScript runner (`tests/run_tests.gd`) instead of GUT/GdUnit4, following the user's instruction to keep testing to basic smoke tests for this experiment. Revisit if the project moves into production. Command: `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd`.
- **Target platforms:** Undecided (desktop assumed for the experiment; runtime asset overrides cover Windows/Linux only).
- **Asset override notes:** Implemented by `src/common/asset_resolver.gd`: `custom/graphics/<logical>.png` overrides `assets/graphics/<dir>/template_<name>.png` after a restart. Audio overrides aren't implemented (sound is out of scope).

## Current approved development objective

**Status: Approved 2026-11-23, in progress.**

- **User approval (reference / summary):** User message of 2026-11-23, "Visual Technology Experiment 001 — Three Ways to Build a Destructible House", with an execution directive for one autonomous run (parallel agents in isolated worktrees, lead integrates).
- **Objective (one):** Three playable visual prototypes of the same small scenario, selectable from a launcher: A true 3D voxels, B modular 3D, C illustrated top-down 2D. Plus a comparison report.
- **In scope:** Shared house plan and comparable gameplay (movement, handgun, one slow enemy type, spawning, wall destruction with collision and navigation updates, day/night toggle, reset, launcher, controls reference, zoom), attractive visual treatment per technology, template art with override support, smoke tests, screenshots, comparison report.
- **Out of scope:** As listed above. No merge to `main`, no tags, no exports without separate approval.
- **Acceptance criteria / done when:** All three versions launch from the launcher. In each, the player moves and shoots, enemies spawn, path toward the player and can be killed, walls can be destroyed with collision and navigation updated (players and enemies use new openings), day/night toggles, reset and launcher return work. Visual quality is judged from the game camera. Report at `docs/experiment-001/COMPARISON.md`. Work committed and pushed to the working branch.
- **Relevant module tests:** `tests/common/*` (plan, grid nav, pursuit brain, asset resolver).
- **Relevant integration/manual checks:** `tests/test_versions_smoke.gd` (same contract on all three versions); screenshots under the game camera, day and night.

## Proposals awaiting user approval

None.
