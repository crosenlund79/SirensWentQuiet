# Construction, materials and explosions (Experiment 003)

Owner: C. Code: `src/world/` (HouseWorld, WorldObject, preview scenarios), `src/build/` (BuildMode, BuildPieces, BuildPalette, Workbench), `src/voxel/` (materials, blast carve, blast effect, yard), `src/props/` (iron styles). Tests: `tests/world/`, `tests/build/`, `tests/props/`, `tests/voxel/`. Contract: SPEC-003 §4 and §5; this extends `docs/experiment-002/world.md`, which still describes everything not changed here.

What is new:
- three structural materials: timber (the house frame and wooden walls), **stone masonry** and **iron plating**;
- a foundation piece, iron barricades, reinforced doors and a workbench (scrap to iron);
- repair paid in the damaged material;
- section materials and a load-bearing hook;
- explosions done properly, and wall targeting for the bomber;
- world save version 2, which still loads Experiment 002 saves.

## Resources and pieces

Costs use the household inventory (`GameState.pay`; the unlimited cheat makes them free). Wood means planks. Scrap stays a raw material: the workbench turns it into iron.

| Key | Class | Piece (variant) | Cost | Notes |
|---|---|---|---|---|
| 1 | Walls | Wooden wall | 4 planks + 6 nails per m | Experiment 002's wall (0.2 m of boards and studs). |
| 1 again | | **Stone wall** | 6 stone per m | Masonry, 0.3 m thick, full height. Needs a foundation: the house floor or a stone foundation. |
| 0 | Foundation | **Stone foundation** | 2 stone per 1 m × 1 m tile | Paving slabs centred on a wall line, flush with the house floor. Drag to lay a strip; parallel strips make a floor. No effect on navigation or collision; no grass grows through it. |
| 2 | Barricades | Barricade (wood) | 2 planks + 4 nails per m | 12 HP. |
| 2 again | | **Iron barricade** | 3 iron + 1 plank + 2 nails per m | 30 HP. Steel posts and flat bars. Bullets pass between the bars, bodies don't. |
| 3 | Doors | Door (wood) | 4 planks + 6 nails + 1 scrap | 18 HP. |
| 3 again | | **Reinforced door** | 4 planks + 6 nails + 3 iron | 42 HP. A plank core under riveted steel plates with straps. Opens and closes like any door. |
| 4 | Doorway | Doorway | free | Unchanged. |
| 5 | Storage | Storage crate | 3 planks + 4 nails | Also raises the stone cap (+20) and the iron cap (+10): K's item caps. |
| 6 | Equipment | Rain collector | 2 planks + 2 nails + 3 scrap | Unchanged. |
| 6 again | | **Workbench** | 5 planks + 6 nails + 2 scrap | Press E at it to turn 3 scrap into 1 iron. |
| 7 | Repair | Repair | the damaged material | Timber: 1 plank per 150 missing voxels + 1 nail per 60 (Experiment 002's rate). Masonry: 1 stone per 90. Iron plate: 1 iron per 60. Objects: the lost-HP fraction × their own cost, at least 1 of their main material. |
| 8 | Reinforce | **Iron plating** (was "metal sheathing") | 2 iron + 4 nails per 1 m section | Same `METAL_SHEET` voxels as in Experiment 002, now drawn as riveted iron plates (0.5 × 0.6 m, dark seams, rivets, rust near the ground). Allowed on wooden, stone and house walls; not on windows. |
| 9 | Demolish | Demolish | refunds half | Uses each piece's own cost. A foundation is taken up only when no stone wall stands on it. |

Rules that stay as before:
- grid snapping: walls on 1 m segments of integer plan lines; objects on 0.5 m cells, R rotates;
- ghost previews and drag-placed runs (walls, barricades, foundations, up to 12 m);
- collision and furniture checks, "Someone is standing there", the hammer rule;
- the exit rule: walls, barricades and objects may not seal the last way out;
- refusal reasons in the status line.

New refusal reasons:
- "Stone walls need a foundation: the house floor or a stone foundation."
- "There's already a floor here." (a foundation on the house floor or on paving)
- "Take the stone wall down first." (demolishing a foundation that carries a stone wall)
- "Windows can't be plated."
- "Already plated with iron."

### The palette

Palette layout:
- **Class buttons:** one per building class, pieces first, then the tools: `1 Walls · 0 Foundation · 2 Barricades · 3 Doors · 4 Doorway · 5 Storage · 6 Equipment | 7 Repair · 8 Reinforce · 9 Demolish`.
- **Variant row:** shown when the class has more than one material, e.g. `Wood · 4 planks, 6 nails` and `Stone · 6 stone`.

Pressing a class's key again cycles its materials. A class remembers the variant last used: after 2, 2 (iron barricade), then 3, the next 2 picks the iron barricade again. The bar shows planks, stone, iron, nails and scrap. A run shows its total, e.g. "run 3 m: 18 stone" or "3 tiles: 6 stone".

`BuildPieces.LIST` keeps its first nine entries in their Experiment 002 order. So `select(i)` with i = 0–8 and `select_id(...)` still pick the same pieces. Keys 1–9 pick the same class as before: key 2 still means barricade and key 7 still means repair. The new pieces are variants or key 0.

## Material strength (measured)

`tests/world/test_material_strength.gd` measures each wall. The house wall is the plain south wall at x = 8.5. The other walls are 3 m long, standing in the yard on y = 11. Each count is the number of actions until the nav cell in the middle of the hole becomes walkable (a walk-through breach):
- **Shots:** handgun shots from 1.8 m away, aimed at random points of the 0.9 m × 1.6 m hole area, as a player keeps shooting at what still stands.
- **Bites:** `enemy_strike` from 0.6 m outside. A brute's swing is `strength` 3, which means three bites in one swing.
- **Blasts:** `explode` 0.55 m outside, centred 1.0 m above the ground, radius 1.6 m, power 24.

Headless run on the shared VM, 0.2 m damage blocks (the game's setting):

| Wall | Shots | Psycho bites | Brute swings | Blasts to breach | Voxels removed by the first blast |
|---|---|---|---|---|---|
| House wall (frame, 0.3 m) | 19 | 13 | 5 | 1 | 1,502 |
| Wooden wall (0.2 m) | 19 | 10 | 4 | 1 | 1,620 |
| Wooden wall + iron plating | 78 | 21 | 7 | 1 (a smaller hole) | 552 |
| Stone wall (0.3 m) | 78 | 72 | 24 | 2 | 476 |
| Stone wall + iron plating | 84 | 201 | 67 | 3 | 240 |

`HouseWorld.SECTION_MATERIALS` records these as the strength of each section. The house frame is 1.0, a wooden wall 0.9 and a stone wall 3.0, and iron plating multiplies a section's strength by 2.0 (`PLATED_FACTOR`).

How the materials resist:
- **Shots:** a shot whose first voxel is masonry or mortar carves at 0.55 × the radius (`STONE_CARVE`) and barely penetrates. Sheet metal carves at 0.45 × the radius, as before. The block carve's mean hardness is high for both: masonry 0.9, mortar 0.6, plate 0.92.
- **Bites:** a bite into masonry is 0.6 × the bite radius (`STONE_BITE`); into plate, 0.55 × (`SHEET_BITE`). Experiment 002 used 0.65 for plate; 0.55 keeps plated stone stronger than bare stone.
- **Blasts:** see the next section.

## Explosions

`HouseWorld.explode(center, radius, power) -> Dictionary`, a refinement of the version in the Experiment 003 foundation:

1. **Structure.** `VoxelCarver.carve_blast` carves the same 0.2 m blocks that shots carve.
   - A block goes when its distance from the centre is less than the blast's reach (`radius`, ragged by ±15 % per block). Vertical distances count 75 %, so a blast at body height tears the wall down to the floor.
   - Material in between uses up the reach. `VoxelMat.BLAST` gives the metres of reach that one metre of each material absorbs. A block also pays for half a block's thickness of its own material.
   - Armour values: timber framing 1.2–2, siding 1.5, insulation 0.6, mortar 4.5, masonry 6, iron plate 9, screed 5.
   - The result: a timber wall goes over a wide area. A stone wall loses its face and keeps its core. Plate shields what is behind it.
   - Glass in reach shatters, whole panes. The foundation slab (`FOUNDATION`, never carved) stays.
   - Paths are measured on the grid before anything is removed. The usual crumble then runs over the crater's box (loose crumbs, strips, floating fragments).
2. **Scorch.** Exposed voxels within 1.35 × radius are darkened toward soot, in the current grid only. The darkening is saved with the world, and repair restores the design's colours.
3. **Objects.** Every object within 1.5 × radius loses up to `power` HP. The damage is `power × (1 − d / reach)^0.75 × (1 − armour between / reach)`, where d is the distance to the object's footprint and the armour is measured before anything breaks. So a wall shields a crate behind it: in the test, a crate behind a stone wall lost 4 HP and one in the open lost 7.
   - Wooden objects break before iron ones because of their HP: a close blast at power 24 destroys a wooden door (18 HP) and leaves a reinforced door (42 HP) damaged.
   - Destroyed objects emit `object_destroyed(kind, at)` as before.
4. **Navigation and collision** are updated before `explode` returns. Damage only opens WALL cells, and destroyed objects open theirs. The sections near the crater are recounted exactly.
5. **Effect** (`VoxelFx.blast`):
   - a flash (an orange OmniLight3D, 0.55 s) and a chunky, translucent fireball;
   - up to 150 debris chunks in the removed voxels' own colours (splinters for wood, plates for metal), plus splinters in a destroyed object's colours;
   - 36 sparks, a ring of dust rolling out along the ground, and a column of dark smoke.
   - About 30 ms of meshing runs in the blast's own frame, so the crater appears together with the flash; the rest of the scorch meshes over the next frames.
   - Sounds: `structure/break` + `structure/crumble`, plus `structure/blast` if that template exists (none does yet).
   - The camera shake is the game's.
6. **Ground scar.** A ragged scorch decal on the ground, recorded in `scars` and saved; there are at most 24, and the oldest goes first. Indoors, the floor voxels show the scorch instead.

Return value:

```
{"voxels": int removed, "hit": [object kinds], "destroyed": [object kinds],
 "opened": nav cells that became walkable, "breach": bool (a WALL cell opened),
 "sections": [Vector3i] wall sections that lost voxels, "ms": float}
```

Invalid input (NaN, a negative radius, infinite power) does nothing. The radius is capped at 4 m. `stats["blast"]` holds the timing of the last blast: prep, carve, apply, scorch, objects, mesh.

**Cost**, measured headless on the shared VM:

| Blast at | Total time | Carve (evaluate + crumble) | Apply (collision, nav, sections) | Scorch | Meshing in the frame |
|---|---|---|---|---|---|
| A 3 m wooden yard wall | 37–58 ms | about 25 ms | — | — | — |
| The house's south wall (it reaches the floor slab) | 110–140 ms | 64 ms (22 + 42) | 8–11 ms | 6 ms | up to 30 ms |

That is a one-off hitch at the moment of the flash. The 30 ms meshing budget is `BLAST_MESH_BUDGET_MS`.

**Suggested bomber numbers** (AI owns them):
- radius 1.6 m and power 24, centred at the bomber's position about 1.0 m up;
- it stands at `weak_points()[i]["pos"]`, about 0.5 m from the wall's outer face.
- With these, one blast breaches a wooden wall, a house wall or a wooden door. A stone wall needs two blasts, plated stone three. A reinforced door survives one blast at contact range.

## Weak points (the bomber's targets)

`HouseWorld.weak_points(from: Vector2, near := Vector2.INF) -> Array`, best first. The candidates are:
- closed doors and barricades;
- the exterior house walls and every player-built wall, wherever their outside can be reached on foot.

Interior walls are not candidates. Neither are sections that are already walkable through, or sections that hold a door or barricade (those are listed as objects).

Each entry:

```
{"kind": "door" | "barricade" | "wall",
 "pos": Vector2,      # where the attacker stands: the first walkable nav cell 0.3-1.2 m out from the OUTSIDE face
 "target": Vector2,   # centre of the door, barricade or wall section
 "score": float,      # higher = better target
 "seg": Vector3i, "object": WorldObject or null,
 "material": "wood" | "iron" (objects), "frame" | "wood" | "stone" (walls),
 "strength": float}   # relative resistance (a wooden door = 1)
```

`score = protection / strength + proximity bonus − distance penalty`:
- **Protection:** door 1.0, barricade 0.9, wall 0.6.
- **Strength of an object:** its HP divided by 18, a wooden door's HP.
- **Strength of a wall:** `section_strength × remaining integrity × √(how much of a full wall the section is)`. Windows and damaged walls are therefore weaker, and stone and plated walls stronger.
- **Proximity bonus:** up to 0.8 for lying within 8 m of `near`. Pass the player's position.
- **Distance penalty:** 0.03 per metre from `from`, the attacker.

The "outside" is away from the house for house walls and away from the bed for built walls, the same side build mode uses for a wall's outer boards.

`tests/world/test_explosions.gd` checks the ranking:
- on the intact house, a closed door ranks first;
- every stand point is outside the house, walkable and within 1.3 m of its target;
- the south wall's stand point is on the south face;
- a damaged section ranks above an intact one, and an iron-plated section below a plain one;
- a wall next to `near` ranks above the same wall far away;
- a wooden wall ranks above a stone wall;
- a reinforced door counts as more than twice as strong as a wooden one;
- a breached section drops out of the list.

## Sections and the load-bearing hook

Each `sections[seg]` entry now carries:
- `"material"`: "frame" for the original house walls, or "wood" or "stone" for built walls;
- `"strength"`: SECTION_MATERIALS × PLATED_FACTOR when the section is plated;
- `"orig"`, `"design"` and `"current"`, as before.

The live counts no longer drift after blasts:
- removed voxels below the wall rows (sole plates) no longer decrement `current`;
- `explode` recounts every section near its crater exactly.

New queries:
- **`section_strength(s)`:** material strength × plating.
- **`section_load_hint(s) -> float`:** the hook for a future support model; nothing reads it yet, and there is no collapse simulation. The value is `load × integrity × foundation × plating`:
  - load: house frame 1.0, timber 0.6, stone 2.5;
  - integrity: the live 0..1;
  - foundation: 1 on a floor or foundation, 0.5 (`UNFOUNDED_LOAD`) otherwise;
  - plating: × 2.
  - Example values: an intact house wall 1.0, an unfounded wooden yard wall 0.3, a stone wall on a foundation 2.5.
- **`is_founded(s)`:** the 0.3 m wall footprint stands at least 85 % on house floor, screed or paving.
- **`section_missing_by(s)`:** missing voxels by repair resource: `{"wood", "stone", "iron"}`.
- **`section_info(s)`** gains `material`, `strength`, `founded`, `foundation` and `load`.

## Objects

- **Materials.** `WorldObject` has `mat` ("wood" | "iron"). `kind` stays "door" or "barricade", so every rule for doors and barricades applies to both materials:
  - navigation;
  - bashing and `enemy_strike`;
  - the exit rule;
  - E to open a door;
  - the cutaway.
- **Material data.** `WorldObject.MATS` holds the iron variants' name, HP, PropKit style and impact kind. Queries: `has_mat(kind, mat)`, `max_hp_of(kind, mat)`, `name_of(kind, mat)`, `display_name()`, `front_dir(rot)` (the attacker's side) and `debris_tones()`. `to_dict()` adds `"mat"`.
- **The workbench** is a new kind: 1.0 × 0.9 × 0.5 m on 0.5 m cells, 14 HP, layer 1, SOLID for navigation. Its visual is PropKit's furniture workbench.
  - Prompt: "[E] Workbench · 3 scrap → 1 iron".
  - `interact(game)` calls `Workbench.convert(game.state, 1)` and toasts the result.
- **`Workbench.convert(state, batches)`** (`src/build/workbench.gd`):
  - For a `GameState` it calls K's `Crafting.convert_scrap(state, batches)`. That rule is all-or-nothing per unit, limited by the scrap owned and the iron cap; the unlimited cheat makes the scrap free. When nothing is made, the toast shows K's `reason`.
  - Any other object with an `inventory` (tests) gets a local fallback with the same 3 → 1 rule.
  - Amounts are read back from the inventory. Returns `{ok, iron, scrap, text, via}`.
- **PropKit styles.** PropKit takes `style: "iron"` for doors (a reinforced leaf, a steel frame, peeling plate at high damage) and for barricades (steel bars that bend, then tear off). `tests/props/test_props.gd::test_iron_styles` checks their bounds and damage meshes.

## Persistence (world save version 2)

`save_data()` writes `"version": 2` and adds three fields to Experiment 002's format:
- `"stone"`: the built sections that are masonry, as `[[axis, line, start]]`;
- `"foundations"`: as `[[axis, line, start]]`;
- `"scars"`: as `[[x, z, radius]]`.

Objects carry `"mat"`. The voxels themselves travel in the existing grid diffs: masonry, paving, plate and the scorch colours.

`load_data()` accepts versions 1 and 2:
- **A version 1 save** (Experiment 002) loads with defaults: every built wall wooden, no foundations, wooden objects, no scars. Sheathed sections load as iron plating; it is the same voxels.
- **Validation** follows Experiment 002's rules, plus:
  - object materials must exist for their kind;
  - HP must not exceed that material's maximum;
  - scars must be finite, inside the yard and at most 24.
  - Anything invalid is refused before anything is built.
- `tests/world/test_world_save_v1.gd` loads `tests/world/fixtures/exp002_world_v1.bin`. That save was written by the untouched Experiment 002 world code, with damage, built walls, objects, sheathing and a cut door. The test checks what the save holds (711 missing voxels, the objects, the hole, the wall), then blasts the loaded house, re-saves it as version 2 and reloads it identically.
- After three blasts, a stone wall, a wooden wall and an iron barricade, a save is 38 KB.

## Other API additions (all additive)

- **`shoot(origin, dir, exclude, muzzle := INF, max_range := Tuning.SHOT_RANGE)`:** the ray length; requested by K for the shotgun's 14 m. Nothing beyond the range is hit (kind "none"), and the tracer ends at the range.
- **`enemy_strike(attacker_pos, target, strength := 1.0)`:** an object takes `round(strength)` damage. A wall gets `round(strength)` bites in one swing; below 1, one smaller bite.
- **`build_walls(segs, material := "wood")`**, **`build_foundation(segs)`**, **`remove_foundation(s)`**, **`floor_coverage(s)`** and **`foundation_at(p)`**.
- **`place_object(kind, p, rot, is_built := true, mat := "wood")`** and **`damage_object(o, n, from, quiet := false)`**.
- **`BuildMode`:**
  - `select_slot(slot)` and `slot()`;
  - `FOUNDATION_REASON`, `RUN_PIECES`, `FREE_PIECES`;
  - `_has_hammer()` uses `GameState.can_build()` when it exists.
- **`BuildPieces`:** `SLOTS`, `SLOT_ORDER`, `variants(slot)`, `slot_of(i)`, `object_cost(kind, mat)`, `wall_cost(material)`, `section_repair_cost_by(missing)`; `object_repair_cost` takes an optional `mat`.
- **`BuildPalette`:** signals `slot_pressed(slot)` and `variant_pressed(index)`; `slot_labels()`.
- **`VoxelMat`:** `MASONRY` (18), `MORTAR` (19), `PAVING` (20) and the `BLAST` table.
- **`VoxelCarver`:** `carve_blast(g, center, radius, seed, quantum := 2, v_scale := 0.75)`, `blast_armour(g, a, b, budget)`, `last_blast_ms`.
- **`VoxelFx`:** `blast(center, radius, change, extra_colours)` and `blast_active()`.
- **`VoxelWorld.mark_visual_dirty(lo, hi)`:** remesh without a collision rebuild.
- **`VoxelYard`:** `tuft_avoid` and `set_tuft_avoid(rects)`. The tufts are rebuilt from the same random sequence, so the Experiment 001 demo's yard is unchanged.

The Experiment 001 voxel demo uses none of the new paths (carve_sphere, impact and the yard defaults are untouched). `tests/voxel` passes.

## Integration (what the game and UI must call)

Phase B wires these up. Nothing needs to change for building itself: `BuildMode.setup(world, state, camera, player)` and `set_active` work as before, and BuildMode handles its own number keys (1–9 and **0**).

1. **Bomber (AI).**
   - Get targets with `world.weak_points(Vector2(bomber.x, bomber.z), Vector2(player.x, player.z))`. Walk to `entry["pos"]` and face `entry["target"]`.
   - On detonation, call `world.explode(Vector3(pos.x, 1.0, pos.z), 1.6, 24.0)`. Characters are hurt through the game's `detonated(at, radius)` handler (SPEC-003 §5). Shake the camera there.
   - The result's `breach` and `opened` tell the director a new opening exists. Nav `revision` increases as usual.
2. **Brute (AI).** Call `world.enemy_strike(pos, target, 3.0)` per swing, instead of calling it three times.
3. **Weapons (K).** `WeaponHandler` detects `shoot`'s 5th argument and passes the weapon's range. Nothing to wire.
4. **Workbench.** The game's interact flow already calls `interact(self)`. The workbench reads `game.state` and calls `game.toast(text, kind)`; SurvivalGame has both.
5. **HUD and inventory.** Show stone and iron next to planks, nails and scrap. Crates still feed `state.inventory.storage_crates = world.count_objects("crate")`, which raises stone and iron caps as well (K's `cap_per_crate`).
6. **Save (SaveGame schema 2).** Keep storing `world.save_data()` and calling `world.load_data(d)`. A version 1 world dictionary inside an Experiment 002 save loads as it is; no migration code is needed. Re-saving writes world version 2.
7. **Toasts.** `object_destroyed(kind, at)` is unchanged, so "The door gave way!" also covers reinforced doors. For the material, look the object up before it is removed, or use `WorldObject.name_of(kind, mat)` where the object is at hand.
8. **F10.**
   - Materials: add stone and iron through `state.inventory.add` (caps apply; the unlimited cheat as before).
   - "Repair the house" stays `world.repair_all()`. It restores voxels, scorch colours and object HP; ground scars stay.
   - Optionally, "blast here" can call `world.explode(point, 1.6, 24.0)` for testing.
9. **Docs and settings.** The build keys are 1–9 plus 0 (foundation), and pressing a class's key again switches its material. The README and the settings key list still say 1–9 (lead or Phase B).

## Preview scenarios and screenshots

`res://src/world/world_preview.tscn` takes `--scenario=<name>` (see the script's header). These scenarios are new:
- `materials`: stone versus wooden walls;
- `iron`: plating, a reinforced door, iron barricades;
- `foundation`: a stone pad, a stone wall going up, a valid stone-wall ghost with the palette;
- `workbench`;
- `blast`: the aftermath;
- `blast_fx`: the blasts at `--blast-at` seconds;
- `palette`.

```bash
CAPTURE_ENGINE_ARGS="--fixed-fps 10" LP_NUM_THREADS=1 tools/capture.sh res://src/world/world_preview.tscn /abs/out.png 2 --scenario=materials
CAPTURE_ENGINE_ARGS="--fixed-fps 10" LP_NUM_THREADS=1 tools/capture.sh res://src/world/world_preview.tscn /abs/out.png 1.7 --scenario=blast_fx --blast-at=1.6
```

Captures (software Vulkan under Xvfb, 1600 × 900) are in `/home/user/swq3-shots/c/`:

| File | Shows |
|---|---|
| `c_materials.png` | A 3 m stone wall: coursed grey blocks, light mortar joints, a dark cap, the foundation strip at its foot. Beside it, a 3 m wooden plank wall. |
| `c_iron.png` | A yard wall with two iron-plated sections and one bare. Iron, wood and iron barricades. The reinforced front door (dark plates, straps), between two plated sections of the house wall. |
| `c_foundation.png` | A 4 × 3 m stone pad: flagstones, no grass through it. A 2 m stone wall on it, a green ghost for 2 m more, and the palette with the Wood / Stone variant row. |
| `c_workbench.png` | The workbench (pegboard of tools, toolbox, vise) between a rain collector and a storage crate in front of the house. |
| `c_blast_fx.png` | 0.1 s after two blasts. The scene is lit orange. Stone chunks burst from the stone wall's crater; wood splinters fly into the house front from the wooden wall; fireballs, sparks and dust. |
| `c_blast_after.png` | 5 s later. The stone wall stands with a sooty crater and rubble at its foot. The wooden wall is gone: the blast took 2.6 m, and the floating-fragment rule dropped the two short ends. A scorch mark lies on the lawn; dust settles. |
| `c_palette.png` | The palette with the stone wall selected and the variant row, over a stone pad with a valid ghost. |

## Tests

```bash
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=<name>
```

- `test_material_strength`: the table above. It checks that stone needs at least 2.5× the shots and bites of wood, plating at least 1.5× the shots, one blast breaches wood, and stone survives one blast.
- `test_explosions`:
  - a breach opens nav and collision in the same frame;
  - fewer voxels are removed from stone and iron;
  - objects are damaged by distance, material and shielding;
  - doors are destroyed or survive by material;
  - the slab never goes, the floor is cratered and scorched, and repair cleans the scorch;
  - bad input does nothing;
  - persistence round trip after three blasts (grids including scorch, nav, scars, foundations, sections, objects), and bad scars and materials are refused;
  - the weak-point ranking.
- `test_world_save_v1`: the Experiment 002 fixture loads, works and re-saves; bad version 1 data is still refused.
- `test_build_materials`:
  - costs per material are paid;
  - stone walls need foundations, and the foundation refusals;
  - iron barricades and reinforced doors (HP, brute strength, repair costs, refunds);
  - repair is paid by material;
  - the load hint;
  - demolishing stone walls and foundations;
  - the workbench (a stand-in state, Crafting through a real GameState, the cheat, persistence);
  - palette classes, variants and keys.
- `test_props::test_iron_styles` and `test_house_world::test_shoot_respects_max_range`.
- Experiment 002's world, build, props and voxel tests still pass. Two expected messages in `test_build_mode` were renamed: "Windows can't be plated." and "Already plated with iron."

## Limitations

- **No collapse.** `section_load_hint` is only a hook; nothing reads it.
- **Built walls in the yard stand on nothing but their sole plate or a foundation.** After a big blast, short leftover pieces count as floating fragments and fall (see `c_blast_after.png`).
- **Shots against plate and masonry** remove few voxels. A player can still shoot through a plated or stone wall eventually (78–84 random shots), which is deliberate but high.
- **The workbench** reuses the furniture workbench mesh. Its pegboard hangs in the air when the bench stands in the open. No detailed art, by policy.
- **Blast cost** is 40–140 ms on this VM in GDScript, mostly the crumble pass. That is acceptable for a rare event; a native carve would be the fix if blasts become frequent.
- **Stone and iron numbers** are tuned for the suggested bomber values. Another radius changes the breach counts.
- **No `structure/blast` sound template exists**, so a blast uses break + crumble.
- Not human-played; no real-GPU timing.
