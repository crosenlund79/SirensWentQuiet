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
