# Sirens Went Quiet

*Working title.* Present day, after something nobody can explain. The grid is gone, the radio is silent and nobody has heard from another sane human since the sirens went quiet. You still have the house.

This repository holds **Experiment 003 — Foundations of Survival**, a vertical slice built on **Experiment 002 — The First Days**. It is a survival game about one house on one lot, ringed by dense fog. **Experiment 001** (three ways to build a destructible house) is kept as history under *Visual Experiments*.

The loop: **wake → assess needs → plan on the map → scavenge → return home → build and prepare → survive the night → sleep → repeat.**

## Run it

1. Install **Godot 4.7** (developed with 4.7.2 stable, standard build, Forward+).
2. Open this folder in Godot (`project.godot`) and press **F5**, or run `godot --path .` from here. The first open imports the assets, which takes a minute.
3. The main menu has New Game, Continue, Settings, Visual Experiments and Quit.

No executable or installer is produced. Exports haven't been approved yet.

## Playing

**New Game** asks for a difficulty:

| Difficulty | Invasions | Start |
|---|---|---|
| Easy | from Day 4, every 4 days; no bombers until the 4th invasion | 12 rounds |
| Normal | from Day 3, every 3 days | 9 rounds |
| Hard | from Day 2, every 2 days; mixed waves and bombers early | 9 rounds |

You wake on Day 1 at 07:00 with a loaded handgun and no spare rounds, a little food and water, a hammer and a few planks.

- **Needs:** hunger, hydration and energy drain over time. Eat, drink and heal from the inventory (I). Starvation or dehydration costs health, and death ends the run.
- **Equipment (I, Equipment tab):** six slots — primary and secondary weapon, body, back, utility and tool.
  - A vest makes blows and blasts hurt 35 % less.
  - A backpack carries half as much again.
  - A flashlight and a crowbar open places and choices on expeditions.
- **Weapons:** handgun (9 mm, magazine) and shotgun (shells loaded one by one, a spread of pellets). The shotgun is found while scavenging.
- **The region map (M, or the map on the dining table):** a voxel miniature of the region with drifting clouds and 24 places in five kinds: homes, food, medical, construction and weapons.
  - Places you haven't found show as unknown.
  - Pick a place and a purpose to plan a trip; planning takes no game time.
- **The fog:** walk to the edge of the lot and press **E**. The expedition screen preselects your plan.
  - Approaches: general scavenging, targeted collection (much more of one thing), careful exploration (slower, safer, finds new places) and a high-risk raid.
  - Each trip costs travel time and has risk, loot and short decision events. Places run low when you strip them and slowly recover.
- **Building (B):** wood, stone and iron.
  - Stone walls need a foundation (the house floor or a stone foundation).
  - Iron makes barricades, reinforced doors and plating.
  - A workbench turns 3 scrap into 1 iron.
  - Repair uses the damaged material. Stone takes much longer to break than wood, and plating doubles it.
  - You can never seal the last way out.
- **Nights:** invasions arrive at 22:00 as waves built from a threat budget that grows each time. A straggler can come on other nights.
  - The **psycho** bashes its way in.
  - The **runner** is fast and looks for an open way in.
  - The **brute** is slow and smashes walls, three strikes per swing.
  - The **suicide bomber** walks to a weak point in your defences and lights a fuse. A HUD alert and a ring on the ground warn you. The blast leaves a lasting breach, so shoot it first.
- **Sleep:** use the bed. Sleep restores energy, still costs food and water, and is cut short when something arrives.
- **Saving:** the game autosaves after waking, at dawn, after an expedition, after an invasion and after planning on the map. You can also save from the pause menu (Esc). There is one save slot. Experiment 002 saves still load and are upgraded on the spot.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Mouse / LMB | Aim / fire |
| R | Reload |
| Q / 1 / 2 | Next weapon / primary / secondary |
| E | Use the bed, a door, a crate, a collector, the workbench or the map table; at the lot edge, head into the fog |
| I / Tab | Inventory and equipment |
| M | Region map (Esc or M closes it) |
| B | Build mode (see below) |
| Mouse wheel | Zoom |
| Esc | Close a panel or leave build mode, otherwise pause (Resume, Save, Settings, Main Menu) |
| H / F1 | Controls hint |
| F3 | FPS line |
| F10 | Developer (cheat) menu |

**Build mode:**
- **1** walls, **2** barricades, **3** doors, **4** doorway, **5** storage crate, **6** rain collector / workbench, **7** repair, **8** iron plating, **9** demolish, **0** stone foundation.
- Press a class's key again to switch its material (wood → stone, wood → iron, collector → workbench).
- **R** rotates, **RMB** cancels, click-drag for wall runs.

