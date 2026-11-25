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

## Previous objective (Experiment 002)

**Status: Approved 2026-11-23. Delivered on the working branch 2026-11-24** (report: `docs/experiment-002/REPORT.md`; integrated playtest 23/23 across a real restart). Not merged.

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

## Previous objective (Experiment 003)

**Status: Approved 2026-11-24 (queued behind Experiment 002, which was delivered at `4c87cd6`). Integrated and published 2026-11-24 as the playtest checkpoint `playtest/exp003-integrated`** (report: `docs/experiment-003/REPORT.md`; suite 385/385; integrated playtest part 1 15/19, part 2 6/6 across a real restart, with the failures documented). Not merged.

- **User approval:** User message of 2026-11-24, "Queued Assignment — Experiment 003: Foundations of Survival", recorded in `docs/experiment-003/ASSIGNMENT.md`.
- **Objective (one):** A systems-first vertical slice:
  - equipment and weapons (handgun + shotgun);
  - wood, stone and iron construction;
  - consolidated survival;
  - a reusable enemy AI with psycho, runner, brute and suicide bomber;
  - difficulty and a threat-budget invasion director;
  - an expanded data-driven scavenging system (24 locations);
  - an interactive voxel city map with drifting clouds;
  - persistence and dev tools for all of it.
- **Decisions recorded:** contracts and phases in `docs/experiment-003/SPEC.md`.
  - Phase A: five parallel module agents (K, C, AI, X, M).
  - Phase B: one integration agent (game, UI, save v2, playtest).
- **Out of scope:** structural collapse simulation, multi-floor construction, crafting beyond one scrap → iron example, detailed art, SirenVoxelLibrary assets, exports. No merge to `main`.
- **Acceptance:** the 20-step vertical slice in `ASSIGNMENT.md` §13, with focused tests, an integrated playthrough and screenshots (especially the city map, enemy behaviours and construction).

## Current approved objective: "Make This House a Home" (Experiment 004)

**Status: Approved by the user's message of 2026-11-24 ("SIRENS — Make This House a Home", execution mode: Rapid Delivery). Delivered 2026-11-24 on the working branch and as the playtest checkpoint `playtest/exp004-house-home`, with a Windows build artifact from GitHub Actions; awaiting the user's playtest.** Record: `docs/experiment-004/ASSIGNMENT.md`; report: `docs/experiment-004/REPORT.md`.

- **Scope (one milestone, as the user bundled it):**
  - destruction lifecycle (intact / damaged / rubble);
  - live main-menu siege;
  - northern atmosphere (darker nights, aurora, pines, snow, snowy map, a lit fireplace);
  - destructible and demolishable furniture and house structures with refunds (full refund for player-built pieces);
  - electrical lights, switches and a destructible, rebuildable fuse box;
  - an equipment / quick-access bar with an unarmed pose;
  - the forest destination and a repairable car as expedition gear;
  - door fix, door reinforcement, boarded windows and metal doors;
  - replaceable floors, stairs, an upper floor and basement excavation with a shovel;
  - sink and fridge interactions, Shift sprint;
  - persistence;
  - a **Windows build delivered as a GitHub Actions artifact**: this explicitly approves the export preset and the CI build workflow.
- **Verification:** basic only (build, launch, new game, systems reachable, no fatal errors, save/load). The user playtests.
- **Supersedes in practice:** the earlier, not-started Experiment 004 directive below. Its overlapping parts (upper floor, basement, stairs) are delivered here in the player-built form this milestone asks for.

### Experiment 004 — Playtest Refinement 01 (approved 2026-11-24)

- **Approval:** the user's message "Experiment 004 — Playtest Refinement 01" (Rapid Delivery, minimal testing). Baseline `playtest/exp004-house-home` (`fa31537`), which stays unchanged. Work goes on the new branch `exp004/refinement-01`.
- **The seven fixes:**
  1. walking animation matched to movement;
  2. the fireplace moved off the kitchen opening;
  3. no floating attachments after demolition;
  4. simplified structural support (roof and upper floor need their outer walls; inner walls carry nothing);
  5. a rotatable camera (Z / C);
  6. upstairs building and roof visibility (V roof toggle);
  7. direct wall replacement.
- **Out of scope:** Windows builds, GitHub Actions builds, audio work, long playthroughs, extensive reports. No merge to `main`.

## Current approved objective: "A House Worth Living In" (Experiment 005)

**Status: Approved by the user's message of 2026-11-25 ("Overnight Milestone — A House Worth Living In", autonomous overnight, Rapid Delivery). Delivered on the branch 2026-11-25 (report: `docs/experiment-005/REPORT.md`; suite 457/457); awaiting the user's playtest.** Branch `exp005/house-worth-living-in`, built on Refinement 01 plus the user's audio upload. Contracts: `docs/experiment-005/SPEC.md`.

