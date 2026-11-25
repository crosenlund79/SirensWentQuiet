# Experiment 005 — A House Worth Living In: contracts

**Approval:** the user's message "Overnight Milestone — A House Worth Living In" (2026-11-25, autonomous overnight, Rapid Delivery).
**Branch:** `exp005/house-worth-living-in`. It starts from Refinement 01 (`d953f1d`) plus the user's audio upload (`25027c3`). The branch name is outside the Windows-build triggers, so no CI builds run.
**Rules:** no exe, no CI builds, light tests, the user playtests.

## Agents and ownership

| Agent | Scope (user's §) | Owns |
|---|---|---|
| **V** | §2 five levels: building upstairs that feels natural, levels −2..+2, stairs, excavation to −2, the roof on the top storey, support for higher storeys, a level indicator, enemies across levels | `src/levels/`, `src/world/house_support.gd`, `game_support.gd`, `voxel_support.gd`, roof parts of `src/voxel/voxel_yard.gd`, level hooks in `build_mode.gd` |
| **F** | §3 storage furniture, §7 placing, moving and rotating furniture, contents dropped on destroy | `src/world/world_object.gd`, `house_furniture.gd`, `build_pieces.gd`, the furniture parts of `build_mode.gd`, new `src/home/storage*.gd`, `src/ui/storage_panel.gd`, prop meshes for new furniture types in `src/props/` |
| **C** | §4 comfort, §5 mood, §6 rooms, §8 windows, light and warmth, their UI | new `src/home/comfort*.gd`, `src/home/rooms.gd`, mood in `src/survival/` (`mood.gd`, plus fields in `game_state.gd`), a Home/Comfort panel in `src/ui/`, a small HUD indicator |
| **A** | §11 audio: the inbox, layered ambience, footsteps, Eli's voice, the requirements audit | `src/audio/`, `src/game/footsteps.gd`, `assets/audio inbox/` docs, `docs/experiment-005/AUDIO.md` |

The lead does integration, the shared dev menu and docs.

**Shared hot files:** `survival_game.gd`, `dev_menu.gd`, `game_state.gd`, `house_world.gd`, `build_mode.gd`, `game_hud.gd`.
- Make small, commented ("Exp 005 (X)"), additive edits.
- Put logic in your own new files.
- In `survival_game.gd`, use helpers created in `_assemble()` (the `game_*.gd` pattern).
- In `dev_menu.gd`, use one appended section function plus one call line.

## 1. Levels (owner V)

- **Storey ids:**
  - −2 lower basement
  - −1 basement
  - 0 ground floor
  - +1 first upper floor
  - +2 second upper floor

  Nothing below −2 or above +2.
- **API:**
  - `game.levels.player_storey: int`
  - `game.levels.world_of(storey) -> HouseWorld`: 0 is the ground `HouseWorld`; the others are `LevelWorld`s, or null when not built.
  - `game.levels.storeys() -> Array[int]`: the storeys that exist, sorted.
  - `signal storey_changed(storey)`
  - `signal levels_changed`: a storey was created or removed.
  - `Levels.NAMES[storey]`: display names.
- **Common rules:** every storey is a `HouseWorld` (or a subclass), so objects, furniture, damage and save work the same on all of them. Agents F and C iterate `storeys()` and call world methods; they never special-case one storey.

## 2. Furniture (owner F)

**Type names** are shared by F (meshes, placement, storage) and C (comfort). These are the `HousePlan.FURNITURE` `type`s plus a few new ones:
- **Existing:** sofa, armchair, chair, coffee_table, dining_table, tv_stand, bookshelf, plant, rug, bed, nightstand, wardrobe, dresser, fridge, stove, counter, sink_counter, island, stool, bathtub, toilet, vanity, washer, dryer, water_heater, workbench, shelves, boxes, floor_lamp.
- **New (F adds meshes):** cupboard (kitchen cupboard), storage_chest, tool_cabinet, painting (wall-hung), table_lamp.

**Enumeration for comfort (F provides):**
- `HouseWorld.furniture_items() -> Array` of `{"type", "rect": Rect2, "rot", "state": "intact"|"damaged", "id"}`;
- original pieces and placed furniture together, destroyed or removed pieces excluded;
- `signal furniture_layout_changed` on the world: place, move, remove, destroy, damage state change, load.

**Storage (F provides):**
- `HouseWorld.storage_of(id) -> Dictionary` (item → count) for any storage piece;
- capacities per type;
- contents saved with the world;
- on destroy or demolish, the contents drop into a recoverable loot pile object.

**Placed lamps:** shine while the house has power (`game.home` / the fuse box `mains_on`, the same rule as the electric fixtures). Expose `is_lit()` on lamp objects.

## 3. Comfort and mood (owner C)

- **Rooms:** regions of each storey's floor bounded by walls, windows and closed doors, found by flood fill. A region open to the outside is "exposed".
- **Comfort per room:** recomputed on events only, never per frame:
  - **events:** structure changes, `furniture_layout_changed`, power changes, fireplace on/off, time-of-day buckets for daylight;
  - **diminishing returns** per category;
  - **labels** inferred from contents.
- **API:**
  - `game.comfort.room_at(storey, plan_pos) -> Dictionary` with `{"label", "comfort", "level_name", "factors": [[text, delta], ...]}`;
  - `game.comfort.house_comfort() -> float`.
- **Mood:** `GameState.mood` (0..100), saved, older saves get the default. It updates at sensible intervals or after events. Effects are modest: energy recovery and sleep quality.

## 4. Audio (owner A)

- **The inbox:** `assets/audio inbox/` is the documented drop folder. The existing upload in `assets/audio/_inbox/` is read as well; nothing is moved. Both are scanned recursively, and descriptive filenames map to logical sound names through a documented table.
- **Fallbacks:** the existing template sounds and `custom/` overrides keep working.
- **New logical names** for the layers: ambience (outdoor, indoor, basement), the fireplace (positional, only while lit), details (owls, wolves, creaks), voice (Eli), music (theme). Footsteps are per surface (snow, wood, cement), with steps sliced from the recordings and triggered by the gait.
