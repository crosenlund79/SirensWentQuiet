# Experiment 002 — Survival core and save file

Owner: S. Code: `src/survival/` (`GameState`, `Inventory`, `Items`, `SurvivalTuning`) and `src/save/save_game.gd` (`SaveGame`). Contracts: SPEC §6, §7.1 and §7.2. Everything here is pure data: no nodes, no scene access, no Autoloads.

## Rules and numbers

All numbers live in `SurvivalTuning`. Stats run from 0 to 100. Rates are per game hour.

| Rule | Value |
|---|---|
| Clock | 1 game minute per real second (`MINUTES_PER_SECOND`); the run starts on Day 1 at 07:00 |
| Events | `new_day` 00:00 · `dawn` 06:00 · `dusk` 20:00 · `invasion_due` at the scheduled time |
| Night amount | 0 from 07:00 to 19:30, smoothstep up to 1 by 21:00, 1 until 05:00, smoothstep down to 0 by 07:00 |
| Awake decay | hunger −1.25 · hydration −1.9 · energy −4.5 |
| Asleep | hunger and hydration decay ×0.6 · energy +12.5 |
| Start | health 100 · hunger 75 · hydration 70 · energy 85 |
| Starving (hunger 0) | health −4 |
| Dehydrated (hydration 0) | health −6 (stacks with starving to −10) |
| Regeneration | +1.5 awake, +3 asleep, only while hunger > 50 **and** hydration > 50 and nothing hurts |
| Speed | ×0.75 at energy ≤ 15 · ×0.6 at energy 0 |
| Warnings (`warnings()`) | "Dehydrated" (hydration 0) · "Starving" (hunger 0) · "Badly hurt" (health ≤ 30) · "Thirsty" (hydration ≤ 15) · "Hungry" (hunger ≤ 15) · "Exhausted" (energy ≤ 15) |
| Sleep refused (`can_sleep()`) | while an invasion is due or running · "You're not tired." at energy ≥ 95 when it isn't night |
| Invasions | Day 3 at 22:00, then every 3 days (Day 6, 9, … at 22:00) |
| Invasion k | size 3 + 2 (k − 1) capped at 11 · psycho HP 3 + floor((k − 1) / 2) · speed ×(1 + 0.05 (k − 1)) · hit 12 × (1 + 0.1 (k − 1)) |
| HUD warning (`invasion_due_soon()`) | from 12:00 on the invasion day until it is due |
| Stragglers (`roll_straggler(day)`) | from Day 2, 35 % per night, a whole minute from 23:00 to 02:59 the next day; never on an invasion night (Day 3, 6, 9… or the day of the scheduled invasion) |
| Rain collectors (`on_dawn(n, at)`) | +1 water per collector, once per day; pass the dawn event's `at` so each dawn of a multi-day skip counts |
| Inventory caps | planks 40 (+20 per crate) · nails 80 (+40) · scrap 20 (+10) · each tool 1 · food, water, ammo and medical uncapped (sanity bound 99 999) |
| Starting inventory | ammo 9, canned food 3, snacks 2, water 4, planks 6, nails 12, bandage 1, hammer 1 |

## How the pieces interact

### One clock

`total_minutes` counts from Day 1 00:00. Day, clock text and night amount derive from it. Every time skip goes through `advance(minutes, asleep)`: frame time, sleep, expeditions and dev skips.

