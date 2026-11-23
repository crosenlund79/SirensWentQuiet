# Version C: Illustrated top-down 2D

*Sirens Went Quiet, Experiment 001.* A hand-inked, top-down 2D version of the shared house, visually rooted in **The Witchening Tales** (PhasmoOnSpeed) but modern: a wooden single-storey house with contemporary furniture, consumed by something nobody explains. Scene: `res://src/illustrated/illustrated_demo.tscn` (launcher key **3**).

## Play it

Shared controls: **WASD** move, **mouse** aim, **LMB** (hold) shoot, **wheel** zoom (12 to 34 m wide), **N** day/night, **R** reset, **Esc** launcher, **H** help, **F3** stats. The F3 line shows standing wall sections, practical lights and live psychos.

Things to try:

- Shoot one stretch of wall and watch it go through its states: bullet holes, cracks and chipped drywall, broken planks with the studs and insulation showing, then collapse (dust, flying planks, debris on both sides, splintered ends on the neighbours). About 10 hits per 1 m section.
- At night, shoot a hole in a wall next to a lit room and step outside: the room's light spills through the hole onto the lawn. A badly broken (not yet removed) section already leaks a thin shaft of light.
- Shoot a window: the first hit cracks the glass, the second shatters it (shards on both sides), then the frame breaks like a wall.
- Walk through your new hole. The psychos use it too (or bash their own: about 10 swings per section).
- Kill a psycho: hit flash, stagger and knockback, then it collapses into a drawn fallen pose and fades after 4 s.
- Day/night: overcast day with drifting cloud shadows and soft "sun" shadows; night has warm practical lamps, a failing bathroom tube, moonlight through the north and west windows, the car's hazard lights and your weapon light, which casts real shadows.

Screenshot scenarios (also handy to look at a state quickly): `--scenario=overview|damage|breach|enemies|shooting|collapse`, `--night`, `--slowmo-at=SECONDS` (fire one shot, then slow time to 3 % to catch the flash), `--view=METERS` (close-ups below the gameplay zoom range) and `--override-root=DIR` (load creator art from another folder, see below). Example:
`LP_NUM_THREADS=2 tools/capture.sh res://src/illustrated/illustrated_demo.tscn /tmp/c.png 5 --hide-help --scenario=breach --night`

## What I took from the reference

From `docs/VISUAL_STYLE_DNA.md`, the art kit in `tools/art/` and `scripts/world/*.gd` of The Witchening Tales:

- **Reused (copied with provenance):** `core.py`, the whole drawing kit: inked masks with a wobbling outline, hatched cool shadow band at the lower right, warm rim at the upper left, paper grain, wood/noise/fabric textures, supersampled Lanczos output. The floor helpers (label maps, bevels, ink seams, cracks), the token construction (dark base disc, rim ring, facing notch, ground shadow) and furniture helpers (cushion, groove, book, paper) were adapted.
- **Same rendering approach:** strict orthographic top-down; art at 2x density; characters as round tokens facing +X and rotated in-engine; furniture authored front-down and rotated in 90 degree steps; seamless floors on UV-repeated polygons; `CanvasModulate` ambient plus warm `PointLight2D` pools with Gaussian textures and PCF5 shadows; `LightOccluder2D` on walls; flicker by summed sines; motion by transforms and tweens only; procedural effects; the cool-ambient/warm-light colour relationship.
- **House authoring there:** JSON room rectangles rasterised to a cell grid; walls are whole cells, drawn as thick dark brick caps from one 128 px tile plus ink lines; doors are cells; occluders are merged cell rectangles; walls are not destructible.
- **Changed for this game:**
  - All content is modern: oak plank floors, patterned cement kitchen tiles, matte bathroom tiles, polished concrete, a deck, a lawn, asphalt, flat-pack and mid-century furniture.
  - Walls follow the thin plan walls (0.3/0.2 m), so they are drawn as tileable *cut sections* (charcoal cladding, dark stained top plate, painted drywall) instead of thick cell caps.
  - Forward+ instead of Compatibility.
  - Occluders use back-face culling, so wall tops stay lit while still casting shadows.
  - Furniture shadows are drawn at runtime and blurred together (no baked drop shadows), because baked ones would rotate with the piece.
  - Added a screen-space grade (desaturation, vignette, paper grain).

