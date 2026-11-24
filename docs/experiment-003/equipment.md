# Experiment 003 — Equipment, weapons and resources (K)

Owner: K. Code: `src/survival/` (`GameState`, `Inventory`, `Items`, `Equipment`, `Crafting`, `Difficulty`, `SurvivalTuning`) and `src/combat/` (`WeaponDefs`, `WeaponHandler`, the preview harness). Tests: `tests/survival/`, `tests/combat/`. Contracts: SPEC-003 §2 and §8. It extends `docs/experiment-002/survival.md`, which still holds where this file doesn't change it.

Everything in `src/survival/` stays pure data: no nodes, no scene access, no Autoloads. `WeaponHandler` is the only node.

## Items and categories

Categories (`Items.CATEGORIES`): weapon, ammo, protective, tool, utility, medical, food, water, material.

| Item | Category | Slot | Cap | Notes |
|---|---|---|---|---|
| `handgun` | weapon | primary / secondary | 1 | 9 mm, magazine 12 |
| `shotgun` | weapon | primary / secondary | 1 | shells, magazine 5 |
| `ammo` (9 mm rounds) | ammo | — | none | handgun reserve |
| `shells` | ammo | — | none | shotgun reserve |
| `vest` | protective | body | 1 | −35 % damage |
| `backpack` | **utility** (was tool) | back | 1 | carry ×1.5 |
| `flashlight` | **utility** (was tool) | utility | 1 | expedition options |
| `crowbar` | tool | tool | 1 | expedition options |
| `hammer` | tool | tool | 1 | needed (owned) to build |
| `wood`, `nails` | material | — | 40 (+20 per crate), 80 (+40) | usable |
| `stone` | material | — | 40 (+20 per crate) | usable |
| `iron` | material | — | 20 (+10 per crate) | usable |
| `scrap` | material, **raw** | — | 20 (+10 per crate) | workbench: 3 → 1 iron |

Helpers:

- `Items.slot(id) -> String`: the slot kind (`"weapon"`, `"body"`, `"back"`, `"utility"`, `"tool"`) or `""`.
- `Items.is_unique(id) -> bool`: gear, capped at one (exactly the items with a slot).
- `Items.is_raw(id) -> bool`: raw materials (scrap).

The flashlight and backpack moved from `tool` to `utility`. Code that asked `Items.category(id) == "tool"` to mean "gear, one of each" should ask `Items.is_unique(id)` (see "Requests").

## Equipment

Slots (`Equipment.SLOTS`): `primary`, `secondary`, `body`, `back`, `utility`, `tool`. State: `GameState.equipment` (slot → item id), saved.

### Rules

- **Only owned gear** can be equipped. A slot whose item is no longer owned reads as empty at once (`equipped`, `has_equipped` and `slot_of` check ownership on every read), and the next inventory change removes it from `equipment`.
- **`equip(id, slot := "")`** returns `""` (also when already there) or a readable reason: "You don't have a protective vest.", "Bottled water can't be equipped.", "Protective vest doesn't go in the back slot.", "Unknown item.", "You're dead.".
  - Without a slot it picks the slot the item fits. A weapon takes the first free weapon slot; with both taken it replaces the weapon in hand.
  - A weapon moved to the other weapon slot swaps places with what was there.
  - Equipping into an occupied slot replaces that item; the old one stays in the inventory.
