# Deferred observations — not approved tasks

Record only observations found during approved work. An item here is **not** permission to implement or add to the current objective.

| Date | Observation | Context |
| --- | --- | --- |
| 2026-11-23 | `PursuitBrain` detects "stuck" by position, so in a half-open gap (cells OPEN but not walkable) it oscillates between waypoints and stops bashing. Version A works around it locally (swing at the nearest WALL after 2.5 s without progress). A progress-based stuck rule in the shared brain would fix it for everyone. | Experiment 001, Version A |
| 2026-11-23 | `GridNav` is a single 2D level with 0.25 m cells and 3×3 body clearance. Multi-floor houses, stairs or basements would need layered navigation. | Experiment 001, comparison report |
| 2026-11-23 | Real-GPU frame rates were never measured: all rendering checks ran under software Vulkan (lavapipe, 1–8 fps). Measure on a typical desktop before choosing a technology on performance grounds. | Experiment 001 |
| 2026-11-23 | The `custom/` override next to an *exported* executable is implemented but untested, because no export was made (not approved). The project-folder override is verified in all three versions. | Experiment 001 |
| 2026-11-23 | Under lavapipe, `tools/capture.sh`'s scene clock barely advances before the capture timer fires. `CAPTURE_ENGINE_ARGS="--fixed-fps 30"` gives deterministic frames; consider making it the default. | Experiment 001 tooling |
| 2026-11-23 | Version A: GDScript carving and meshing cost a few ms per shot (spikes of 10–30 ms seen on the shared VM), and there are 500–1100 draw calls in the comparison scene. Shotguns or explosions would need threaded or native meshing, or larger chunks. Carving a tall piece of furniture doesn't shrink its collision box. | Experiment 001, Version A |
| 2026-11-23 | Version B: kit modules are built in code, so the editor shows nothing for them (no `@tool` previews or per-module scenes). Debris chips hover slightly outdoors, and the cutaway also lowers open door leaves. | Experiment 001, Version B |
| 2026-11-23 | Version C: windows never occlude light, so interior light also spills through intact windows. Furniture's baked shading rotates with the piece. Doors are always-open doorways. | Experiment 001, Version C |
| 2026-11-23 | The asset-resolver test deliberately loads an invalid PNG, and Godot prints `ERROR:` lines that look like failures in the test log. | Shared tests |
| 2026-11-23 | Experiment 002: invasion spawn gaps are real seconds and don't follow the dev time-speed setting. Stragglers crossed by a long time skip that ends in daylight never appear. | Game loop (G) |
| 2026-11-23 | Experiment 002: Tab is taken by GUI focus navigation while a panel has a focused button, so it doesn't close the inventory. I and Esc still do. | UI / game loop |
| 2026-11-23 | Experiment 002 build mode: an open door leaf has no collision; two wall runs meeting at a corner leave a 0.1 m notch at the outer corner (no body can pass); placing a 12 m run costs about 90 ms on the click; dev `repair_all` takes about 0.2 s. | World / construction (V) |
| 2026-11-23 | Experiment 002 cutaway: tall mesh props between the camera and the player are hidden whole (shadow kept) instead of sliced. | World (V) |
| 2026-11-23 | Experiment 002 props: furniture other than the survival pieces shows no real damage. `HousePlan.LIGHTS` fixtures (ceiling lights, hood, table lamp, bare bulb) have no mesh types and are simply absent. Textures are object-space, so scaling a prop node stretches them. | Props (P) |
| 2026-11-23 | Experiment 002 fog: a WORLD-shaped FogVolume rendered nothing under software Vulkan, so a 60 m box volume plus 10 transparent fog slices are used. The real-GPU cost of those layers is unmeasured. | Fog (E) |
| 2026-11-23 | Experiment 002 balance: expedition loot, risk and invasion difficulty are a first pass, tuned from simulations, not play. | Expeditions / survival |
| 2026-11-23 | Experiment 002 audio: no sound has been auditioned by ear (only measured). The enemy voices and the menu music are the riskiest. Audio overrides next to an exported game are untested. | Audio (A) |
| 2026-11-23 | Experiment 002 saving: one slot with one backup generation; a single time advance is capped at 30 days. The checksum covers the file, but world contents are validated by `HouseWorld.load_data`. | Save (S) |
| 2026-11-23 | Test runner: `--filter` matches the file's base name and the method, not the folder, so `--filter=survival` skips `tests/survival/test_game_state_core.gd`. | Shared tests |
| 2026-11-23 | `src/game/survival_game.gd` is about 1,100 lines, because the dev and debug APIs live on the root. Worth splitting if the game loop grows. | Game loop (G) |
| 2026-11-24 | The main menu's music doesn't start on the very first launch: `main_menu._ready` calls `Sfx.music` while the root is still adding the main scene, so `Sfx._persistent_host`'s `add_child` fails ("Parent node is busy setting up children"). It plays after returning from a game. Present since Experiment 002; a deferred call would fix it. | Audio / menu (found in the Experiment 003 smoke launch) |
| 2026-11-24 | Experiment 003 playtest: the in-game bomber blast was never captured on screen (F10 overflow, fixed afterwards; not re-run). The runner was not seen using an open back door. Step 14's gear-dependent event choice depends on the random draw. | Integration (I) |
| 2026-11-24 | Experiment 003: enemies converge on the same cheapest bash point (crowds stack at one wall spot); the brute's collision radius (0.29 m) exceeds the nav clearance (0.25 m). | AI |
| 2026-11-24 | Experiment 003: blasts cost 40–140 ms in GDScript (mostly the crumble pass); after a big blast short leftover yard-wall pieces fall as floating fragments; plated or stone walls can still be shot through with about 80 shots. | Construction (C) |
| 2026-11-24 | Experiment 003: one stock number per place (taking water also reduces food); discovery uses straight distance, not roads; travel time uses straight distance × 1.3, not the drawn road. | Scavenging (X) / map (M) |
| 2026-11-24 | Experiment 003 UI: the map's pin clicks were unreliable in automation (list entries work); the HUD weapon card text is dense; the dimmed build-mode status card shows its shadow as a second copy; the shotgun, workbench and map table are placeholders. | UI / assets |
| 2026-11-24 | The region map renders at about 1 fps under software Vulkan (tilt-shift and SSAO); real-GPU cost unmeasured. | Map (M) |