## Approach

Scale: **64 world px per meter**, template art **128 px per meter**. Everything is built from `HousePlan` at runtime; no scene authoring beyond the root node.

| Module (`src/illustrated/`) | Responsibility |
|---|---|
| `illustrated_demo.gd` | Scene root: wiring, gunfire (hitscan), camera, spawning, HUD, smoke-test debug API, screenshot scenarios |
| `house_view.gd` | Ground and room floors, the subfloor under walls, furniture and props (sprites, collision, tall-piece occluders), decor, fixtures, fenced yard boundary |
| `walls.gd` | Posts at every wall junction (indestructible, SOLID in nav), wall sections from `wall_spans` (about 1 m, windows as 1 m panes), door frames and open leaves, enemy bashing, nav sync |
| `wall_section.gd` | One destructible section: HP, per-0.125 m chunk damage, bullet holes, glass, light leak, removal (collision, occluder, nav in the same frame) |
| `lighting.gd` | Day/night blend: ambient, practicals, glows, moonlight through windows, cloud shadows, hazards, shadow strength, grade |
| `fx.gd` | Muzzle flash with a brief shadow-casting light, tracer, casings, material impacts (wood, cladding, plaster, glass, metal, flesh), floor specks, debris decals, collapse burst |
| `player.gd`, `enemy.gd`, `token.gd` | Characters: movement, `PursuitBrain`, token presentation (facing, sway/bob, recoil/lunge, hit flash, night self-light), death |
| `ill_art.gd` | Scale and z-layer constants, `tex()` through `AssetResolver`, art manifest, tiny procedural particle textures |

**Walls and destruction.**
- Each section is a `StaticBody2D` on layer `walls` with a `LightOccluder2D` (none for windows: glass lets light through). It draws its tileable strip region per run of chunks, choosing the intact, cracked or broken strip per chunk from the hits around it.
- On top of the strip it draws a world-consistent shadow band and rim plus a heavy ink edge, and keeps up to 18 bullet holes where the bullets struck the face.
- Light leak: at a third of its HP, the occluder splits around the most damaged chunk, so a sliver of light passes while collision stays.
- Removal, all in the same frame: collision layer cleared, shape disabled, occluders freed, the section's `span_rect` cells set `OPEN` and `refresh_region` called. Debris, dust and planks are spawned and the neighbours draw torn, splintered ends. The OSB sill under the wall shows through the gap.
- Section HP is `round(WALL_SECTION_HP * length)`, so 9 to 10 hits for the 0.85 to 1 m sections. The smoke-test hole at (8.5, 9.0) is the section x 8.0 to 8.95, about 10 shots.
- Enemies bash the nearest standing section within 0.3 m of the swing target (`ENEMY_WALL_DAMAGE` per swing, chunk damage but no bullet hole).

**Lighting.**
- Day: cool overcast ambient, soft shadows (a `CanvasGroup` of black silhouettes blurred with mipmaps, offset down-right by height) and slowly drifting cloud shadows.
- Night: dark blue ambient. The `night_on` lights glow warm with PCF shadows (the bathroom tube flickers and drops out on summed sines). Four cool moonlight lights shine in through the north and west windows, the car's hazard lights blink and the player carries a cone weapon light (shadowed) plus a faint self light.
- Characters get a faint unshaded copy at night so they stay readable in the dark.
- One blend factor tweens everything over 0.55 s.

**Characters and effects.**
- The player is a token with a dark jacket, a rust-orange accent (pack straps, hood lining), a backpack and a two-handed handgun.
- Psychos are pale, hunched, in a torn hoodie or a stained office shirt, on a red-ringed base.
- Walking sways and bobs the token; shots kick it back; swings lunge it forward and nudge the camera.
- Death crossfades into an illustrated fallen pose that slides along the shot.

