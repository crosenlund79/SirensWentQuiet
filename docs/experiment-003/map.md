# Experiment 003 — The voxel city map (M)

The region map is a **miniature 3D model of the region around the house**, used at home to understand the world and choose expeditions (SPEC-003 §6, ASSIGNMENT §8). It is not a second playable world: planning on the map only sets `state.region.planned` / `planned_purpose`; the player still leaves by walking into the fog.

## 1. Files (owner: M)

| File | What it is |
|---|---|
| `src/map/region_terrain.gd` | `RegionTerrain`: the deterministic region as data (heights, water, cover, roads, bridges, districts, building boxes, tree instances). `LAYOUT_ID`, `shared()`, queries (`height_at`, `district_at`, `anchor_of`, `route_from_home`, `connected_to_home`, `content_hash`). No nodes. |
| `src/map/region_map_mesher.gd` | `RegionMapMesher`: terrain chunks, props, water and tree MultiMeshes from a `RegionTerrain` (cached). |
| `src/map/region_map_view.gd` | `RegionMapView` (Node3D): environment, sun, meshes, the house's warm light, cloud layers, fog floor, camera rig, projection helpers. |
| `src/map/region_map_screen.gd` | `RegionMapScreen` (CanvasLayer): the screen and its API. |
| `src/map/map_markers.gd` | `MapMarkers` (Control): pins, route line, hover card, mouse pan/zoom/select. |
| `src/map/map_info.gd` | `MapInfo`: the info panel's data (X's `location_summary` or a local fallback), category colours, plan helper. |
| `src/map/shaders/*` | `map_common.gdshaderinc` (cloud field, cloud shadows, edge fog), `map_surface`, `map_water`, `map_clouds`. |
| `src/map/map_preview.tscn` (+ `.gd`) | Standalone preview with a sample run, for captures. |
| `tests/map/test_map_terrain.gd`, `tests/map/test_map_screen.gd` | Tests (`--filter=map`). |

## 2. How the terrain is generated

One region, built the same way every time (`RegionTerrain.SEED`, FastNoiseLite with fixed seeds, a seeded `RandomNumberGenerator`, fixed iteration order). Scale: **1 column = 1 region cell = 25 m = 1 world unit**; `RegionLocations.SIZE` = 160 × 120 columns. **Vertical: one height step = 0.5 world units** (`STEP`); the sea surface is step 4 (`SEA`); the town sits around step 7; mountain peaks reach about step 45.

The build runs these passes, each authored around `RegionLocations` (positions and districts) with procedural detail:

