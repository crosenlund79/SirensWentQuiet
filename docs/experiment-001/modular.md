# Version B: Modular 3D Construction

Scene: `res://src/modular/modular_demo.tscn` (launcher key **B**). Godot 4.7, Forward+.

The house is assembled at runtime from `HousePlan` using a small kit of reusable pieces on the 1 m grid, rendered as conventional stylised 3D. Each wall piece has four visible damage states. When a piece is destroyed, it drops its collision and opens its navigation cells in the same frame.

## Approach

- **One kit, one shader.** Every static piece (walls, posts, floors, roof, furniture, props, rubble) uses one surface shader (`src/modular/kit/kit.gdshader`). A per-vertex *layer* id selects the material: siding, room paint, trim, section cap, timber, insulation, gypsum, metal, five floor finishes, roof, grass, asphalt, fabric, furniture wood and so on. Textures are sampled in world space, so neighbouring modules line up seamlessly and a module can be moved or swapped without UV work. Texture alpha is a height map, which gives grooves, grout and plank seams a light bump.
- **Modules own their collision.** Each wall module is a `StaticBody3D` (`ModWall`) on the `walls` layer with its own box shapes. `ModHouse` writes the navigation: a destroyed module sets the `GridNav` cells of its *real* footprint (the trimmed `plan_rect`) from `WALL` to `OPEN` and calls `refresh_region()`. The neighbouring posts stay `WALL` and keep their collision.
- **Damage is construction, not fracture.** A damaged wall is modelled as what it is: an exterior skin (siding over sheathing) or drywall, a stud cavity with top and bottom plates and a middle stud, and fibreglass insulation in exterior walls. Holes are jagged 2D polygons cut through each skin, with splintered rims. The broken middle stud, the torn insulation and the room behind show through. Heavy damage centres its hole on where the module was actually hit. Meshes are built procedurally per module (about 1 ms) only at state changes. Intact meshes are shared.
- **Readable interior.** The camera matches Version A (FOV 40, pitch −56°, distance 20, zoom 11 to 32). The roof dissolves (dithered) while the player is inside or behind it. Whole 1 m wall modules between the camera and the player slide down to 1 m, Sims-style, and show a dark section cap (back faces are drawn as a solid "poché"). Shadows still use the full-height walls, so the lighting does not jump. Tall yard props in front of the player dissolve too. The aim ray skips the hidden parts and lands on the visible cut top.
- **Effects are cheap and capped.** Debris chips (splinters, plaster, glass, soil) are CPU-simulated and drawn with one MultiMesh (420, ring buffer). They settle on the floor and stay until they are recycled. Dust puffs use one MultiMesh (160), and sparks and tracers share one additive MultiMesh (96). A breach also throws at most 10 short-lived rigid chunks, which shrink away after 4 s. Bullet holes, gashes and cracks are alpha-blended atlas quads on a per-module MultiMesh, so they follow that module's cutaway and vanish with it.

## Module catalog (`src/modular/kit/`)

| Piece | Class | Notes |
|---|---|---|
| Wall section, solid | `ModWall` (`SOLID`) | 1 m long (shortened next to a post), 2.6 m tall, 0.3 m exterior or 0.2 m interior. Side A (+z) and side B (−z) take the paint of the room they face, through instance uniforms. Exterior side: vertical siding with a concrete plinth band; interior sides: paint with a baseboard |
| Window section | `ModWall` (`WINDOW`) | Opening from sill to head (0.9 m or 1.4 m to 2.1 m), charcoal frame with a transom, window board and metal sill, glass pane. A 2 m window is two modules, read as a double mullion |
| Door section | `ModWall` (`DOOR`) | Open doorway: header, jamb linings, casings (charcoal outside, white inside), threshold, and a door leaf standing open against the wall (front, back or interior style). Not destructible, never blocks |
| Post | `ModPost` | At every wall end and T-junction. Its size is the thickness of the thickest wall there. Indestructible. Outside faces read as charcoal corner boards |
| Floor tile | `ModFloorKit` | 1 m × 1 m. One MultiMesh per finish: oak, ash, bathroom tile, terracotta hex, concrete. A concrete foundation slab sits underneath |
| Roof panel | `ModRoof` | 1 m standing-seam strip from eave to ridge, one MultiMesh per slope (2 × 15). Ridge cap and two siding gables with a vent. 22° pitch, 0.45 m eaves, 0.5 m rakes |
| Furniture and props | `ModFurnitureKit` | One mesh (one draw call) per `HousePlan.FURNITURE` / `PROPS` entry, built from chamfered boxes, prisms and blobs. A footprint box collider on `environment` (height ≥ 1.2 m) or `low_obstacles` |

