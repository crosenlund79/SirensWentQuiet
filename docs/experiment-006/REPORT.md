# Experiment 006 — Defensive Living: report

- **Branch:** `exp006/defensive-living`. It builds on Experiment 005 and the user's Pixel Operator font.
- **How it was built:** Rapid Delivery, with four parallel agents (D defences, R research, U UI, B house and balance) integrated by the lead.
- **Delivery:** source only. No exe and no Windows CI build. Nothing was played by a human.
- **Launch:** open `project.godot` in Godot 4.7 and press F5.
- **Developer menu:** F10 has the sections "Defences", "Research" and "House & balance".

## What's new, by the user's sections

| § | Feature |
|---|---|
| 1 | **Aurora:** `NorthernSky.OPACITY = 0.4` scales the curtains and the ambient, moon and fog tint, and the curtains get an extra 0.75 (0.3 of the old look). Behaviour is unchanged. |
| 2 | **Spikes:** wooden (3 planks + 2 nails per m, 10 HP) and metal (3 iron + 2 scrap + 2 nails, 26 HP, needs Metalworking). Enemies pressing on them or swinging from reach take damage on a per-enemy cooldown (wood 1 per 1.8 s, metal 2 per 1.5 s). Blows and blasts destroy them. |
| 3 | **Trenches and moats:** "Dig trench" (shovel; 1 m cells outside the house; 4 min and 1 energy per cell; drag for a run) and "Fill with water" (floods the whole connected section; free next to a rain collector, else 1 bottle per 4 cells). "Backfill" undoes a cell. Water blocks psychos, runners and bombers; brutes wade slowly. Dry trenches cost 4× in navigation and slow bodies. The player can't walk into water. |
| 4 | **Drawbridges:** 1 and 2 tiles (8 planks + 8 nails + 1 iron, 24 HP; 14 + 12 + 2, 32 HP; need Woodworking). **E** raises or lowers one. A raised bridge is a wall to enemies, so they bash it and bombers target it. A broken raised bridge crashes down at 1 HP. The state is saved. |
| 5 | **Build menu:** 8 category tabs (keys 1–8), a grid of tiles with icons and costs against carried + stored, padlocks with skill reasons, missing amounts in red, a Recent row, direct keys F Repair / X Demolish / G Move / Q previous, and a level header. It is data-driven: a new item needs only a `BuildPieces` entry with `"cat"` and `"icon"`. |
| 6 | **Enemies:** see the table below. Difficulty adds `enemy_speed` and `enemy_attack_interval`. |
| 7 | **Public Library and research:**<br>- The Library: city centre, known from the start, 30 min away, moderate danger.<br>- Skill books: Basic Woodworking → Reinforced Construction → Metalworking Manual → Advanced Metal Fabrication. They drop mostly at the library; occasionally hardware, construction site, police, military.<br>- Reading (Skills tab **K**, or Read in Supplies) teaches the skill.<br>- **Gates:** Woodworking unlocks drawbridges and makes wooden repairs 25 % cheaper. Reinforced unlocks the reinforced door, the iron barricade and Reinforce wood → reinforced. Metalworking unlocks the metal door, metal spikes and Reinforce → metal, and the workbench makes 1 iron from 2 scrap. Advanced unlocks iron plating.<br>- Older saves get the skills their existing structures imply. Nothing already built is ever removed. |
| 8 | **Remove window** (Tools): the opening becomes a solid wall copied from the surrounding wall (siding, framing, gypsum). It costs 3 planks + 4 nails per m and gives back 1 plank, 1 nail and 1 scrap per m from the frame. It blocks movement, is load-bearing, and can be plated and demolished; rooms stop counting it as a window. Saved in the voxel diffs. |
| 9 | **TV and radio:** a placeable TV (and the house's own TV) and a new radio, both on mains power. E switches them; there's a screen glow or dial light and soft generated static. Comfort +2 / +1 (one source per room, at most 2 rooms). Mood "Watching TV" +3 or "The radio for company" +2, capped at 3. |
| 10 | **Foundations:**<br>- New timber footing (2 planks + 2 nails per tile) next to the stone foundation.<br>- On the ground floor, walls you build on bare ground take 1.35× deeper blows.<br>- Walls up to 2 m outside the house only prop it when founded.<br>- A +2 storey needs ≥ 2 m of stone foundation outside each outer wall.<br>- Repair restores foundation tiles. |
| 11 | **Shotgun:** verified, already complete: found as loot, auto-equipped to the secondary slot and the quick bar, 6-pellet shots, shell-by-shell reloads, damages enemies, saved. The only fix: its own reload sound name (`weapon/shotgun_reload`, falling back to the handgun's). |
| 12 | **Gun store:** "Pike's Guns" already existed. Now known from the start, with the shotgun 10 % on the shelves and 24 % in the locked back room. A new "Behind the counter" event (crowbar: shotgun 40 %), more ammunition, danger 1.4, stock floor 0.08. |
| 13 | **Building from storage:** every BuildMode cost (place, replace, repair, plate, reinforce, levels, furniture) pays atomically, first from what you carry, then from the storage furniture on all storeys; loot piles don't count. Refunds overflow into storage. The menu shows "carried+stored". Eating, the bar, crafting and the car still use only what you carry. |
| 14 | **UI:**<br>- Pixel Operator everywhere through `UiTheme` (regular, bold, 8 px headings, caps, mono), snapped to 16, 32 or 48 px so it stays crisp.<br>- 73 procedural 12 × 12 pixel icons (HUD, gear, materials, build pieces, categories, book, lock, TV, radio…).<br>- Square panels with hard shadows, slate backgrounds, key caps and square toggles.<br>- Restyled: HUD, quick bar, build menu, level indicator, inventory (+ Skills tab), storage, the Home tab, expeditions, map labels, main menu, pause, settings, death screen and dev menu. |

### Enemy numbers (Normal difficulty, first invasion)

| | Speed (m/s) | Swing every (s) | Damage × |
|---|---|---|---|
| Psycho | 1.4 → 1.85 | 1.1 → 0.85 | 1.0 → 1.2 |
| Runner | 2.6 → 3.3 | 0.75 → 0.6 | 0.6 → 0.7 |
| Brute | 1.0 → 1.25 | 1.6 → 1.35 | 1.8 → 2.2 |
| Bomber | 1.6 → 2.0 | (fuse 2.5 → 2.2) | |

- **Pursuit:** enemies recompute their path two to three times as often and give up on a blocked path sooner.
- **Per invasion:** speed now rises 4 % per invasion, up to +20 % (was 5 %, up to +30 %). A late runner stays under the player's sprint (6.4).

## Verification

- **Tests:** the full headless suite on the merged branch: see `STATUS.md` / the final commit.
- **New tests:** `test_defenses`, `test_research` + `test_research_game`, `test_house_balance` and `test_build_menu`, plus updated build and UI tests.
- **Rendered frames, looked at:** the build menu's Defence tab with locks and carried+stored counts, the HUD, the inventory and the main menu (by agent U); aurora before and after (agent B); the moat and raised bridge (agent D).

## Known limitations

- **Moats:**
  - The ground storey only; trenches keep a cell away from the house and the lot edge.
  - Simplified water: a section is all wet or all dry, with no draining.
  - A closed water ring with its lowered bridge blown up leaves non-wading enemies milling at the edge.
  - Raised bridges let bullets through, as barricades do.
- **Research:**
  - Reading takes no game time, and each book teaches its skill outright.
  - The drop rates come from simulation only.
  - The workbench prompt shows both scrap rates.
- **Foundations:**
  - Timber footings use the stone slab's impact sound.
  - The foundation repair cost ignores the Woodworking discount.
- **Storage payment:**
  - The car repair still pays only from what you carry.
  - Refunds from level pieces don't overflow into storage.
- **TV and radio:** mains only; no batteries.
- **UI:**
  - Icons are procedural, with no `custom/` PNG override.
  - Pixel crispness is exact only at integer window scales.
  - Long tile names are shortened; the tooltip shows the full name.
  - Keys 9 and 0 no longer do anything in build mode.
- **Balance:** a first pass (enemy speeds, costs, drop rates); untested by a human.
- **Carried over:** earlier limits are in the Experiment 004/005 reports and `docs/BACKLOG.md`.