- **Decay is exact and applied once.** The stats change linearly between thresholds. `advance` splits the span exactly where hunger or hydration reaches 50 (regeneration stops) or 0 (damage starts), or health reaches 0. One long call gives the same result as hundreds of small random-sized calls; a test checks this to 1e-6 over about 48 h.
- **Events come back in time order**, each exactly once, because every boundary is reported only when it lies in (start, end]. Ties are ordered `new_day`, `dawn`, `dusk`, `invasion_due`.
- **Boundaries can't be missed.** An advance that ends within 0.001 min *before* a boundary or the invasion time lands on it. So `advance(plan_sleep(x).minutes)` and `advance(until_morning_minutes())` always cross the boundary they aim for, despite float rounding.
- **Bad input does nothing.** Zero, negative, NaN and infinite minutes are ignored: no change and no `changed` signal. One call skips at most 30 days.
- **Death stops the clock.** If the player dies during an advance, the clock stops at the moment of death, and `died` listeners see that time. Only the events before it are reported. After death nothing changes: `advance` returns `[]` and the clock no longer moves, while `damage`, `heal`, `use_item`, `on_dawn` and `apply_expedition` do nothing.
- **Stat assignments are clamped.** Setting a stat directly, as the dev menu does, clamps it to 0..100 and ignores NaN.

### Invasions

The run record holds `next_invasion_at` (the next slot on the Day 3/6/9… grid), plus `invasion_announced`, `invasion_active` and `invasion_forced`.

1. When the clock reaches `next_invasion_at`, `advance` reports `invasion_due` once and sets `invasion_announced`. It is never reported again, even if the game never calls `start_invasion()`. One long skip over several slots reports only the first.
2. The game calls `start_invasion()`. While an invasion is announced or active, `can_sleep()` refuses and `plan_sleep()` returns 0 minutes.
3. `end_invasion(survived)` counts the invasion: `invasions_done` +1, which drives the size progression whether the invaders died or retreated at 06:00. `survived` only goes into the log. It then schedules the next slot after both now and the slot that was due.
4. `force_invasion_now()` (dev cheat) makes the next invasion due now: the next positive `advance` reports it. It **replaces** the upcoming regular invasion, so after it ends the next one is the slot after that. It returns false while one is announced or running.
5. `next_invasion_text()` gives "Day 3, 22:00 (in 63 h 00 min)", "Due now (invasion k)" or "In progress (invasion k)".

### Sleep

The game asks `can_sleep()`, then `plan_sleep(requested)`, then calls `advance(plan.minutes, true)`.

`plan_sleep` clamps the request to 0..24 h. It ends the sleep **exactly** at the next invasion (`reason` "invasion") or at a straggler's arrival (`reason` "straggler"; it ends a hair *after* the arrival minute, so `total_minutes >= roll_straggler(d)` holds). The result is `{"minutes", "interrupted", "reason", "text"}`, where `text` is a readable wake-up line.

A straggler that already arrived never interrupts again. Use `until_morning_minutes()` for "sleep until morning".

### Stragglers

`roll_straggler(day)` returns the **absolute** `total_minutes` of the straggler on the night that starts on `day`, or −1. The night runs from 23:00 on `day` to 03:00 on `day + 1`. The roll is deterministic from `run.seed` and the day, so a save restores the same nights. The director spawns the straggler when the clock passes that minute. `plan_sleep` makes sure the player wakes for it.

### Expeditions

`apply_expedition(result)` returns the clock events of the trip. `apply_expedition_report(result)` does the same, and also reports what actually happened:

```
{"applied", "events", "added", "left_behind", "consumed", "lost", "damage"}
```

Order of application:

1. The id guard: an empty id, an id seen in the last 64 results, or a dead player means nothing is applied.
2. Time passes awake, clamped to 0..24 h.
3. `consumed`, then `lost`, are removed, each clamped to what is owned.
4. `gained` is added up to the caps. Whatever doesn't fit is in `left_behind`, on top of anything E already left behind.
5. `damage` is applied (cause "expedition"), clamped to 0..100. The invulnerable cheat blocks it.

Unknown items, non-numeric, negative and NaN amounts and non-Dictionary sections are ignored. Counts never become negative or non-int; a 400-result fuzz test covers this.

### Cheats

- **`invulnerable`** blocks every source of damage: enemies, starvation, dehydration and expeditions. With it on, the player can never die.
- **`unlimited`** makes `can_pay` and `pay` succeed, and `use_ammo` always succeed, without touching the inventory. It never creates items. `use_item` still consumes.