Damage states (`Tuning.WALL_SECTION_HP` = 10):

| State | Hit points | What you see | Collision / nav |
|---|---|---|---|
| Intact | 10 to 8 | clean; bullet holes appear at the exact impact points | box / `WALL` |
| Damaged | 7 to 4 | two siding boards knocked off (bare sheathing), one hanging loose; chipped plaster inside | unchanged |
| Heavy | 3 to 1 | big jagged hole through both skins with a grime ring, snapped middle stud, torn insulation; window frames hang twisted | unchanged (still blocks) |
| Destroyed | 0 | jagged stubs, a lintel at 1.92 to 2.2 m with hanging studs and insulation, a broken bottom plate, rubble on both sides | **no collision, cells `OPEN`**, same frame |

Windows: the first hit cracks the glass, the second shatters it into a burst of shards. Glass hits do not cost hit points. Bullets then fly through the empty frame, and hits on the sill wall or the head damage the window module like a wall. Enemies who bash a window smash the glass first.

### Grid rules

1. Walls sit on whole-meter grid lines from `HousePlan.WALLS`. Each `wall_spans()` span is cut into 1 m pieces: solid, window or door, one module per meter.
2. Every wall end and every T-junction gets one post module. Modules touching a post are shortened by half the post size, so no two pieces overlap and the corners close. A test checks that every point of every wall centre line lies in exactly one piece.
3. Side A of a horizontal wall faces south (+z); side A of a vertical wall faces west. Paint and the outside face are chosen by `HousePlan.room_at()` half a meter to each side.
4. Floors are 1 m tiles per room rect. Roof panels are 1 m strips over the footprint plus overhangs.
5. A module's `plan_rect` is its real footprint. That rect, and only that rect, is opened in `GridNav` when the module is destroyed.

Because every piece is a node with its own collision, moving, removing, upgrading or replacing one is a node operation plus a `refresh_region()` on its footprint. This experiment only exercises removal by destruction.

## How to play and what to try

WASD moves, the mouse aims, holding LMB fires and the wheel zooms. N switches day and night, R resets, H shows help, F3 shows stats and Esc returns to the launcher.

- Walk into the living room and watch the wall modules in front of you slide down in 1 m steps, while the roof dissolves.
- Shoot one south-wall module about ten times. It goes through bullet holes, loose boards, a ragged hole with insulation and a broken stud, and then a breach with rubble. Walk out through it.
- Shoot a window: the glass cracks, then bursts. Shoot through the empty frame at an enemy outside.
- Let an enemy stand at a wall: it bashes the nearest module and comes in through the breach.
- Press N at night: warm lamps light the rooms, the bathroom bulb flickers, and your weapon light throws shadows through breaches and windows.

Screenshot scenarios (`tools/capture.sh ... --scenario=<name>`): `overview`, `exterior` (roof on), `damage` (the four states side by side on the south facade), `breach`, `enemies`, `shooting` and `kit` (every kit piece and state laid out and labelled). Scenario mode applies view changes instantly and pre-simulates debris, because the software renderer shows only a few frames before the capture.

## Art: logical names and overrides

All textures load through `AssetResolver.get_texture("modular/<name>", true)`. Put `custom/graphics/modular/<name>.png` next to the project or the exported game, then restart. RGB is the colour and alpha is an optional height map; an override without alpha renders flat. All textures are seamless. The tile size in meters is set in the shader.

