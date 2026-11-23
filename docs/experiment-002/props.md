# Props: the hybrid look

Owner: P. Code in `src/props/`, art in `assets/graphics/props/`, generator in `tools/art/props/`, tests in `tests/props/`.

The house structure stays voxel (Version A). Furniture, doors, lamps, appliances, storage, vegetation and yard props are conventional stylized meshes built by `PropKit`. They take Version B's strengths:
- clean low-poly shapes with chamfered edges;
- projected textures with a gentle height-map bump;
- one consistent material.

They also follow Version A's palette and lighting:
- the same sage kitchen, slate sofa, rust armchair, mauve bedding and oak;
- slightly desaturated and warmed in the shader;
- the same Forward+ lights, SSAO and fog.

Post-event wear is built in: dust on every upward face, grime where the wear attribute says so, and small signs of a hurried departure (a cabinet door ajar, a cracked TV, coats on chairs, a toppled photo frame, a dying plant).

## Provenance

Forked from Experiment 001's modular kit (`src/modular/kit/`). Nothing in `src/props/` references `src/modular/` or `assets/graphics/modular/` at runtime; a test checks this.

| Props file | Forked from | Changes |
|---|---|---|
| `prop_mesh.gd` (`PropMesh`) | `mod_mesh.gd` (`ModMesh`) | wear in `COLOR.a`, flags in `UV2.y` (thin sheet, vertical grain, no shadow), `box_inside`, `cylinder_inside`, `sheet`, `ochamfer`, `polyline`, `extrude` |
| `prop_materials.gd` (`PropMaterials`) | `mod_materials.gd` | 20 prop layers; `kit()`, `ghost()`, `cut_materials()`, `reset()` |
| `props.gdshader` | `kit.gdshader` | object-space projection, dust and wear, voxel-quantised cutaway, `lit`, flame and glow layers, section fill on cut pieces |
| `prop_furniture.gd`, `prop_yard.gd` | `mod_furniture_kit.gd` | front turned to −Z, fitted to the plan sizes, A's palette, disorder details |
| `prop_survival.gd`, `prop_ghost.gdshader`, `prop_kit.gd`, `prop_gallery.*` | new | |
| `tools/art/props/make_props_art.py` | `tools/art/modular/make_modular.py` | same algorithms and seeds for four textures; adds `rough_wood` |

The four textures shared with B (`fabric`, `wood_grain`, `concrete`, `asphalt`) are byte-identical copies. The generator reproduces them exactly.

## API (SPEC §7.5)

```gdscript
class_name PropKit
static func make(type: String, size: Vector3, opts := {}) -> Node3D   # visual only, no collision
static func has(type: String) -> bool
static func types() -> PackedStringArray
```

**Additive extensions:**
- `opts.style`: `"plank"` gives a player-built plank door (the default is a painted panel door).
- `opts.ghost`: draws any type with the preview material.
- `opts.tint`: the ghost colour.
- `opts.light`: candles and lanterns get an `OmniLight3D` child named `Light` (shadowed), driven by `set_lit`.
- `set_lit(node, amount)`: sets the `lit` instance parameter on every mesh, plus the optional light.
- `set_tint(node, color)`: sets the ghost colour (rgb + alpha).
- `set_damage(node, damage)`: swaps in the cached meshes for a new damage value. It keeps the node, its transform and the door leaf's swing.
- `set_door_open(node, amount)`: 0 is closed; +1 swings the leaf toward the front, −1 toward the back (`DOOR_SWING` = 1.65 rad).
- `default_size(type)`, `canonical_size(type, size, facing)`, `max_bounds(type, size, facing)`, `node_bounds(node)`, `triangle_count(node)`, `facing_basis(facing)`, `clear_cache()`, `cache_stats()`.
- `PropMaterials.kit()`, `ghost()`, `cut_materials()`.

## Conventions

- **Origin:** the floor centre of the footprint. **Front:** −Z (north) before rotation.
- **Facing:** `opts.facing` ("N", "E", "S" or "W", default N) is applied as the **root's basis**: E = −90°, S = 180°, W = +90° about Y. Set the root's `position`; don't overwrite its whole transform.
- **Size:** the world footprint, as `HousePlan` gives it (plan rect width along X, height, rect depth along Z). A sofa facing E with a 0.95 × 2.4 rect is `make("sofa", Vector3(0.95, 0.85, 2.4), {"facing": "E"})`. Turned pieces swap the canonical width and depth for you.
- **Span pieces** (`door`, `barricade`, `wall_ghost`) accept either order: the longer horizontal side is the span, the shorter one the wall thickness.
- A zero or negative component uses `default_size(type)`. Height 0 is allowed for flat pieces (`rug`, `path`, `road`, `driveway`).
- **Bounds:** everything stays inside the size, except:
  - clutter on tops, up to about 0.1 m;
  - edges and handles, up to 0.06 m;
  - the documented `PropKit.OVERHANG` per type: the bed headboard, the faucet, the vanity mirror and workbench pegboard on the wall behind, water-heater pipes into the wall, cabinet doors and drawers left ajar, the tree crown (the plan size is the trunk), the streetlight arm, the car's open door, spilled rubbish, the leaning mailbox, broken barricade planks at its foot, and the road curb.