**Camera.** Strict top-down `Camera2D`, smoothed follow with a small look-ahead toward the aim, 22 m default width, 12 to 34 m zoom, small shake on shots and collapses.

## Art list and how a creator replaces it

All art loads through `AssetResolver.get_texture("illustrated/<name>", true)`. To replace a piece, draw a PNG and save it as `custom/graphics/illustrated/<name>.png`, in the project or next to an exported Windows/Linux build, then restart the game. Missing or invalid files fall back to `assets/graphics/illustrated/template_<name>.png`. **Any resolution works:** each kind of art is scaled to a fixed real-world size (table), so drawing at 2x or 4x the template just gives a crisper result. Keep the template's proportions and orientation; open the template PNG as a tracing layer. Regenerate templates with `python3 tools/art/illustrated/generate.py` (about 3 minutes).

| Group | Logical names | Template px | What the PNG covers, pivot, orientation |
|---|---|---|---|
| Floors (10) | `floor_wood`, `floor_wood_light`, `floor_tile`, `floor_kitchen_tile`, `floor_concrete`, `floor_deck`, `ground_grass`, `ground_concrete`, `ground_asphalt`; `floor_subfloor` | 512x512; 256x256 | Seamless tile = 4 m x 4 m (`floor_subfloor`: 2 m x 2 m, the sill under walls). World-aligned. |
| Wall strips (6) | `wall_ext`, `wall_ext_cracked`, `wall_ext_broken`, `wall_int`, `wall_int_cracked`, `wall_int_broken` | 512x56, 512x42 | Horizontally seamless, 4 m long. Wall band = middle rows (ext 8 to 48 of 56, int 8 to 34 of 42), transparent margins for splinters. **Top of `wall_ext` = outside** (cladding); the game turns it to face out. No directional light (the engine adds it). |
| Windows (4) | `window`, `window_cracked`, `window_shattered`, `window_broken` | 128x56 | One 1 m pane, same vertical layout as `wall_ext` (top = outside, sill at the bottom = inside). |
| Wall bits (3) | `wall_post` (post end grain, core 40 of 56 px), `door_leaf` (0.9 m door, hinge at the left end, 1/16 m margin), `fence` (4 m seamless strip, body = middle half) | 56x56, 132x23, 512x32 | |
| Furniture (30) | `sofa`, `armchair`, `coffee_table`, `tv_stand`, `floor_lamp`, `bookshelf`, `dining_table`, `chair`, `plant`, `rug_living`, `rug_bed`, `bath_mat`, `counter`, `sink_counter`, `stove`, `fridge`, `island`, `stool`, `bed`, `nightstand`, `wardrobe`, `dresser`, `bathtub`, `toilet`, `vanity`, `water_heater`, `workbench`, `washer` (also the dryer), `shelves`, `boxes` | e.g. sofa 323x138, bed 221x285, chair 74x70 | Footprint seen from above, **front facing down (+Y)**, plus a 1/16 m transparent margin on every side; centred pivot; the game rotates it by `facing` (N 180, E -90, W +90 degrees). Footprint = the `HousePlan` rect (width and depth swapped for E/W). `counter` is drawn 1.0 m long; the game stretches only its middle so it fits any length. |
| Props (5) | `car` (2.3 x 4.6 m, nose down), `dead_tree` (4.6 m canopy, trunk at the centre), `trash_bin` (tipped bin), `mailbox`, `streetlight` (0.8 x 4.4 m, pole at the centre, arm reaching down) | 310x605, 605x605, ... | As furniture. Tree branches and the lamp head draw above characters. |
| Details (8) | `papers`, `shoe`, `toy`, `mud_trail`, `leaves`, `ceiling_light`, `bulb`, `table_lamp` | small | Scaled by width only (aspect kept), centred, placed by the decor table in `house_view.gd`. |
| Debris (3) | `debris_planks`, `debris_plaster`, `debris_glass` | 144x106 | Drawn 0.75 to 1 m wide where a section collapses, randomly rotated. |
| Characters (5) | `player`, `psycho_a`, `psycho_b` (1 m square token, **facing +X**, centred); `psycho_a_dead`, `psycho_b_dead` (2 m x 1 m fallen pose, head toward +X) | 128x128, 256x128 | Rotated in-engine; keep the drop shadow inside the canvas. |
| Light textures (2) | `light_soft` (radial falloff), `light_cone` (apex at the centre, pointing +X) | 512, 1024 | Intensity only (white RGB, alpha = light). |