- **`unequip(slot) -> bool`**: false if the slot was empty or unknown. The item stays in the inventory.
- **Auto-equip:** newly acquired gear (count 0 → 1) goes into its slot if that slot is free. This makes found gear effective without visiting a panel. It does not apply:
  - to the hammer (`Equipment.NO_AUTO_EQUIP`: it has no equipped effect and must not take the crowbar's tool slot);
  - to items owned when a run starts or a save is loaded;
  - after a deliberate unequip (only an acquisition triggers it).
  - `state.auto_equip = false` turns it off (not saved).
- **Losing gear** (an expedition's `lost`, the dev menu, anything that changes the inventory) unequips it. A lost weapon takes its magazine with it; a weapon found later starts empty. If the weapon in hand goes, the other weapon slot takes over the hand.
- Signals: `equipment_changed` (and `changed`).

### Effects

| Item | Effect | Where |
|---|---|---|
| vest | incoming damage × 0.65 (−35 %) for every cause except `starvation` and `dehydration`: psychos, blasts, other archetypes, expedition injuries | `GameState.damage` via `damage_factor(cause)` |
| backpack | expedition carrying capacity ×1.5 | `GameState.carry_multiplier()`, used by X |
| flashlight | expedition options and risk | `has_equipped("flashlight")`, used by X |
| crowbar | alternative scavenging options | `has_equipped("crowbar")`, used by X |
| hammer | needed to build and repair: **owned**, not necessarily equipped | `GameState.can_build()` |

Decisions:

- **Hammer owned, not equipped.** Building happens at home, where the household's tools are at hand. Requiring a swap before every build would add friction without a choice. `can_build()` matches what BuildMode already checks (owned, or the unlimited cheat), so construction needs no change. The hammer can still be equipped by hand; it then takes the tool slot, which matters only because the crowbar can't be there too.
- **The backpack doesn't raise material caps.** Caps are household storage (crates raise them); the backpack is about carrying.
- **The vest also reduces expedition injuries.** `apply_expedition_report` now reports both `damage` (the trip's injury) and `damage_taken` (the health actually lost). X shouldn't reduce the amount again; it may still use the vest for options and chances.
- The vest is applied before the 1000-point bound, after the difficulty (`enemy_damage()` already holds it).

## Weapons

`WeaponDefs.DEFS` (SPEC-003 §2):

| | handgun | shotgun |
|---|---|---|
| ammo item | `ammo` | `shells` |
| magazine | 12 | 5 |
| fire interval | 0.2 s | 0.9 s |
| damage | 1 per hit | 1 per pellet |
| pellets | 1 | 6 |
| spread (full cone) | 1° | 9° (each pellet within 4.5° of the aim line, uniform over the cross-section) |
| range | 40 m (HouseWorld's own) | 14 m |
| reload | magazine, 1.4 s; firing is blocked meanwhile | one shell per 0.5 s until full or out of shells; firing interrupts it |

Consequences, measured in `tests/combat/test_weapons_world.gd`: at 3 m every pellet lands on a psycho (a 9° cone is 0.47 m across, the body 0.5 m), so one blast kills a 3-HP psycho. At 18 m three blasts leave it untouched, while one handgun shot hits it. The handgun's 1° cone is ±7 cm at 8 m.

### Runtime: `WeaponHandler` (a Node)

- Every pellet resolves through `HouseWorld.shoot(origin, dir, [player RID], muzzle)`, so hits, voxel damage, impacts, tracers and impact sounds are the world's.
- One trigger pull plays the muzzle flash, the casing and `player.on_fired()` once, like today's handgun.
- Sounds: `weapon/handgun_fire` and `weapon/dry_fire`, plus `enemy/hit` and `enemy/death` once per enemy hit per pull (not per pellet).
- **Range:** if `world.shoot` takes a 5th argument (`max_range`), the handler passes the weapon's range. Until then, a pellet with a range under 40 m is probed with `world.aim_ray`; if its first hit lies beyond the range it is **spent**: a tracer to the range, no damage, result `{"kind": "spent"}`.
- **Shot origin and aim** as in the game today: from the player's position at `Tuning.MUZZLE_HEIGHT` towards the aim point (straight ahead and down when the aim is closer than 0.3 m). Muzzle: `WeaponDefs.DEFS[id]["muzzle"]` in the rig's `gun` node space.
- **Dry fire:** an empty magazine clicks (at most every 0.45 s, emitting `empty`). If there is a reserve, it starts a reload (`auto_reload`, default on).
- **Unlimited cheat:** every pull first tops the magazine up to capacity for free, then fires without spending, so the magazine is always full and never runs dry. The reserve is untouched, and a reload also costs nothing.
- **Switching** (`switch_to`, `select_slot`, `next`): instant, then the new weapon may fire after 0.3 s. Switching cancels a reload. The weapon in hand is `GameState.active_weapon_slot` (saved).
- **Visual:** the handgun is the rig's own pistol mesh. The shotgun is a placeholder of six boxes (barrel, tube, pump, receiver, grip, stock) added at runtime as `WeaponModel` under the rig's `gun` node, with the pistol mesh hidden. With no weapon, both are hidden. The voxel files are untouched.

### Magazines, reserve and the start

- `GameState.weapons` = `{weapon id: {"loaded": n}}` for owned weapons only; saved. The reserve is the inventory ammo item (`state.reserve(id)`).
- **Start** (`GameState.new_run(seed, level)`): the handgun is owned (`START_ITEMS` now has `handgun: 1` and no `ammo`). It is equipped as primary and holds `Difficulty` `start_rounds`: Easy 12, Normal 9, Hard 9. There is no reserve. Nine bullets still means nine.
- **Expeditions:** `apply_expedition_report` takes rounds the trip `consumed` from the reserve first, then from the magazines, the weapon in hand last. So rounds in a gun can be spent on a trip and aren't free. `rounds_carried(ammo_id)` (reserve + magazines) is what a trip can bring. `lost` ammo comes from the reserve only.
- **`use_ammo(n)`** (Experiment 002 API) still works for the old firing path. It spends 9 mm rounds from the handgun's magazine first, then the reserve, all or nothing.

## Resources: scrap → iron

Wood (planks), stone, iron and nails are usable construction resources. Scrap is **raw**: a workbench turns 3 scrap into 1 iron (`Crafting.RECIPES["iron"]`, the only recipe; no crafting tree).

```
Crafting.convert_scrap(state, n := 1) -> {"ok", "units", "used", "made", "reason"}
Crafting.can_process(state, "iron") -> ""|reason
Crafting.max_units(state, "iron") -> int
```

- It makes as many units as asked, limited by the scrap owned and the iron cap (+10 per crate). Each unit is all or nothing.
- The unlimited cheat makes the scrap free (as `pay` does); the iron cap still holds.
- A dead player makes nothing.
- Reasons: "You need 3 scrap metal.", "No room for more iron.", "You're dead.", "Nothing to make.".

## Difficulty semantics

`src/survival/difficulty.gd` holds the table (foundation); `GameState` applies the survival-core part:

| Value | Effect |
|---|---|
| `start_rounds` | rounds in the handgun's magazine at the start |
| `enemy_damage` | `GameState.enemy_damage()` = 12 × (1 + 0.1 (k − 1)) × enemy_damage; the vest applies afterwards in `damage` |
| `enemy_count` | `invasion_size()` (Experiment 002 director) × enemy_count, rounded, at least 1 (Easy 2, Normal 3, Hard 4 in invasion 1) |
| `enemy_hp` | `invasion_enemy_hp()` × enemy_hp, rounded, at least 1 (Easy 2, Normal 3, Hard 4); `enemy_hp_scale()` for archetype HP |
| `first_invasion_day`, `invasion_interval_days` | the invasion grid at 22:00: Easy Day 4, 8, 12…; Normal 3, 6, 9…; Hard 2, 4, 6… (`_invasion_slot_after(t, level)`, `end_invasion`, stale-save rescheduling, straggler-free invasion nights) |

- Other values (threat budget, bombers, specials, `loot`, `scavenge_danger`) are read by AI and X through `Difficulty.get_value(state.difficulty, key)` or `state.difficulty_value(key)`.
- `set_difficulty(level)` (dev menu) moves an invasion that isn't yet due onto the new grid. One already due or running is kept.
- Normal reproduces Experiment 002 exactly, so its invasion tests are unchanged.

## Survival consolidation

I reviewed hunger, hydration, health, energy, sleep and the clock. The rates stay as they were: forgiving. Expeditions already consume time and needs (they advance the clock awake). Food, water and medicine keep their uses. Two real inconsistencies are fixed:

1. **Sleeping through an overdue invasion.** After loading a save made after the invasion time but before it was reported, `can_sleep()` allowed sleep. `plan_sleep()` didn't stop for it either (it only looked for an invasion in the future), so the invasion was reported only on waking, possibly at dawn. Now an overdue invasion counts as pending: no sleep until it is reported and fought.
2. **Dying in your sleep from hunger or thirst** ("danger interrupts sleep"). `plan_sleep()` now also ends the sleep:
   - when hunger or hydration runs out (reason `"needs"`, e.g. "You wake up parched. You need water.");
   - with one already out, when health falls to the "Badly hurt" level (30).
   - `can_sleep()` refuses with a need out and health at or below 30 ("You're too weak to sleep like this. Eat and drink first.").
   - The invulnerable cheat skips all of this.
   - A fed and watered night is unchanged.

## Persistence

`to_dict()` adds `difficulty`, `equipment`, `weapons`, `active_weapon` (and the foundation's `region`); `summary()` adds `difficulty`. `from_dict()` validates:

- **difficulty:** an unknown level or a non-string gives Normal. It is applied before the run record is cleaned, so stale schedules move along the right grid.
- **equipment:** keeps only owned gear in a slot it fits, each item once. A non-Dictionary gives `{}`.
- **weapons:** one entry per owned weapon, `loaded` clamped to 0..capacity (numbers parsed like inventory counts). Unknown weapons are dropped.
- **active_weapon:** `"primary"`/`"secondary"`, falling back to an equipped weapon.
- **Experiment 002 dictionaries** (neither `equipment` nor `weapons`) are migrated: Normal; the handgun added and equipped as primary; its magazine filled from the inventory's `ammo` up to 12, the rest left in reserve. The schedule and everything else are kept.
- Restoring never auto-equips; reloads in progress aren't saved.

## API

```
# GameState (src/survival/game_state.gd)
signal equipment_changed
var equipment: Dictionary            # slot -> id
var weapons: Dictionary              # id -> {"loaded": int}
var active_weapon_slot: String       # "primary" | "secondary"
var auto_equip := true
func equip(id, slot := "") -> String
func unequip(slot) -> bool
func equipped(slot) -> String
func has_equipped(id) -> bool
func slot_of(id) -> String
func damage_factor(cause: String) -> float
func carry_multiplier() -> float
func can_build() -> String
func active_weapon() -> String
func set_active_weapon_slot(slot: String) -> bool
func magazine(id) -> int
func set_magazine(id, n: int) -> void
func reserve(id) -> int
func load_rounds(id, n := -1) -> int
func spend_round(id) -> bool
func rounds_carried(ammo_id: String) -> int
func use_ammo(n := 1) -> bool        # Experiment 002 path
func set_difficulty(level: String) -> void
func difficulty_value(key: String) -> Variant
func first_invasion_day() -> int
func invasion_interval_days() -> int
func enemy_damage() -> float
func enemy_hp_scale() -> float
static func new_run(run_seed := 0, level := Difficulty.DEFAULT) -> GameState

# Equipment (src/survival/equipment.gd)
const SLOTS, WEAPON_SLOTS, SLOT_NAMES, VEST_FACTOR, UNARMORED_CAUSES, BACKPACK_CARRY, NO_AUTO_EQUIP
static func slots_for(id) -> Array
static func is_equippable(id) -> bool
static func fits(id, slot: String) -> bool

# WeaponDefs (src/combat/weapon_defs.gd)
const DEFS, SOUNDS
static func has(id) / ids() / get_def(id) / name_of(id) / capacity(id) / ammo_of(id) / using_ammo(ammo_id)
static func pellet_dirs(dir: Vector3, n: int, spread_deg: float, rng) -> Array[Vector3]

# WeaponHandler (src/combat/weapon_handler.gd), a Node
signal fired(id: String, hits: Array)
signal empty(id: String)
signal reload_started(id: String)
signal reloaded(id: String)
signal reload_interrupted(id: String)
signal switched(id: String)
var auto_tick := true                # advances in _physics_process; tests call tick()
var auto_reload := true
func setup(state: GameState, world: Node, player: Node3D) -> void
func tick(delta: float) -> void
func try_fire(aim_point: Vector3) -> Dictionary   # {"ok", "id", "reason", "pellets", "hits", "reloading"}
func reload() -> String
func switch_to(id: String) -> String
func select_slot(slot: String) -> String
func next() -> String                # the id switched to, or ""
func current() -> Dictionary         # {id, name, loaded, capacity, reserve, ammo, ammo_name, reloading,
                                     #  reload_progress, mode, slot, unlimited}
func current_id() -> String
func is_reloading() -> bool
func reload_progress() -> float
func cooldown() -> float

# Crafting (src/survival/crafting.gd)
static func convert_scrap(state, n := 1) -> Dictionary
static func process(state, recipe: String, units := 1) -> Dictionary
static func can_process(state, recipe: String) -> String
static func max_units(state, recipe: String) -> int

# Difficulty: valid, get_value, name_of, desc_of, start_rounds
# Items: slot, is_unique, is_raw (plus the Experiment 002 helpers)
```

## Integration (Phase B)

### Game (`src/game/survival_game.gd`)

1. **Create the handler** after the player and world exist:
   ```
   weapons = WeaponHandler.new(); weapons.name = "Weapons"; add_child(weapons)
   weapons.setup(state, world, player)
   ```
   Call `setup` again with the new state after a load or a new run.
2. **Firing:** replace the body of `_physics_process`'s trigger block and `_fire`. Remove `_fire_cd`, `_dry_cd` and `Tuning.FIRE_INTERVAL` from the game: the handler owns the fire interval and the dry-click throttle.
   ```
   if _trigger:
       var res := weapons.try_fire(player.aim_point)
       if res["ok"]: shots_fired += 1
   ```
   `_can_fire()` gates it as today. Let `debug_fire_at` return `weapons.try_fire(...)`.
3. **"Out of ammo" toast:** connect `weapons.empty` to a toast. Use "Out of ammo" only when `weapons.current()["reserve"] == 0`; otherwise say "Reloading". The handler has already started the reload.
4. **Input** (outside build mode, SPEC-003 §8):
   - `reload` → `weapons.reload()`, showing a non-empty reason other than "Full." as a toast;
   - `weapon_next` → `weapons.next()`;
   - `weapon_1` → `weapons.select_slot("primary")`, `weapon_2` → `weapons.select_slot("secondary")`.
   - In build mode, R and the number keys keep their build meaning.
5. **Player damage:** keep `state.damage(state.enemy_damage(), "psycho")`; the vest applies inside. For other archetypes pass their name as the cause (`"runner"`, `"brute"`). For the bomber's blast, use `state.damage(amount, "blast")`. Every cause except starvation and dehydration is reduced.
6. **Sleep text:** `plan_sleep` has a new reason `"needs"`. The game's wake-up toast should use `plan["text"]` for every reason except the invasion's own line. Today it shows "You wake to something at the door." for anything but a straggler.
7. **Weapon sounds** (optional, audio owner): when Sfx gains `weapon/shotgun_fire`, `weapon/reload`, `weapon/reload_done`, `weapon/shell_load` and `weapon/switch`, the handler uses them automatically. Until then it falls back to `weapon/handgun_fire` (+3 dB) and quiet `weapon/dry_fire` clicks.

### HUD

Read `weapons.current()`:

- the weapon name;
- `loaded / capacity`, with the reserve `reserve` and `ammo_name`;
- a reload bar from `reloading` and `reload_progress`;
- "unlimited" when `unlimited`.

Refresh on `state.changed`, `weapons.fired / reloaded / switched / reload_started` and while `reloading`. Out of ammo means `loaded == 0 and reserve == 0`.

### Equipment panel

- **Slots:** `Equipment.SLOTS` with `Equipment.SLOT_NAMES` and `state.equipped(slot)`.
- **Candidates for a slot:** owned items where `Equipment.fits(id, slot)`.
- **Buttons:** `state.equip(id, slot)` (show the returned reason) and `state.unequip(slot)`.
- Refresh on `state.equipment_changed`.
- **Inventory panel:** `GROUPS` needs `weapon`, `protective` and `utility` rows, or the handgun, shotgun, vest, flashlight and backpack don't appear. Show "Owned" for `Items.is_unique(id)` instead of category `tool`.

### Developer menu (F10), all through the real systems

- **Packs:**
  - `"weapons": {"shotgun": 1, "shells": 10, "ammo": 24}`;
  - `"gear": {"vest": 1, "backpack": 1, "flashlight": 1, "crowbar": 1}`;
  - `"materials": {"wood": 20, "stone": 20, "iron": 10, "nails": 40, "scrap": 10}`.
  - Added gear auto-equips into free slots. Skip owned gear with `Items.is_unique(id)` instead of category `tool`.
- **Fill magazines:** `state.set_magazine(id, WeaponDefs.capacity(id))` for each owned weapon.
- **Difficulty:** `state.set_difficulty(level)`, with `Difficulty.LEVELS` / `name_of`.
- **Workbench test:** `Crafting.convert_scrap(state, n)`.

### New Game and saving

- **New Game:** `GameState.new_run(seed, difficulty_choice)`.
- **Save v2:** `state.to_dict()` already carries `difficulty`, `equipment`, `weapons` and `active_weapon`.
- **Loading v1:** `GameState.from_dict` migrates an Experiment 002 state by itself (handgun equipped, magazine from `ammo` up to 12, Normal). `SaveGame` only needs to accept schema 1 and re-save as 2.

## Requests to other owners

- **C (world):**
  - Add an optional `max_range := Tuning.SHOT_RANGE` 5th parameter to `HouseWorld.shoot` and use it as the ray length. The handler detects it (`get_method_argument_count`) and then passes the shotgun's 14 m directly, instead of probing with `aim_ray`. Without it, the probe ignores camera-cut voxels (as `aim_ray` does) while `shoot` doesn't, which can, rarely, mark a pellet as spent when a cut wall within range would have stopped it.
  - The workbench calls `Crafting.convert_scrap(state, n)` and shows `reason` when `ok` is false.
  - Build mode may call `state.can_build()` (same rule as its `_has_hammer`).
- **X (expeditions):**
  - `state.has_equipped("flashlight" | "crowbar" | "vest" | "shotgun")` for options;
  - `state.carry_multiplier()` instead of the fixed `BACKPACK_BONUS` (only when the backpack is equipped);
  - `state.rounds_carried("ammo")` and `rounds_carried("shells")` for the rounds a trip can bring, since the starting rounds now sit in the handgun, not the inventory. `consumed` ammo is taken from the magazines too.
  - Use `Items.is_unique(id)` wherever `Items.category(id) == "tool"` meant gear, one of each (`expedition_run.gd` lines 256, 297 and 302 in the foundation; `tests/expedition/test_expedition_rules.gd` line 25). Otherwise a found flashlight or backpack gets the backpack bonus and loses the "only if not owned" rule.
  - Don't reduce `damage` for the vest: `GameState.damage` does.
- **AI:**
  - `state.enemy_damage()` already includes the difficulty; multiply only by the archetype factor;
  - `state.enemy_hp_scale()` for archetype HP;
  - the blast cause `"blast"`.
- **Audio (lead):** the optional Sfx names above.

## Tests in other folders that the new start breaks

The SPEC-mandated start (the nine rounds sit in the handgun's magazine, with no 9 mm reserve in the inventory) breaks eight checks owned by Phase B and X. They read `inventory.count("ammo")` as "the rounds the player has". In the full suite run at the end of this work: 276 passed, 8 failed, all of them these.

- **`tests/game/test_survival_game.gd`** lines 76, 97, 104, 108, 111 and 127: read `s.magazine("handgun")` instead of `s.inventory.count("ammo")`.
  - The game's firing itself is right: `use_ammo()` spends the magazine first.
  - Verified in a scratch copy: 22 of 22 pass.
- **`tests/ui/test_ui_hud.gd`** line 16 ("nine bullets"), with the HUD fix:
  - `src/ui/game_hud.gd` line 305 should show the weapon in hand: `state.magazine(state.active_weapon())`, plus the reserve, or `WeaponHandler.current()` once wired;
  - the test's line 51 then empties with `state.set_magazine("handgun", 0)`.
  - Verified: 3 of 3 pass with the HUD showing magazine + reserve.
- **`tests/expedition/test_expedition_screen.gd`** ("rounds 0..owned", "slider sets the rounds", "brought what was chosen"): the gear screen offers `inventory.count("ammo")`, now 0 at the start.
  - X should offer `state.rounds_carried("ammo")`: `expedition_screen.gd` lines 153, 569 and 645, and `expedition_data.gd` lines 415 and 425.
  - With those five lines changed the screen test passes. `test_expedition_rules::test_fuzz_invariants_over_many_seeds` then fails, because the run's own `consumed` accounting reads the inventory. X's rewrite has to count the magazines there too; `apply_expedition_report` already spends from them.

## Tests

```
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_equipment   # slots, effects, persistence, v1
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_weapons     # handler (stand-ins) and the real world
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_difficulty
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_crafting
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_survival_consolidation
```

- **`tests/survival/test_equipment_rules.gd`:**
  - the start; equip and unequip reasons; swapping weapon slots;
  - auto-equip (not the hammer, not after a deliberate unequip);
  - losing gear and the magazine going with the gun;
  - the vest per cause (with `damage_taken`), the backpack, the hammer, the flashlight and crowbar;
  - the round trip, from_dict cleaning, and the Experiment 002 migration (15 rounds → 12 + 3; 5 → 5 + 0; none → empty).
- **`tests/survival/test_difficulty_semantics.gd`:**
  - start rounds per level;
  - the invasion days per level over three invasions, straggler-free invasion nights;
  - enemy damage and wave numbers;
  - `set_difficulty`, stale rescheduling on the right grid;
  - sleep stops at the invasion on every level.
- **`tests/survival/test_crafting_scrap.gd`:** 3 → 1, leftovers, the cap and crates, the unlimited cheat, bad input, dead.
- **`tests/survival/test_survival_consolidation.gd`:** the two fixes above.
- **`tests/combat/test_weapons_handler.gd`** (stand-in world and player):
  - the magazine and the 0.2 s interval, dry clicks and `empty` throttling;
  - reload timing (1.4 s), auto-reload;
  - the six pellets inside the 9° cone, and the pellet statistics (6000 pellets: none beyond 4.5°, centred, uniform outer ring 0.36);
  - the 14 m range (probe and 5th argument);
  - shell-by-shell reload with interruption, and running out of shells;
  - the unlimited cheat, switching, `current()`, the save round trip.
- **`tests/combat/test_weapons_world.gd`** (real HouseWorld, VoxelPlayer, VoxelEnemy):
  - a handgun hit;
  - one blast at 3 m kills (every non-spent pellet went through `HouseWorld.shoot`);
  - three blasts at 18 m do nothing while the handgun hits;
  - the shotgun model on the rig.
- The Experiment 002 survival tests were updated for the new start: rounds in the magazine, no reserve, utility gear.

## Preview harness

`src/combat/weapon_preview.tscn` sets up:

- the real house world, the player on the front yard and two psychos;
- a handler with the handgun (12 rounds, 24 in reserve) and the shotgun (5 shells, 12 in reserve).

Controls: WASD, mouse aim, hold LMB, R, Q, 1, 2, and U for the unlimited cheat. A static label shows the readout.

Screenshot mode: `--weapon=handgun|shotgun --shot-at=<s>` fires once at the nearest psycho and freezes the effects:

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/combat/weapon_preview.tscn /abs/shotgun.png 2.0 --weapon=shotgun --shot-at=1.5
```

Two day captures were taken this way (lavapipe), one per weapon: `k_handgun_day.png` and `k_shotgun_day.png`. They show the muzzle flash, the tracers and the hit psycho flashing; in the shotgun one, several pellet tracers and the placeholder's long barrel. They are handed to the lead with the report (not committed).

## Known limitations

- The shotgun model is a placeholder of boxes on the rig's arm. Its `StandardMaterial3D` isn't part of the night material list, so at night it is lit only by the scene's lights.
- Without C's `max_range` parameter, the 14 m range uses an `aim_ray` probe, with the camera-cut caveat above.
- Weapon sounds fall back to existing names until the new ones exist.
- No melee, no weapon customisation, no damage falloff inside the range (out of scope).