### Inventory

Counts are non-negative ints of known items only. `remove` and `remove_all` (a whole cost) are all-or-nothing.

- **Untrusted amounts** go through `Inventory.to_count`: ints pass, finite floats round, numeric strings parse, and anything else is invalid.
- **Costs:** an invalid amount can't be paid, zero and negative amounts are ignored, and an unknown item with a positive amount can't be paid.
- **Losing a crate** keeps materials stored above the new cap; only further adds are refused.

## Save file

### Format

One slot at `user://savegame.dat`; tests use `SaveGame.path_override`. The game composes:

```
{"summary": state.summary(), "state": state.to_dict(), "world": world.save_data(), "game": {...}}
```

`write()` adds `"schema"` (1), `"game_id"` (`"sirens_went_quiet"`) and `"saved_at"` (unix seconds). The identifier is `game_id`, not `game`, because `"game"` holds G's dictionary.

`"state"` must be a Dictionary; `"world"` and `"game"` default to `{}`. Any other type is refused and nothing is written.

File layout (little-endian):

| Offset | Field |
|---|---|
| 0 | magic `SWQS` |
| 4 | u32 format (1) |
| 8 | u32 schema |
| 12 | u64 saved_at |
| 20 | u32 codec (1 = zstd) |
| 24 | u32 uncompressed size |
| 28 | u32 summary size |
| 32 | u32 payload size |
| 36 | MD5 of summary + payload (16 bytes) |
| 52 | summary: `var_to_bytes(summary)` |
| … | payload: `var_to_bytes(data)` compressed with zstd |

`var_to_bytes` is the same Godot binary Variant encoding that `store_var` writes, without objects.

**Why compress.** I measured with the real voxel house grid (149 × 31 × 99, 457 k voxels), plus a damaged copy and a design copy (6.9 MB raw). zstd shrank it to 471 KB (6.9 %): compression took 11 ms, decompression 6 ms and decoding 7 ms. Plain `store_var` took 9 ms to write and 11 ms to read. Deflate was 504 KB but took 74 ms. In the test suite, the 4 MB blob took 23–33 ms to write and 9–19 ms to read over three runs. These are headless timings on this container.

### Writing safely

1. Encode, compress and write `<path>.tmp`, then close it.
2. Re-open the tmp file, check header and checksum, decompress, compare the bytes with what was meant to be written, and decode and validate it. On failure the tmp is deleted and the old save is untouched: `ERR_FILE_CORRUPT`.
3. If the current main file is valid, rotate it to `<path>.bak`, replacing the older backup. A damaged main file is deleted instead, so it never replaces a good backup.
4. Rename the tmp file to the main path.

A crash at any step leaves the last good save readable, as the main file or as the `.bak`. Every failure returns an `Error` and sets `SaveGame.last_error` to a readable sentence.

### Reading

`read()` returns `{"ok", "error", "data", "restored_from_backup"}`. If the main file is missing or unusable, it loads the `.bak` and returns `ok: true, restored_from_backup: true` and a `backup_reason`.

Checks run in this order:

1. The file opens.
2. It isn't empty and is at most 256 MB.
3. The magic matches.
4. The format and schema match.
5. The sizes add up to the file length exactly.
6. The header is sane: an uncompressed size of at most 512 MB.
7. The MD5 matches.
8. It decompresses to the exact size.
9. It decodes to a Dictionary with `game_id`, an int `schema`, a Dictionary `state` and Dictionary `world` and `game`.

Corrupt files are rejected by the size and checksum checks before anything is decoded, so garbage never reaches the decoder.

Errors are readable:

- "No saved game."
- "The save file is empty."
- "The save file is damaged (it was cut off)."
- "… (it failed its integrity check)."
- "The save is from an older version of the game." This includes files in the foundation's plain `store_var` layout.
- "The save is from a newer version of the game."
- "This is not a Sirens Went Quiet save file."
- "The save could not be opened (a folder is in its place)."

