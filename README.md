# Sirens Went Quiet

*Working title.* A modern-day, post-event survival game centred on one house. This repository currently holds **Visual Technology Experiment 001: three ways to build a destructible house**. It's three small playable showcases of the same scenario, built to compare technologies. It is **not** the game yet.

| | Version | Technique |
|---|---|---|
| **A** | True 3D Voxels | Volumetric walls, chunked mesh rebuilds, irregular holes |
| **B** | Modular 3D | Reusable grid-aligned wall/door/window/furniture pieces with damage states |
| **C** | Illustrated 2D | Top-down ink-and-wash illustration with destructible wall sections |

## Run it

1. Install **Godot 4.7** (developed with 4.7.2 stable, standard build, Forward+).
2. Open this folder in Godot (`project.godot`), or run `godot --path .` from here.
3. Press **F5**. The launcher appears: click a version or press **1 / 2 / 3**.

Controls in every version: **WASD** move · **mouse** aim · **LMB** (hold) shoot · **wheel** zoom · **N** day/night · **R** reset · **Esc** back to the launcher · **H** hide help · **F3** stats.

The player cannot die. Shoot walls to open holes: you can walk through them and the "psychos" will use them too.

## Replace the art

Claude-made fallback art lives in `assets/graphics/**/template_*.png`. To use your own, put a PNG with the same logical name (without `template_`) in `custom/graphics/` (same subfolder), e.g. `custom/graphics/illustrated/floor_wood.png`, and restart the game. The same works with a `custom/` folder next to an exported Windows/Linux executable. Details: `assets/README.md`.

## Docs

- `docs/experiment-001/COMPARISON.md`: the comparison report (results of the experiment)
- `docs/experiment-001/SPEC.md`: the shared scenario, numbers and contracts
- `docs/PROJECT_BRIEF.md`: confirmed decisions and the approved objective
- `CLAUDE.md`, `docs/GODOT_CLAUDE_GUIDELINES.md`, `docs/DESIGN_WORKFLOW.md`: how work on this project is done (from the starter pack)
- `docs/BACKLOG.md`: observations deferred during work (not approved tasks)

## Tests

```bash
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
```

Screenshots through the real renderer (Linux, Xvfb + software Vulkan): `tools/capture.sh <res://scene.tscn> <out.png> [seconds] [--night]`.