1. **Heights.** A base of rolling hills (FBM noise) and a gentle rise toward the northern woods; the **north-west mountains** (a ridged-noise massif around (9, 7), warped so its foot is irregular); bumps for the **southern hills**, the bay's headlands and the north-east; the **town basin** flattened toward step 7 (soft ellipses for the centre, suburbs, industry and docks); the **farmland** flattened. The **east coast** is an authored shoreline per row (`COAST`) with noise, except the straight **docks quay** (rows 57–85). East of it is sea (floor below sea level); a sand beach rises from it elsewhere.
2. **Districts.** Authored shapes in priority order (`district_rule`): docks (the quay strip), centre (an ellipse round (97, 62)), industrial (south of the centre along the lower river), suburbs, mountains (within 44 cells of the north-west corner), forest (the north), farmland (south-west), hills (west and south-west). Every location's district in `RegionLocations` must match its cell (tested).
3. **River.** An authored centreline (`RIVER`) from a mountain **tarn** through the woods, past the sawmill, **through the city** (between the construction site and the supermarket), along the industrial lower river and into the **bay** south of the docks, smoothed (Catmull-Rom) with a slight meander upstream. Its water level falls along a concave profile (steep in the mountains, flat in town), is never above the ground along the course and never rises downstream (falls appear where it steps down). The channel is carved with banks: gorges in the hills, embankments in town (two steps below the streets).
4. **Pads.** Each location's footprint (`pos` and `size`) is levelled; the house gets a 3 × 3 lot. The **quarry** is a cut, terraced pit in the foothills (benches step up toward the rim; never filled).
5. **Roads.** The **ring road** around the centre and **Route 9** (west edge → south of the house → the diner → industry → the docks quay) are authored; a street grid fills the centre and long streets cross the suburbs. Then **A\*** (`AStarGrid2D`, 4-connected) runs from every place to the house, nearest first: existing roads are cheapest, slopes cost quadratically, crossing the river is expensive but possible, other places' plots are avoided. The result is a road tree that merges into the network instead of a star. Roads are then cut and filled to climb at most one step per cell; road cells over water become **bridges**.
6. **Levees.** Dry cells next to water are raised to at least the water level (no water stands above its banks).
7. **Land cover.** Snow and rock by height and slope, beaches, quay, paved centre with a **riverside park**, industrial yards, suburban lawns, a patchwork of **fields** with furrows in the farmland, and **forest** where a forest noise field is high (strongest in the north, sparse in the hills); clearings at the logging area, sawmill, farm and outpost.
8. **Buildings (simple voxel masses).** City blocks fill the centre's street blocks (1×1 to 2×2 lots; taller toward the core, some with setbacks or rooftop units); suburbs get two small gabled houses per street-facing cell (stepped voxel roofs, muted wall and roof colours, cars in some drives); industry gets sheds and two brick **chimneys**; the docks get **cranes**, container stacks, piers and moored boats; a few cottages stand along country lanes. Every location has its own small composition: the H-shaped **hospital**, the **police** station with a mast and cars, shops with coloured bands, the **supermarket** and diner with parking, the half-built tower and **tower crane** at the construction site, scrap heaps behind a fence, the warehouse sheds, the sawmill shed and log piles, the logging clearing, the quarry office and machine, the farm with a red barn and a silo, the **shooting range** berms, and the **military outpost** with a fence, barracks, watchtowers, a helipad and trucks.
9. **The house.** A small dark-slate house with **warm emissive windows** and a fence round the lot, on the south-western edge of town at `RegionLocations.HOME`, plus an `OmniLight3D` (brighter at night) and the amber home pin.
10. **Trees.** Pines on high ground and in the northern forest, autumn broadleaf trees elsewhere (olive, ochre, rust), garden trees in the suburbs and park, riverside trees, hedgerows along field edges, and three bare trees by the house (like the ones in the yard).

`content_hash()` is a SHA-256 over every array plus the boxes and trees; two builds give the same hash (tested).

**Layout identity.** `RegionTerrain.LAYOUT_ID = "region-v1"`, the same as `RegionState.layout`'s default. On `open`, the screen compares them; a different layout is shown in the title card ("Saved on another map layout") and nothing else changes (the places come from `RegionLocations` either way). Change `LAYOUT_ID` if the geography changes in a way a save should notice.

## 3. Meshing

- **Terrain:** 20 chunks of 32 × 32 columns. One top quad per column; side quads only where a neighbour is lower (an upper "lip" band in the cover colour, the rest earth or rock). No walls at the region edge (it dissolves into fog). Vertex colours with per-cell variation; **baked AO** in `COLOR.a` (top corners from the three neighbours, like `VoxelMesher`; side bottoms darker). Roads are narrow strips laid on their cells (centre square plus arms toward neighbouring road cells), so the ground shows beside them.
- **Props:** every building box as five faces (no bottom), chunked like the terrain; AO darkens side bottoms; `UV.x` marks emissive faces.
- **Water:** one mesh, surfaces per water cell plus falls where the river steps down; `COLOR` carries depth, shore and sea for the shader.
- **Trees:** five voxel tree meshes (tall pine, small pine, broadleaf, bush, bare tree), drawn as five `MultiMeshInstance3D` (instance colour tints the canopy; quarter-turn rotations keep the voxel grid).

## 4. The look