A demonstration, without touching `custom/`: three deliberately different "hand-drawn" PNGs (a mustard marker-style sofa at 2x density, a red-coat player and white-board exterior walls) were loaded with `--override-root=<folder>` and replaced the templates with no code change (`creator_override_demo.png`). `test_creator_override_replaces_art_at_any_resolution` checks that an override at another size still covers the same footprint. If a creator replaces only `wall_ext`, the cracked and broken states still come from the templates, so draw all three for a consistent wall.

**Doodle Nook fit:** everything is a flat RGBA PNG at a known real-world size with one fixed orientation rule per kind. A drawing app only needs a canvas preset per kind (for example "furniture: footprint + 1/16 m margin, front down") and an export to `custom/graphics/illustrated/<name>.png`. No rigging, UVs, meshes or animation frames are needed. The template generator can also export blank guide sheets later if wanted.

## Effort and numbers

- **76 PNGs** in total: 10 floors, 13 wall-kit, 30 furniture, 5 props, 8 details and fixtures, 3 debris, 5 characters, 2 light textures. Destroying walls needs only **6 wall strips + 4 window states** (plus 3 debris decals). Everything else is ordinary set dressing that any 2D game needs.
- Generated by about 3,100 lines of Python (650 of them the adapted core kit); the game code is about 2,400 lines of GDScript, including the tests.
- Performance (headless timings, no GPU here):
  - Building the scene takes about 135 ms: 794 nodes, 66 sections, 12 posts, 70 occluders, 15 point lights (10 with shadows, all lit at night; by day only the 4 shadowless hazard lights).
  - Destroying a section (nav refresh, debris, particles) takes about 3 ms; a shot with all its effects about 0.14 ms.
  - Draw calls (shown with F3): about 270 to 400 at the default view, about 600 for the whole-house overview.
  - Under lavapipe software Vulkan the screenshots run at 2 to 8 fps, which says nothing about a real GPU. The 2D workload is small; the main GPU cost is the shadowed lights at night.

## Tests

- `tests/illustrated/test_illustrated.gd`:
  - every manifest texture resolves, and every furniture/prop has art;
  - sections, doors and posts cover every wall exactly;
  - destroying a section opens collision and nav in the same frame;
  - windows lose their glass before the frame;
  - enemy bashing hits the nearest section;
  - a creator override at another resolution is used and fits the footprint.
- `tests/test_versions_smoke.gd::test_illustrated_smoke` (shared).

## Known issues and limits

- **Furniture shading rotates with the piece.** Its hatched shadow band is baked for the front-down orientation, so pieces facing north, east or west have their shadow on another side; the reference accepts the same compromise. Runtime shadows are correct.
- At close zoom, a boundary between an intact and a damaged chunk run is a straight vertical cut in the strip. Destruction granularity is one section (about 1 m) for collision and nav, and 0.125 m for the drawing.
- Soft shadows are blurred in screen space, so they look slightly softer when zoomed out.
- Windows never occlude light (glass), so interior light also spills through intact windows. That is intended, but it means light leaks are not only through damage.
- After the glass is gone a window still stops bullets until its frame is destroyed (per the shared spec).
- Tokens are 1 m wide (base included) while bodies are 0.5 m, so tokens visually overlap furniture edges when hugging them.
- Night is dark outdoors by design; characters get a faint unshaded copy to stay readable. Corpses do not.
- Doors are always-open doorways (no door logic); leaves are decoration.
- Furniture is not destructible (out of scope); tall pieces just stop bullets with material effects.
- Verified only in screenshots and the headless tests. Mouse and keyboard feel was not played by hand, and no exported build was made (not requested), so the override next to an exported executable is untested here.