| Logical name | Used for | Tile |
|---|---|---|
| `modular/siding` | exterior wall boards (also gables) | 2 m |
| `modular/plaster` | interior paint (tinted per room) | 2 m |
| `modular/floor_wood` | living room oak | 2 m |
| `modular/floor_wood_light` | bedroom ash | 2 m |
| `modular/floor_tile` | bathroom tiles | 1 m |
| `modular/floor_kitchen_tile` | kitchen terracotta hexagons | 1.4 m |
| `modular/concrete` | utility floor, driveway, plinth | 2.5 m |
| `modular/roof` | standing-seam roof | 2 m |
| `modular/grass` | dead lawn (sampled at two scales) | 4 m / 9.3 m |
| `modular/asphalt` | street | 4 m |
| `modular/fabric` | upholstery, bedding, rugs (tinted) | 0.5 m |
| `modular/wood_grain` | furniture wood (tinted) | 1 m |
| `modular/marks` | 2 × 2 atlas: bullet hole, gash, crack web, glass impact (real alpha) | — |

The templates are generated by `python3 tools/art/modular/make_modular.py` (numpy and Pillow; seeded). Module meshes are procedural, not files. An artist-made mesh per state is the natural next step (see Known issues).

## Performance (measured)

- **Kit:** 290 modules (71 wall, 12 post, 126 floor tiles, 30 roof panels, 51 furniture and props). The intact walls total about 2,700 triangles.
- **Draw calls** (HUD, 1600×900, including shadow passes): about 240 to 340 by day and about 130 for the kit sheet. Night is higher (about 840 to 900) because the five shadowed practicals, the weapon spot light and the moon render shadow maps. The hood light and bedside lamp cast no shadows to save draws. One material, MultiMeshes for floors, roof, grass, debris and marks, and one mesh per furniture piece keep this low.
- **CPU (headless):** the scene builds in about 100 ms (instantiate and ready). Per module state change: the damaged mesh takes 0.4 ms, heavy 1.1 ms, destroyed 1.1 ms and rubble 0.6 ms. Per frame: cutaway, camera and stats take 0.12 ms, and effects with full pools take 0.29 ms. A 60 s soak with auto-fire and spawning (16 modules destroyed, enemies dying and being freed) produced no errors.
- Software-rendered screenshots run at about 1 fps under lavapipe, so that figure says nothing about real-GPU speed. Judge by the draw calls and mesh sizes above.

## Tests

`tests/modular/test_modular_kit.gd`:
- grid coverage (every wall point lies in exactly one piece; 71 modules, 12 posts);
- the damage-state thresholds, plus collision off when destroyed;
- the window glass-then-frame order;
- doors are indestructible;
- a destroyed module opens exactly its footprint while the post stays blocked;
- the cutaway lowers modules in front of the player, aiming skips the hidden parts and the roof hides;
- an enemy wall swing damages the nearest module.

The shared `test_versions_smoke.gd::test_modular_smoke` also passes. Run them with `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=modular`.

## Known issues and limitations

- Modules are built in code, so opening a kit piece in the editor shows nothing (there are no `@tool` previews and no per-module `.tscn`). Swapping in artist-made meshes per state would need a small hook (for example, an exported mesh per state) that this experiment does not add.
- No structural integrity: the roof and the lintels stay up over destroyed sections (out of scope).
- Debris chips do not collide with walls and land on a single floor height (3.5 cm), so outdoors they hover slightly. Rigid chunks collide only with floors and walls.
- The cutaway also lowers the open door leaves, which then read as small boxes from above.
- A 2 m window is two 1 m modules (a double mullion), and each half is damaged separately.
- Furniture is not destructible, and low furniture does not stop bullets (by the shared spec).
- Shots are traced from the body centre at muzzle height, so you cannot shoot through a wall you are hugging. The tracer is drawn from the visible muzzle.
- Scenario screenshots use instant transitions and pre-simulated debris (see above). In normal play everything is time-based.