### Other calls

- **`info()`** is cheap for the main menu: it reads the header, summary and checksum, but never decompresses or decodes the payload. It returns `{"exists", "valid", "schema", "saved_at", "summary", "error", "restored_from_backup"}`. `valid` is also true when only the `.bak` is good.
- **`delete_save()`** removes the main file, the `.bak` and any leftover `.tmp`, so a dead run can't be continued.

### GameState persistence

`to_dict()` stores the clock, stats, inventory, cheats, run record, `dead` and `death_cause`.

`from_dict(d)` accepts any Variant. It returns **null** when the input is not a Dictionary, or when the clock, a stat, the inventory or the run record is missing, of the wrong type, NaN or infinite. Otherwise it cleans the rest:

- stats are clamped, and the clock is clamped to Day 1 07:00 … 10 years;
- unknown items, bad counts and bad cheat flags are dropped;
- the run record is sanitised field by field, and **unknown run keys from other modules are kept**;
- a restored run never has an invasion running. An invasion that was due when saved (announced, or even started) is reported again by the next `advance`, unless it is more than 8 h overdue; then the schedule moves to the next slot. An invalid schedule is rebuilt from the grid;
- health 0 restores as dead.

The summary keys are `day`, `clock`, `health`, `days_survived`, `invasions_done` and `dead`.

### Limitations

- **One slot.** There is one backup generation, and no recovery from the `.tmp` of a crashed write (the `.bak` is used instead).
- **No live encounters.** Saving is blocked while enemies are alive (G's `can_save`), so a running invasion is never saved. If one is saved anyway, loading drops the running state and the invasion becomes due again (within 8 h of its time).
- **Engine-bound encoding.** The format is Godot's binary Variant encoding inside the file, so a save is tied to Godot 4's encoding.
- **No integrity check for world contents.** The checksum detects corruption, but V's `load_data` must still validate the world data.

## How to test

```
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_save_game
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_clock      # or test_stats, test_invasions,
     # test_sleep_stragglers, test_inventory, test_cheats_expeditions, test_state_persistence, test_game_state_core
```

The test files and what they cover:

- **`tests/survival/test_clock.gd`**: event order, small steps equal one big step, long advances and the cap, bad input, death stopping the clock, landing exactly on dawn, night amount.
- **`tests/survival/test_stats.gd`**: decay awake and asleep, regeneration and its threshold split, starvation and dehydration, `died` once, bad damage and heal amounts, clamped assignments, speed, warnings, item use, summary.
- **`tests/survival/test_invasions.gd`**: due once, the long skip, sleep ending exactly at the invasion, start and end scheduling, progression, the warning window, the forced invasion, the text, a restored overdue invasion.
- **`tests/survival/test_sleep_stragglers.gd`**: `can_sleep`, the straggler rules and their determinism (2000 seeds give about 35 %), straggler interruption, rain collectors.
- **`tests/survival/test_inventory.gd`**: caps with crates, untrusted amounts, atomic costs, signals, `from_dict`, the catalogue.
- **`tests/survival/test_cheats_expeditions.gd`**: both cheats, expedition application and clamping, death on an expedition, the 400-result fuzz.
- **`tests/survival/test_state_persistence.gd`**: exact round trip, null cases, cleaning, a 500-dict mutation fuzz.
- **`tests/save/test_save_game.gd`**: a 4 MB blob round trip, input validation, rotation, a simulated failed verification (`fault_injection = "corrupt_tmp"`), a failed final rename falling back to `.bak` (`"fail_rename"`), a bit flip, truncated, empty, garbage and huge-header files, schema mismatch, foreign and foundation-format files, `info()` not unpacking, a directory in place of the file, delete, a stale tmp file.

The save tests write only under `user://test_save_s_<pid>/` and reset `path_override` even when a test aborts.