- **Light and palette:** a soft warm sun from the south-west with shadows, a cool ambient, filmic tonemapping, light SSAO and glow; the muted autumn palette of the lot (olive grass, ochre and rust trees, slate roofs, concrete city).
- **Water:** shallow/deep and river tints by depth, foam along the beaches, white streaks on falls, fine animated ripples and soft moving bands of light (the shimmer).
- **Fog at the edge:** every map shader fades to the fog colour near the region border along a ragged noise edge, and a wide **fog floor** in the same shader surrounds the region, so the miniature floats in fog (the game's theme) and the background never shows.
- **Drifting clouds:** one cloud field (a seamless noise texture sampled at two scales) drives both the **cloud layers** (two planes above the map, thin, with gaps, self-shaded toward the sun) and the **cloud shadows** on terrain, buildings, trees and water (shifted along the sun direction). They drift slowly (`CLOUD_SPEED` ≈ 0.8 world units per second; about three minutes to cross the region). **Usability:** the clouds clear in a circle around the cursor and around the selected place, and they fade out as the camera zooms in below them; the shadows stay.
- **Tilt-shift:** at close zoom (camera distance under 100) a gentle depth of field softens the far and near edges, like a model under a lens; the overview stays sharp.
- **Time of day:** `open` reads `state.night_amount()` and tints the sun, ambient, fog and clouds toward moonlight; the house's window and light grow warmer and brighter at night (the only lit house in a dead town).

## 5. Interaction

- **Screen:** `RegionMapScreen` is a CanvasLayer (layer 65, `PROCESS_MODE_ALWAYS`) with the miniature in its own `SubViewport` and `World3D` (it never touches the game's world or environment). The SubViewport renders only while the screen is visible.
- **Layout:** title card (day, time, places known, the current plan), the list of known places (sorted by travel time, the plan marked), the info panel (only with a selection), "Find my house" and "Close" (top right), key hints (bottom left), legend (bottom right). Everything uses `UiTheme`.
- **Navigation:** drag to pan (the grabbed ground point stays under the cursor), WASD or arrows to pan, the wheel to zoom at the cursor (clamped 16–200), `+`/`-`/PageUp/PageDown to zoom; the camera pitch flattens as you zoom in. **H** or the button finds the house.
- **Pins:** one per known place (category colour and glyph, a stem to the ground, the name when close, hovered, selected, planned or home); a hover card shows the name, category and travel time. **Undiscovered places have no pin and are not in the list** (they can't be selected). The selected place gets an amber ring on the pin and a glowing ring on the ground, plus the **road route from the house** drawn as a dashed amber line.
- **Info panel** (on select): name, category and district, description; travel time each way and distance, risk (coloured), today's stock; what you might find; relevant equipment (✓ equipped, ○ owned but not equipped, ✗ missing, "required" in red); notes (visits, flags); the four **mission purposes** (General scavenging, Targeted collection with a resource picker, Careful exploration, High-risk raid; unavailable ones disabled with the reason as tooltip) with the description, time and risk of the chosen one; **"Plan expedition"**; and a status line ("Walk into the fog at the edge of your lot to set out").
- **Keyboard:** Tab / Shift+Tab next or previous known place (the camera flies there), 1–4 mission purpose, Enter plan, H house, Esc or M close.

## 6. Gameplay text

`MapInfo.summary(id, state)` calls `ExpeditionData.location_summary(id, state)` when the method exists (checked with `has_method`; X's API, see `scavenging.md` §11) and normalises it; otherwise it uses a local fallback built only from `RegionLocations` and `RegionState` (travel time, a category risk, a resources line, generic equipment hints, the four purposes, today's stock). It is called when the selection changes, never per frame. The hover card uses only `RegionLocations`.

## 7. Persistence

The map **reads** `GameState` (`region.discovered`, today's stock via `region.stock_on(id, day)`, `region.planned` / `planned_purpose`, `region.layout`, inventory and equipment, the clock) and **writes only the plan**: `state.region.plan(id, purpose)` (X's method; direct fields as a fallback). Purposes are an approach id or `targeted:<item>`. Nothing else is stored. The **camera is not saved**: it stays where it was while the screen node lives (reopening keeps the view) and starts framed on the whole region otherwise. On `open`, the planned place is preselected with its purpose.

## 8. Performance (measured, headless here unless noted)

| What | Number |
|---|---|
| Terrain build (`RegionTerrain.build`) | 320–460 ms |
| Mesh build (`RegionMapMesher.build`) | 380–510 ms |
| First `open` (both, plus nodes) | 0.7–1.0 s once per session (`prewarm()` moves it to loading); later opens reuse the cached region and meshes |
| Quads | terrain 34,414 · props 23,315 · water 2,455 · trees 112,950 (instanced) · **total 173,134** |
| Objects | 6,288 trees, 4,663 building boxes |
| Mesh instances | 43 (20 terrain chunks, 15 non-empty prop chunks, water, 5 tree MultiMeshes, 2 cloud planes) plus the fog floor |
| Rendered frame (preview `--stats`, overview, software Vulkan under Xvfb at 1600 × 900) | 336 draw calls, 1,446 objects, 704k primitives (all passes: depth, two shadow splits, colour); about 1 fps on lavapipe. Not a real-GPU measurement. |

The budget test (`test_map_performance_budget`) records these numbers on every run and fails above 4 s per build step or 260k quads.

## 9. Integration (Phase B)

The game must:

1. **Create the screen once** (e.g. in the game root) and keep it: `var map := RegionMapScreen.new(); add_child(map)`.
2. **Optionally pre-build** during loading to avoid the first-open hitch: `RegionMapScreen.prewarm()` (builds and caches the region and its meshes; about 1 s headless).
3. **Open it** on the `open_map` action (M) at home and from a map interactable in the house: `map.open(state)`. While `map.is_open`, block player movement, firing and building input (the map uses WASD, arrows, H, Tab, 1–4, Enter, Esc and M itself and marks them handled in `_input`). Pausing the clock is the game's choice; the screen pauses nothing and runs while the tree is paused.
4. **Listen:** `map.destination_selected(id, purpose)` (the plan is already in `state.region`; show a toast, autosave, or close the map) and `map.closed` (restore input).
5. **Leave as before:** the fog boundary opens the expedition screen, which preselects `state.region.planned` / `planned_purpose` (X).
6. **Dev menu "reveal all map locations":** `state.region.discover_all()` (X), then reopen or call `map.open(state)` again to refresh pins.
7. Hide or don't render the game's 3D view while the map covers the screen if performance matters (the map draws its own world).

## 10. Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=map`

- the terrain is deterministic (same SHA-256 twice, equal to the shared build);
- every location lies on land, fully dry, in its `RegionLocations` district; the house is in the suburbs;
- roads connect every location to the house (flood fill over road cells, continuous routes);
- the river rises in the mountains, flows continuously into the bay, never rises downstream and ends at sea level; no water stands above its banks;
- geography: the harbour and warehouse by the bay, the sawmill on the river, the north-west mountains the highest ground, the quarry cut below its rim, the north wooded, the farmland in fields;
- performance budget numbers recorded;
- the screen opens and closes (once-only `closed`, Esc, M), planning sets `RegionState` and emits `destination_selected` once (targeted purposes included), the house and nothing can't be planned, undiscovered places are hidden and can't be selected, the plan is preselected, keyboard, layout check, pins project and can be hit, `MapInfo` fallback and normalisation of X's shape.

## 11. Preview and captures

`src/map/map_preview.tscn` opens the screen with a sample run (day 3, sixteen places known, the supermarket picked over, the hardware store planned, a flashlight and a crowbar). Arguments after `--`: `--select=<id|home|none>`, `--approach=<id>`, `--plan`, `--focus=x,z,dist`, `--cloud-time=s`, `--cloud-rate=k`, `--no-clouds`, `--night=n`, `--hide-ui`, `--all`, `--stats`.

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/map/map_preview.tscn /abs/out.png 1.5 --select=none
```

Screenshots are in `/home/user/swq3-shots/m/` (see the report).

## 12. Known limits

- Roads are one cell wide on a 25 m grid; diagonal country roads become staircases.
- Building masses are deliberately simple; at full zoom-out the suburbs read as texture.
- The cloud layers are planes: from low angles they show as flat sheets (they fade out when zooming in).
- The tilt-shift and SSAO cost GPU time; on software Vulkan the map renders at about one frame per second (expected; not representative of a real GPU).
- The route line is the road path from the house; travel time comes from `RegionLocations.travel_minutes` (straight distance × 1.3), not from the drawn road's length.