- **Seed** varies details: book colours, door paint, plank colours, leaf positions, what lies on tables.
- **Damage** (0..1) is quantised to steps of 1/20.
- **Doors:** the root holds the frame (`Mesh`), and a direct child `Leaf` sits at the hinge. Its own `Mesh` extends 0.904 m along +X and from 0.008 m to 2.05 m up (for a 1 × 2.1 m opening); the handles stand proud of both faces. The leaf is centred in the wall, 0.04 m thick.
  - The frame fills the opening exactly: jambs and head 0.045 m, depth = wall thickness + 0.03 (a 15 mm lip on each face), with a threshold, stops and hinges.
  - **Swing:** rotate `Leaf` about Y. `rotation.y` = 0 is closed; positive swings toward the front (the facing side).

## Types

Triangles are for the plan size (or the default size for the extra types), counting the frame and the leaf for doors.

| Type | Default size (w × h × d) | Tris | Notes |
|---|---|---|---|
| `tv_stand` | 2.0 × 1.1 × 0.45 | 340 | walnut, one emptied cabinet, TV with a crack, dead plant |
| `sofa` | 2.4 × 0.85 × 0.95 | 636 | slate fabric, one cushion askew, blanket half on the floor |
| `coffee_table` | 1.1 × 0.45 × 0.6 | 232 | books, a knocked-over mug and spill, papers |
| `rug` | 3.4 × 0.01 × 2.9 | 2–33 | A's rust and cream motif, a corner kicked over, stains (no shadow) |
| `armchair` | 0.9 × 0.85 × 0.9 | 350 | rust, newspaper on the arm, mug on the floor |
| `floor_lamp` | 0.4 × 1.6 × 0.4 | 148 | unlit fabric shade, sitting askew (no power) |
| `bookshelf` | 1.4 × 1.9 × 0.4 | 912 | gaps where shelves were searched, leaning books |
| `dining_table` | 1.6 × 0.75 × 0.9 | 330 | shrivelled fruit, plate, candle stub, a note |
| `chair` | 0.45 × 0.9 × 0.42 | 186 | slightly turned, sometimes a coat on the back |
| `plant` | 0.5 × 1.1 × 0.5 | 110 | terracotta pot, mostly dying leaves |
| `fridge` | 0.75 × 1.85 × 0.7 | 140 | notes, water stain at the foot |
| `counter`, `sink_counter`, `island` | plan sizes | 254–412 | sage cabinets, oak worktop, a door ajar, things left out |
| `stove` | 0.75 × 0.92 × 0.62 | 394 | cold pot and lid (no range hood: the plan's fixtures are not props) |
| `stool` | 0.4 × 0.7 × 0.4 | 148 | |
| `bed` | 1.6 × 0.6 × 2.1 | 468 | mauve duvet thrown back, headboard |
| `nightstand` | 0.45 × 0.55 × 0.42 | 190 | paperback, glass of water |
| `wardrobe` | 1.5 × 2.0 × 0.62 | 156 | door ajar, a sleeve hanging out, suitcase on top |
| `dresser` | 1.2 × 0.8 × 0.5 | 294 | one drawer out, photo frame knocked flat |
| `bathtub` | 1.7 × 0.55 × 0.8 | 156 | water-line ring, towel over the edge |
| `toilet` | 0.7 × 0.8 × 0.55 | 186 | lid up |
| `vanity` | 0.9 × 0.85 × 0.52 | 336 | cracked mirror on the wall behind |
| `water_heater` | 0.6 × 1.6 × 0.6 | 228 | rusty base ring, pipes into the wall |
| `workbench` | 1.8 × 0.9 × 0.65 | 464 | open toolbox, pegboard with missing tools |
| `washer`, `dryer` | 0.62 × 0.85 × 0.62 | 122 / 174 | the dryer has a heap of laundry on top |
| `shelves` | 1.6 × 1.9 × 0.45 | 392 | half-emptied metal shelving, a tipped can |
| `boxes` | 1.0 × 0.6 × 0.7 | 116 | one box opened and rummaged |
| `deck` | 4.0 × 0.15 × 1.3 | 244 | weathered boards, a cracked board, leaves |
| `path`, `driveway`, `step` | plan sizes | 58 / 27 / 50 | concrete; oil stain, weeds in the joints |
| `road` | 28 × 0 × 1.5 | 178 | the plan lane only: asphalt, low curb, faded edge line, storm drain, leaves |
| `car` | 2.0 × 1.45 × 4.4 | 494 | faded maroon, flat tyre, cracked windscreen, driver's door open |
| `dead_tree` | 0.6 × 4.5 × 0.6 | 764 | branching bark tubes, roots |
| `trash_bin_tipped` | 0.6 × 0.6 × 0.9 | 294 | lies along the longer side, bags and litter spilled to the front |
| `mailbox` | 0.3 × 1.2 × 0.3 | 104 | leaning, lid open, uncollected letter |
| `streetlight_dead` | 0.25 × 4.5 × 0.25 | 172 | dark lamp head, a flyer on the pole |
| `door` | 1.0 × 2.1 × 0.2 | 784 | painted four-panel door (4 colours by seed) or `style: "plank"` (boards, Z brace, scrap patch, rope pull). Damage: cracks from 0.2, panels knocked out from 0.5, a split stile from 0.75, a sagging leaf at 0.95 |
| `barricade` | 1.0 × 2.0 × 0.2 | 480 | two uprights, 3–9 mixed planks (raw, grey, painted) with gaps for bullets, nails, a diagonal brace. Damage cracks planks (they sag at the break), then breaks them: stubs stay nailed on and up to two pieces lie at the front |
| `crate` | 0.9 × 0.6 × 0.6 | 385 | slatted rough planks, dark inside, battened lid askew, rope handles, stencil. Damage knocks out slats and cracks the lid |
| `rain_collector` | 1.0 × 1.6 × 1.0 | 376 | blue drum, tarp on four posts sagging into a funnel, tap and can. Damage tears the tarp, dents the drum and leans a post |
| `candle` | 0.2 × 0.18 × 0.2 | 460 | two or three pillar candles with drips on a saucer, matchbox. Flames only while lit |
| `lantern` | 0.2 × 0.32 × 0.2 | 276 | battery camping lantern: frosted diffuser glows while lit; the guard bars cast no shadow |
| `bush` | 1.2 × 0.9 × 1.0 | 700 | dead shrub: twigs, clinging dry leaf cards, fallen leaves. Damage strips leaves |
| `wall_ghost` | 1.0 × 2.6 × 0.2 | 44 | chamfered block in the translucent ghost material; `set_tint` makes it green or red |

An unknown type returns a crate of the requested size (`prop_type` meta = "crate"), never null.

Every piece except `door` is **one** `MeshInstance3D` named `Mesh`: one surface and the one shared material, so one draw call (plus shadow passes). A door is two (frame and leaf). All 51 plan pieces together are 13,945 triangles.

## Material, shader and integration

**Per vertex:**
- layer in `UV2.x`;
- flags in `UV2.y` (1 thin two-sided sheet, 2 vertical grain, 4 casts no shadow);
- sRGB tint in `COLOR.rgb`;
- wear in `COLOR.a`. Damage raises it (`damage × 0.45`), and outdoor types add 0.12.

**Shader (`props.gdshader`):**
- Textures are projected along the dominant axis in **object space**, with a per-node offset. A swinging leaf or a moved crate keeps its grain, and identical pieces don't repeat.
- Dust (`dust`, `dust_color`) settles on upward faces.
- Grime follows wear, darker near the ground.
- A gentle contact darkening near the floor.
- Global `saturation` 0.9 and a `warm` tint.

**Cutaway:** the uniforms are the voxel surface shader's: `cut_origin`, `cut_dir`, `cut_radius`, `cut_floor`, `cut_near`, quantised on the same 0.1 m grid (`grid_origin`, `voxel_size`). Cut props step in line with cut walls and show the same dark section fill. To enable it, append `PropMaterials.cut_materials()` to `HouseWorld.cut_materials`; `update_view` then drives them.

**`lit` (instance parameter, 0..1):**
- flames are discarded at 0 and flicker when lit;
- wax warms slightly;
- the lantern diffuser glows.
- Nothing else is emissive: lamps and fixtures stay dark because there's no power.

**Ghost (`prop_ghost.gdshader`):** unshaded, translucent, with a rim, facet shading and slow scan lines. Instance parameter `tint`. It casts no shadow.

## Textures and creator overrides

All textures load through `AssetResolver.get_texture("props/<name>", true)`. Put `custom/graphics/props/<name>.png` next to the project or the exported game, then restart. RGB is the colour; alpha is an optional height map (bump). Pieces tint the light, near-neutral textures. Templates are mipmapped.

| Logical name | Used for | Tile |
|---|---|---|
| `props/wood_grain` | furniture wood (tinted per piece) | 1 m |
| `props/rough_wood` | weathered planks: barricades, crates, plank doors, deck, posts | 1 m |
| `props/fabric` | upholstery, bedding, lamp shades (tinted) | 0.5 m |
| `props/concrete` | path, driveway, step, curb, streetlight base | 2.5 m |
| `props/asphalt` | road | 4 m |

Regenerate with `python3 tools/art/props/make_props_art.py` (numpy and Pillow, seeded). Colours of individual pieces are code (the palette constants at the top of each builder file), not textures.

## Performance (headless, this VM)

- Cold build of all 51 plan pieces: 35 ms (including shader and texture load). The same 51 again from the cache: 3.3 ms.
- 200 barricades in 20 variants (4 seeds × 5 damage levels): 27 ms, with 20 builds and 180 cache hits.
- **Cache key:** type, canonical size (mm), damage step, seed and style. Facing is a node rotation, so all four facings share one mesh. The cache clears itself at 1,024 entries.
- No real-GPU frame-rate measurement.

## Gallery

`res://src/props/prop_gallery.tscn`: every type on Version A's voxel ground and floor swatches (read-only use of `voxel/*` art), lit by an instantiated `VoxelLighting` with the house practicals switched off.

User args:
- `--night`: `set_amount(1.0)`; candles and lanterns burn, with lights.
- `--lit`: candles and lanterns burn by day too.
- Camera:
  - `--view=game|close|all`: the game camera (pitch −56°, FOV 40, distance 20), a close view, or the whole gallery;
  - `--group=living|kitchen|bedroom|survival|yard`;
  - `--focus=<type>`;
  - `--dist=<m>`.
- `--nolabels`.
- `--house`: the hybrid look in place. It builds the foundation `HouseWorld`, takes the voxel furniture and fixtures out of its grid (material ids 32–77), and dresses it with every plan piece. It adds:
  - doors in all five doorways (one plank door, one damaged, two open);
  - barricades on the west living-room window;
  - crates, a rain collector, bushes, a build ghost;
  - a lantern on the coffee table and a candle on the dining table.

  The props' cutaway is driven by `HouseWorld.update_view`. `--look=x,z` sets the camera target.

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/props/prop_gallery.tscn /tmp/p.png 1.5 --house --look=5,5.5 --night
```

## Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=props` runs `tests/props/test_props.gd`. It checks:
- every listed type, and every plan piece at its own rect and facing, builds one non-empty mesh that fits its size (with the documented overhangs) and fills it;
- facing turns the front, and the backrest ends up behind it;
- a turned plan rect shares the mesh;
- doors have a direct `Leaf` child at the hinge with the stated size and swing, the frame fits the opening, and either span order works;
- barricade damage changes the mesh and removes plank area, and `set_damage` reuses the cache;
- the cache shares meshes and the one material;
- unknown types and zero sizes fall back;
- `lit`, the optional light, ghost material and tint work;
- textures resolve, and a creator override replaces one;
- nothing references the modular demo.

## Limitations and known issues

- **Damage:** door, barricade, crate, rain collector and bush model damage in the mesh, and the car adds a shattered window. Furniture shows only extra wear and splinters on the floor from damage 0.25.
- **Plan fixtures:** `HousePlan.LIGHTS` fixtures (ceiling lights, range hood, table lamp, bare bulb) have no prop types. The stove has no hood. The gallery's house mode simply removes the voxel fixtures.
- **Road:** only the plan lane. B's road extended 40 m with a far sidewalk and hedge, but that lies inside the fog now.
- **Scaling:** projection is in object space, so a scaled node would stretch its textures. Size pieces through `make`, not by scaling.
- **Cutaway:** furniture is cut like the walls (above `cut_floor`). Thin sheets (leaves, tarp, paper) render both sides instead of the section fill.
- **Lights:** candle flames flicker through `TIME` in the shader whenever lit. The optional lights are shadowed omni lights, so many of them cost shadow passes; the game may prefer its own lights.
- **Verification:** visual checks are lavapipe captures (software Vulkan), not a real GPU. No human has looked at them in motion.