- **Scope:**
  - five-level house architecture (−2..+2) with natural upstairs construction, basements by excavation, upper storeys, support, stairs and save;
  - functional storage furniture with placement, moving and rotation;
  - room comfort and Eli's mood with modest effects and UI;
  - windows, light and fireplace warmth in room conditions;
  - an audio inbox convention, layered ambience, surface footsteps, Eli's voice lines and an audio requirements audit.
- **Out of scope:** executables, installers and Windows CI builds; new enemy types or locations; generated replacement audio (unless a temporary fallback is necessary); a general overhaul. No merge to `main`.
- **Verification:** light. The project loads; all five levels are reachable via dev tools; construction works upstairs and underground; storage works; furniture survives save and load; comfort and mood update; no fatal errors.

## Current approved objective: "Defensive Living" (Experiment 006)

**Status: Approved by the user's message of 2026-11-25 ("Next Milestone — Defensive Living", Rapid Delivery, autonomous). Delivered on the branch 2026-11-25 (report: `docs/experiment-006/REPORT.md`; suite 484/484); awaiting the user's playtest.** Branch `exp006/defensive-living`, built on Experiment 005 plus the user's Pixel Operator font. Contracts: `docs/experiment-006/SPEC.md`.

- **Scope:**
  - subtler aurora;
  - wooden and metal spikes;
  - excavatable trenches and water moats;
  - one- and two-tile drawbridges;
  - a categorised construction menu;
  - moderately more dangerous enemies;
  - a Library location with skill books and a small research tree gating metal construction;
  - window removal into a solid wall;
  - a functional TV and radio;
  - buildable foundations in structural support;
  - shotgun integration verified;
  - the gun store verified (it already exists);
  - construction paid from house storage;
  - a UI overhaul with the Pixel Operator font and a coherent icon set.
- **Out of scope:** executables and Windows CI builds; merges to `main`; large test campaigns.

## Current approved objective: "The House Has Ears / Beyond the Front Door" (Experiment 007)

**Status: Approved by the user's message of 2026-11-25 ("Combined Milestone — The House Has Ears / Beyond the Front Door", autonomous Rapid Delivery). Delivered on the branch 2026-11-25 and as the source-only checkpoint `checkpoint/exp007-scavenging` (report: `docs/experiment-007/REPORT.md`; suite 519/519); awaiting the user's playtest.** Experiment 007 had not started before, so this is one combined milestone. Branch `exp007/house-has-ears` from Experiment 006. Contracts: `docs/experiment-007/SPEC.md`.

- **Scope:**
  - playable scavenging replaces the dialogue expeditions: visible travel on the regional map (on foot and by car), enterable POIs (Pine Woods, Convenience Store, Public Library, plus a reusable placeholder for other locations), physical looting with persistence, enemy encounters, return home with offscreen home consequences;
  - room visibility at home and in POIs;
  - the structural overview (4 modes, 5 levels);
  - event-based noise and straggler behaviours;
  - observation holes;
  - electronic security (motion sensors, alarms, turret mounts using inventory firearms, an automatic reload upgrade, research);
  - audio integration and the production report;
  - save and load across home, travel and POI.
- **Delivery:** source-only checkpoints (`checkpoint/exp007-*`). No exe and no Windows CI builds; no merge to `main`.

## Earlier Experiment 004 directive (approved, not started)

**Status: Approved by the user's directive of 2026-11-24 ("Immediate Directive + Experiment 004 — A House to Live In"). Not started: the user's later message of 2026-11-24 asked to finish Experiment 003, publish the checkpoint, write `docs/HANDOFF_EXP004.md` and stop; Experiment 004 continues in a fresh session.**

- **Objective (one, as directed):** a modest three-floor suburban house (basement: workshop, storage, stairs; ground floor: kitchen, living room, hallway, front and rear entrances, stairs; upstairs: two bedrooms, bathroom, landing) with the existing survival, combat, construction, scavenging and save systems working in it; then lightweight room visibility, event-based noise, and a structural overview (four modes, floor selection), with F10 tools for them. The previous house is preserved as an alternative.
- **Order:** finish 003 → house → visibility → noise → overview → handoff, publishing playtest branches at playable stages. No Experiment 005.
- **Out of scope:** observation holes, sound-wave or per-voxel acoustics, a second simulation for the overview, a continuously rendered minimap, redesigning the invasion director, exports, merges to `main`.
- **Handoff:** `docs/HANDOFF_EXP004.md`.

## Workflow decisions (user, 2026-11-24)

- **Playtest checkpoints:** at each meaningful playable milestone, push a stable branch `playtest/<milestone>` and keep developing elsewhere. Never commit to, force-push or rewrite a published checkpoint. The user's directive explicitly allows these branches beyond the three-branch guideline.
- **Human playtesting first:** brief smoke verification (import, relevant tests, a short launch check) instead of long or repeated automated playthroughs; minor defects are recorded for the user's playtest.
- **Repository boundary:** this project's sessions work only on `crosenlund79/SirensWentQuiet`. The SirenVoxelLibrary Asset Foundry directive was sent here by mistake and is revoked for these sessions; its assets aren't imported.

## Proposals awaiting user approval

None.