### Developer menu (F10)

It doesn't pause the game. While any cheat is on, a **CHEATS ACTIVE** badge shows. Every button goes through the real systems.

- **Toggles:** invulnerability, unlimited resources.
- **Supplies:** food and water, medical, ammunition, the shotgun and shells, fill magazines, vest and gear, construction materials (+10 planks, stone, iron or scrap), all tools.
- **Needs and time:** set needs; advance an hour; skip to night or morning; time ×1 / ×4 / ×10.
- **Difficulty:** Easy, Normal or Hard.
- **Threats:**
  - next invasion;
  - spawn a psycho, runner, brute or bomber;
  - compose a wave and start it.
- **Map and missions:** run a mission now (any place and approach); reveal all places.
- **House:** repair everything.
- **Inspector:** game and save state.

Cheats are saved with the run. A new game always starts with them off.

### Saving: where and how

The save is `user://savegame.dat`, plus a `.bak` of the previous good save. On Linux that's `~/.local/share/godot/app_userdata/Sirens Went Quiet/`; on Windows, `%APPDATA%\Godot\app_userdata\Sirens Went Quiet\`.

- **What it holds (schema 2):**
  - the clock, stats, difficulty, inventory, equipment, magazines, cheats and invasion progression;
  - the region (known places, stock, visits, lasting consequences, the plan);
  - the player's position;
  - the house: voxel damage and construction, including materials, plating, foundations and blast scorch marks;
  - doors, barricades, crates, collectors and workbenches, with their HP and open state.
- **How it's written:** a temporary file first, which is checked before it replaces the save. If the main file is damaged, the backup is used. Schema 1 saves (Experiment 002) are migrated when loaded.
- **Limitations:**
  - You can't save while asleep, during an expedition or during an invasion, so a live fight is never stored.
  - Death deletes the save.

## Replace the art and the sound

Claude-made fallbacks live in `assets/**/template_*`. Put your own file with the same logical name (without `template_`) in the `custom/` folder, mirroring the subfolders, then restart the game:

- Graphics: `custom/graphics/<dir>/<name>.png`, e.g. `custom/graphics/props/wood_grain.png` or `custom/graphics/voxel/siding.png`.
- Audio: `custom/audio/<group>/<name>.ogg` (or `.wav`), e.g. `custom/audio/weapon/shotgun_fire.ogg`.

A missing or broken override falls back to the template with a warning; it never crashes. The same `custom/` folder next to an exported Windows/Linux game will work the same way, but this is untested because nothing has been exported. Files in `custom/` are yours and are never touched by the project. See `assets/README.md`.

The logical names are listed in `docs/experiment-002/audio.md`, `docs/experiment-002/props.md`, `docs/experiment-002/world.md` and `docs/experiment-001/voxel.md`.

## Docs

- `docs/experiment-003/REPORT.md`: the Experiment 003 report (what was built, tests, the playtest, limitations, screenshots)
- `docs/HANDOFF_EXP004.md`: the state of the code for the next milestone, and what to reuse
- `docs/experiment-003/`:
  - `ASSIGNMENT.md`, `SPEC.md`
  - module docs: `equipment.md`, `construction.md`, `ai.md`, `scavenging.md`, `map.md`
  - `game.md` (the integration)
- `docs/experiment-002/`:
  - `REPORT.md`, `SPEC.md`
  - module docs: `game.md`, `survival.md`, `world.md`, `VOXEL_RESOLUTION.md`, `props.md`, `expeditions.md`, `ui.md`, `audio.md`
- `docs/experiment-001/`: the visual technology experiment and `COMPARISON.md` (history)
- `docs/PROJECT_BRIEF.md`: confirmed decisions and the approved objective
- `docs/BACKLOG.md`: observations deferred during work (not approved tasks)
- `CLAUDE.md`, `docs/GODOT_CLAUDE_GUIDELINES.md`, `docs/DESIGN_WORKFLOW.md`: how work on this project is done

## Tests and checks

```bash
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
```

Add `-- --filter=<text>` to run only the tests whose file or method name contains it.

Through the real renderer (Linux, Xvfb + software Vulkan, slow but deterministic):

- `tools/survival_playtest.sh [out dir]`: the integrated acceptance playtest. It runs in two processes (a new game through save and quit, then continue and verify), with real input events and screenshots. Under software rendering it takes about an hour.
- `tools/playtest.sh <1|2|3>`, `tools/compare.sh <1|2|3>`: Experiment 001 demo checks.
- `tools/capture.sh <res://scene.tscn> <out.png> [seconds] [args]`: one screenshot. Under software rendering, pass `CAPTURE_ENGINE_ARGS="--fixed-fps 30"`.
