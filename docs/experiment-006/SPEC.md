# Experiment 006 — Defensive Living: contracts

**Approval:** the user's message "Next Milestone — Defensive Living" (2026-11-25, Rapid Delivery, autonomous).
**Branch:** `exp006/defensive-living`, from Experiment 005 (`698ffcf`) plus the user's Pixel Operator font upload (`main` `8f56f4b`, `assets/fonts/pixel_operator/`, CC0).
**Delivery:** source only. No exe, no CI build (the branch name is outside the build triggers), no merge to `main`. The user playtests.

## Agents and ownership

| Agent | User's § | Owns |
|---|---|---|
| **D** (defences) | 2 spikes (wood, metal), 3 trenches and water moats, 4 drawbridges (1 and 2 tiles) | new `src/defense/`; the enemies' handling of water, trenches, spikes and bridges (`src/ai/` nav costs, `src/common/grid_nav.gd` / `weighted_nav.gd` additions); defence `WorldObject` kinds; trench and water state in the world save |
| **R** (research and scavenging) | 7 Library, skill books, small research tree, recipe gating; 11 verify and fix shotgun integration; 12 gun store (it exists: `gun_shop`, "Pike's Guns"; verify loot, reach, depletion) | new `src/research/`; `src/expedition/`, `src/region/`, `src/survival/items.gd` (books), skills in `game_state.gd`, a research panel in `src/ui/` (functional; U styles it centrally), the shotgun fixes in `src/combat/` and `src/game/game_hotbar.gd` |
| **U** (UI) | 5 construction menu redesign (categories, costs, locks, preview, five levels); 14 UI visual overhaul (Pixel Operator, theme, icons) across the HUD, bar, build menu, inventory, storage, comfort and mood, expeditions, research | `src/ui/ui_theme.gd`, `ui_icons.gd`, `ui_icon.gd`, `src/build/build_palette.gd` (rewrite as a category menu), categories in `build_pieces.gd`, the look of the other `src/ui/*` screens |
| **B** (house and balance) | 1 aurora opacity; 6 more dangerous enemies (data-driven); 8 window removal → solid wall; 9 functional TV and radio; 10 buildable foundations in structural support; 13 build materials from house storage | `src/home/northern_sky.gd` (aurora), `src/ai/enemy_defs.gd` (+ difficulty numbers), window and foundation parts of `house_world.gd` / `house_support.gd`, new `src/home/media.gd` (TV and radio), the comfort catalogue entries for media, new supply code (inventory plus storage) and its hooks in build mode, repair and upgrade |

The lead integrates, writes the docs and handles the shared dev menu.

**Shared hot files:** `survival_game.gd`, `dev_menu.gd`, `game_state.gd`, `house_world.gd`, `build_mode.gd`, `build_pieces.gd`, `game_hud.gd`.
- Make small, commented ("Exp 006 (X)"), additive edits, with logic in your own files.
- In `survival_game.gd`, create helpers in `_assemble()` (the `game_*.gd` pattern).
- In `dev_menu.gd`, add one appended section function and one call line.

## 1. Build pieces (U defines the categories; everyone adds entries)

`BuildPieces.LIST` entries get three optional fields:
- `"cat"`: a category id;
- `"requires"`: a skill id, or "" when nothing is needed;
- `"icon"`: a `UiIcons` name.

| Category id | Holds |
|---|---|
| walls | walls and foundations |
| floors | floors, stairs, levels, excavation |
| doors | doors and windows |
| defense | fortifications: barricades, spikes, trenches, water, drawbridges |
| furniture | furniture and storage |
| utilities | collector, workbench, fuse box, lamps, TV, radio |
| decor | decorations: rug, painting, plant |
| tools | repair, reinforce, demolish, move, remove window |

U assigns categories to every existing entry. Agents D, R and B set `"cat"` (and `"requires"` where gated) on their new entries. The old number keys 1–9 and 0 may stay as quick keys or be remapped by U; the menu must stay fast.

## 2. Research (R)

- **Skills:** `GameState.skills` (saved; older saves get the skills their existing structures imply, so nothing becomes unusable).
- **API:**
  - `Research.knows(state, id) -> bool`
  - `Research.locked_reason(state, piece: Dictionary) -> String`: "" when buildable, otherwise "Requires Metalworking (read 'Metalworking manual')";
  - `Research.SKILLS` (id → name, description, book item, prerequisites).
- **Gating:** build mode's evaluation refuses gated pieces with that reason (R adds the hook). U's menu shows the lock and the reason.
- **Skill ids** (R may refine; keep the tree small):

| Skill id | Gates |
|---|---|
| woodworking | better wood pieces |
| reinforced | reinforced door, iron barricade, plating |
| metalworking | metal door, metal spikes |
| advanced_metal | later metal pieces |

  Plain wood pieces, furniture, trenches and stone walls need nothing.

## 3. House supply (B)

- **Building, repairing and upgrading** pay from the household pool plus the eligible storage containers in the house, on all storeys; loot piles don't count.
- **API:**
  - a game helper or static functions: `can_pay(cost)`, `pay(cost) -> bool` (atomic: inventory first, then containers; nothing taken on failure), `available(item) -> int`;
  - refunds go to the inventory (existing caps; the overflow goes to a container if simple).
- **Display:** the build menu shows the combined counts (U reads `available()`).

## 4. Defences (D)

- **Kinds:** `WorldObject` kinds `spikes_wood`, `spikes_metal`, `drawbridge_1`, `drawbridge_2`, with HP, destructible by blows and blasts, and saved.
- **Spikes** hurt enemies on contact, with a per-enemy cooldown.
- **Trenches:**
  - a grid of dug outdoor cells on the ground storey, with a water state per connected section;
  - water-filled cells are impassable for ordinary enemies; dry trenches are slow or costly;
  - the player crosses by drawbridge;
  - the last-exit rule counts water and bridges.

## 5. UI (U)

- **Font:** the Pixel Operator font in `assets/fonts/pixel_operator/` (CC0), at readable sizes.
- **Central theme:** `UiTheme`, so every screen follows. The other agents build their panels with `UiTheme` helpers and icons, not custom styling.
