# Sirens Went Quiet

*Working title.* Present day, after something nobody can explain. The grid is gone, the radio is silent and nobody has heard from another sane human since the sirens went quiet. You still have the house.

This repository holds **Experiment 002 — The First Days**, the first playable survival prototype: one fragile wooden house on one lot, ringed by dense fog. **Experiment 001** (three ways to build a destructible house) is kept as history under *Visual Experiments*.

The loop: **wake → assess needs → scavenge → return home → build and prepare → survive the night → sleep → repeat.**

## Run it

1. Install **Godot 4.7** (developed with 4.7.2 stable, standard build, Forward+).
2. Open this folder in Godot (`project.godot`) and press **F5**, or run `godot --path .` from here.
3. The main menu has New Game, Continue, Settings, Visual Experiments and Quit.

No executable or installer is produced. Exports haven't been approved yet.

## Playing

You wake on Day 1 at 07:00 with nine bullets, a little food and water, a hammer and a few planks.

- **Needs:** hunger, hydration and energy drain over time. Eat, drink and heal from the inventory (I). Starvation or dehydration costs health, and death ends the run.
- **The fog:** walk to the edge of the lot. At the fog, press **E** to head out on a *simulated* expedition. There are four destinations: Nearby Homes, Grocery Store, Hardware Store and Medical Clinic. Each one costs time and has risk, loot and short decision events. A flashlight unlocks the clinic, a crowbar opens stockrooms and a backpack lets you carry more.
- **Building (B):**
  - Wooden wall runs (click-drag), barricades, doors, doorways, storage crates and rain collectors.
  - Repair, metal sheathing and demolish tools.
  - You can never seal the last way out.
- **Nights:**
  - Invasions come on Day 3, 6, 9… at 22:00, a little harder each time.
  - Psychos bash doors, barricades and walls. The holes they make stay until you repair them.
  - A straggler can come on other nights.
  - Survive until they're dead, or until dawn.
- **Sleep:** use the bed. Sleep restores energy, still costs food and water, and is cut short when something arrives.
- **Saving:** the game autosaves at safe moments: after waking, at dawn, after an expedition and after an invasion. You can also save from the pause menu (Esc). There is one save slot.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Mouse / LMB | Aim / fire (one round per shot) |
| E | Use the bed, a door, a crate or a collector; at the lot edge, head into the fog |
| I / Tab | Inventory |
| B | Build mode. In build mode: **1** wall, **2** barricade, **3** door, **4** doorway, **5** crate, **6** rain collector, **7** repair, **8** metal sheathing, **9** demolish; **R** rotates; **RMB** cancels |
| Mouse wheel | Zoom |
| Esc | Close a panel or leave build mode, otherwise pause (Resume, Save, Settings, Main Menu) |
| H / F1 | Controls hint |
| F3 | FPS line |
| F10 | Developer (cheat) menu |

### Developer menu (F10)

It doesn't pause the game. While any cheat is on, a **CHEATS ACTIVE** badge shows.

- Toggles: invulnerability, unlimited resources.
- Supplies: add food and water, ammunition, construction materials, a medical pack or all tools.
- Needs: set hunger, hydration and energy.
- Time: advance one hour, skip to night (20:00) or to morning (06:00), time speed ×1 / ×4 / ×10.
- Threats: trigger the next invasion, spawn psychos.
- House: repair everything.
- An inspector for game and save state.

Cheats are saved with the run. A new game always starts with them off.

### Saving: where and how

The save is `user://savegame.dat`, plus a `.bak` of the previous good save. On Linux that's `~/.local/share/godot/app_userdata/Sirens Went Quiet/`; on Windows, `%APPDATA%\Godot\app_userdata\Sirens Went Quiet\`.

- **What it holds:**
  - the clock, stats, inventory, cheats and invasion progression;
  - the player's position;
  - the house: voxel damage and construction, as diffs against the pristine house;
  - doors, barricades, crates and collectors, with their HP and open state.
- **How it's written:** a temporary file first, which is checked before it replaces the save. If the main file is damaged, the backup is used.
- **Limitations:**
  - You can't save while psychos are around, so a live fight is never stored; an invasion due later is restored by the clock.
  - Death deletes the save.

## Replace the art and the sound

Claude-made fallbacks live in `assets/**/template_*`. Put your own file with the same logical name (without `template_`) in the `custom/` folder, mirroring the subfolders, then restart the game:

- Graphics: `custom/graphics/<dir>/<name>.png`, e.g. `custom/graphics/props/wood_grain.png` or `custom/graphics/voxel/siding.png`.
- Audio: `custom/audio/<group>/<name>.ogg` (or `.wav`), e.g. `custom/audio/weapon/handgun_fire.ogg`.

A missing or broken override falls back to the template with a warning; it never crashes. The same `custom/` folder next to an exported Windows/Linux game will work the same way, but this is untested because nothing has been exported. Files in `custom/` are yours and are never touched by the project. See `assets/README.md`.

The logical names are listed in `docs/experiment-002/audio.md`, `docs/experiment-002/props.md`, `docs/experiment-002/world.md` and `docs/experiment-001/voxel.md`.

## Docs

- `docs/experiment-002/REPORT.md`: the Experiment 002 report (what was built, the integrated playtest, limitations, screenshots)
- `docs/experiment-002/SPEC.md`: module boundaries, contracts and numbers
- `docs/experiment-002/`: `game.md` (game loop and flows), `survival.md` (rules, numbers, save format), `world.md` (house world and construction), `VOXEL_RESOLUTION.md` (0.1 vs 0.2 m study), `props.md`, `expeditions.md`, `ui.md`, `audio.md`
- `docs/experiment-001/`: the visual technology experiment and `COMPARISON.md` (history)
- `docs/PROJECT_BRIEF.md`: confirmed decisions and the approved objective
- `docs/BACKLOG.md`: observations deferred during work (not approved tasks)
- `CLAUDE.md`, `docs/GODOT_CLAUDE_GUIDELINES.md`, `docs/DESIGN_WORKFLOW.md`: how work on this project is done

## Tests and checks

```bash
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
```

Through the real renderer (Linux, Xvfb + software Vulkan, slow but deterministic):

- `tools/survival_playtest.sh [out dir]`: the integrated survival playtest. It runs in two processes (a new game through save and quit, then continue and verify), with real input events and screenshots.
- `tools/playtest.sh <1|2|3>`, `tools/compare.sh <1|2|3>`: Experiment 001 demo checks.
- `tools/capture.sh <res://scene.tscn> <out.png> [seconds] [args]`: one screenshot. Under software rendering, pass `CAPTURE_ENGINE_ARGS="--fixed-fps 30"`.
