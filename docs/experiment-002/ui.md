# Experiment 002 — UI (owner U)

Menus, panels and the HUD for *The First Days*, all in one visual language. Contracts: `docs/experiment-002/SPEC.md` §2, §3, §7.8. Everything lives in `src/ui/`, `src/menu/` and `src/launcher/`. Tests: `tests/ui/`.

## Screens

| Screen | Class / scene | Opens from | Pauses the tree | Closes with | Emits |
|---|---|---|---|---|---|
| Main menu | `src/menu/main_menu.tscn` (main scene) | start, `GameLaunch.MENU_SCENE` | n/a | — | changes scene |
| Settings | `SettingsPanel` | main menu, pause menu | caller decides | Back, Esc | `closed` |
| Pause menu | `PauseMenu` | Esc in game (G) | yes (G) | Resume, Esc | `resume_requested`, `save_requested`, `settings_requested`, `main_menu_requested` |
| HUD | `GameHud` | game root | no | — | — |
| Inventory | `InventoryPanel` | I / Tab (G) | yes (G) | I, Tab, Esc, Close | `closed` |
| Developer menu | `DevMenu` | F10 (G calls `toggle()`) | **no** | F10 | — |
| Sleep | `SleepDialog` | the bed (`game.open_sleep()`) | yes (G) | Cancel, Esc | `sleep_chosen(minutes)`, `closed` |
| Death | `DeathScreen` | `GameState.died` (G) | yes (G) | Main Menu only | `main_menu_requested` |
| Intro | `IntroOverlay` | new run (G calls `play()`) | G decides | any key / click skips | `done` (once) |
| Confirm | `ConfirmDialog` | anything | — | the buttons, Esc = no | `answered(yes)` |
| Visual Experiments | `src/launcher/launcher.tscn` | main menu | n/a | Back, Esc → main menu | — |

All panels run with `process_mode = ALWAYS`, take keyboard focus on their first enabled button (Up/Down/Enter work everywhere), and share the same fade, scrim and margins through `UiModal`.

### Main menu

- Title, a quiet subtitle and a background shader of a silent suburban street in drifting fog with an abandoned siren mast (one full-screen canvas shader, four-octave noise; no textures).
- **New Game** asks for confirmation when `SaveGame.info()["exists"]` ("This will overwrite your current survival run."), then sets `GameLaunch.mode = "new"` and changes to `GameLaunch.GAME_SCENE`.
- **Continue** is enabled only when `SaveGame.info()["valid"]`. Its right-hand caption shows the save summary (`Day 4 · 21:15`) or the reason it is disabled (`No saved game`, `Can't be loaded` plus the full error line under the buttons). Sets `GameLaunch.mode = "continue"`.
- **Settings**, **Visual Experiments** (`GameLaunch.EXPERIMENTS_SCENE`), **Quit**.
- On start: unpauses the tree, resets `Engine.time_scale`, `GameSettings.apply()`, `Sfx.attach(self)`, `Sfx.music("music/menu")`; shows `GameLaunch.notice` once in a notice dialog and clears it. Leaving fades to black and calls `Sfx.music("")`.
- The save summary is read by `UiTheme.save_summary_text(summary)`: it uses `summary["text"]` if present, else `day` + `clock` (or `time`), else `total_minutes`. **G:** please write `{"day": int, "clock": "HH:MM"}` (adding `total_minutes` is fine).

### Settings

Master, sound effects, ambient and music sliders (applied live to the buses of `default_bus_layout.tres`), a fullscreen toggle, and the controls reference (every SPEC §3 action, build keys 1–9 and R, RMB, F3, H/F1 and F10). Values are saved when the panel closes.

`GameSettings` (static): `load_settings()`, `save_settings() -> Error`, `apply()` (loads once; safe headless), `apply_audio()`, `apply_display()` (only switches the window mode when it differs), `get_value(key)`, `set_value(key, v)` (applies live), `reset()` (tests), `path_override` (tests), `DEFAULTS`.

### Pause menu: the signal sequence (for G)

- **Resume** or **Esc**: the menu closes itself, then emits `resume_requested`. Unpause there.
- **Save**: emits `save_requested`. Save synchronously in the handler and, ideally, call `pause.report_save(error)` with `""` on success or a readable error. The menu shows "Game saved." or the error. Without `report_save` it assumes success.
- **Save** is disabled while `open(save_block_reason)` got a non-empty reason; the reason shows on the button.
- **Settings**: emits `settings_requested`. If nothing is connected to that signal, the menu opens its own `SettingsPanel` and returns when it closes. **G: don't connect it**; the built-in panel is the intended path.
- **Main Menu** shows a confirmation page: "Progress since your last save will be lost."
  - **Save and quit** (only when saving is allowed): emits `save_requested`, then `main_menu_requested`, unless `report_save()` reported an error during the save, in which case it stays and shows the error.
  - **Quit without saving**: emits `main_menu_requested`.
  - **Back** / Esc: back to the main page.
- The menu does not close itself on `main_menu_requested`; change the scene (and unpause first: the main menu also unpauses defensively).

### HUD (`GameHud`)

- **Top left:** a compact card with a sun/moon glyph that cross-fades with `state.night_amount()`, `Day N · HH:MM` and the period (Dawn, Morning, Afternoon, Evening, Dusk, Night). Below it are four stat bars: health, food, water and energy. Each is an icon, a thin bar with a tick at `SurvivalTuning.WARN_LEVEL`, and a number.
  - At ≤ 15 a bar turns amber and pulses gently. At 0 it turns red; health turns red at ≤ 15.
  - Warning words appear under the bars: Hungry/Starving, Thirsty/Dehydrated, Exhausted/Spent, Badly hurt, and "Something is coming tonight." while `state.invasion_due_soon()`.
  - If S adds `GameState.warnings()`, the HUD uses its result instead. It accepts an Array of Strings, `[text, kind]` pairs or `{"text", "kind"}` dictionaries.
- **Top centre:** `set_banner(text)` (red-edged band, pulsing; `""` hides it) and the toasts.
  - Toasts stack under the banner, at most 4. Each kind has its own colour: info, good, warn or bad.
  - A toast lasts about 3–4 s and then fades. Repeating the newest toast counts it ("Out of ammo ×3") instead of stacking another.
- **Top right:** the **CHEATS ACTIVE** badge, listing every truthy `state.cheats` entry (Invulnerable, Unlimited resources). It is visible whenever any cheat is on.
- **Bottom centre:** `set_prompt(text)`. A leading `[E]` becomes a key chip.
- **Bottom right:** the ammo count. It turns amber at ≤ 3 and red at 0 ("out of ammo"). With the unlimited cheat it reads "unlimited".
- **Bottom left:** a dim `H Controls` hint, the compact controls card (H/F1) and the FPS line (F3, off by default). **The HUD handles `toggle_stats` and `toggle_help` itself** in `_unhandled_input` and marks them handled.
- `flash_damage(strength := 1.0)`: a red edge vignette. The HUD also flashes by itself when health drops by more than 3.5 in one frame, so enemy hits show even without a call.
- `set_mode("build")` dims the clock card and hides the prompt, ammo and hints, so the bottom centre is free for the build palette. `"play"` restores them; `"hidden"` hides the whole HUD.
- Every HUD control ignores the mouse.

### Inventory

Shows the needs bars at the top, then two columns: Food, Water, Medical and Ammo on the left; Materials (`count / cap`, plus the storage-crate note) and Tools (Owned / —) on the right. Each item shows its description and effect ("food +30 · water +4"), and everything fits without scrolling.
- **Use** (consumables only) calls `state.use_item(id)`, shows the returned text and plays `player/eat`, `player/drink` or `player/bandage` through `Sfx.play`.
- An empty result shows "You can't use that right now." and plays `ui/error`.
- The panel refreshes on `state.changed`, so the developer menu can add items while it is open.

### Sleep

Shows the day and time, energy (bar and words), and a warning when `state.invasion_due_soon()` or when `plan_sleep` says the sleep will be interrupted ("You'll be woken at 22:00").
- **Sleep until morning** shows the wake time and duration, and emits `sleep_chosen(-1)`.
- **Rest 2 hours** emits `sleep_chosen(120)`.
- **Cancel** / Esc emits `closed`. A sleep choice closes the dialog and emits only `sleep_chosen`.
- If `state.can_sleep()` exists and returns a non-empty String (or `false`), both sleep buttons are disabled and the reason is shown.

### Death screen

A slow fade to near-black, "YOU DIDN'T MAKE IT", the days survived, the cause and one quiet line. **Main Menu** emits `main_menu_requested`. The button arms after 1.2 s so a held click doesn't skip the screen, and Esc does nothing.

Causes map to friendly wording: `psycho`/`enemy`/`attack` → "Killed by a psycho.", `starvation` → "Starved.", `dehydration` → "Died of thirst.", `expedition`/`fog` → "Lost out in the fog."; other causes are shown capitalised.

### Intro

Four lines over black (about 9.2 s: 0.6 s fade-in, 1.0 s hold, 0.5 s fade-out per line, then a 0.8 s reveal):
- "On the ninth day, the sirens went quiet."
- "Nobody has answered since."
- "Then the fog came in, and it stayed."
- "You still have the house." (amber)

Any key or click skips with a 0.35 s fade. `done` is emitted exactly once, after the black is gone. The overlay swallows the skip input; **G:** don't fire while it plays (`intro.is_playing`).

### Developer menu (F10)

A compact, scrollable panel on the right under a "DEVELOPER" header. It **does not pause** and its buttons never take keyboard focus, so WASD and the number keys keep working. G calls `setup(state, game)` once and `toggle()` on `dev_menu`. Stats, inventory and cheats are edited on `GameState`; every game call is guarded with `has_method`, and a missing method is reported in the status line.

| Section | Control | Effect |
|---|---|---|
| Cheats | Invulnerable (toggle) | `state.cheats.invulnerable` |
| | Unlimited resources (toggle) | `state.cheats.unlimited` |
| Supplies | + Food & water | +3 canned food, +2 snacks, +4 water |
| | + 10 ammo | +10 rounds |
| | + Materials | +20 planks, +40 nails, +10 scrap (caps apply; says "storage full") |
| | + Medical | +2 bandages, +1 first-aid kit |
| | All tools | hammer, crowbar, flashlight, backpack (no duplicates) |
| Needs | Food / Water / Energy: 0 · 25 · 50 · 100 | sets `hunger` / `hydration` / `energy` |
| Time | +1 hour | `game.dev_advance(60)` |
| | Night 20:00 / Morning 06:00 | `game.dev_skip_to(20)` / `(6)` |
| | Speed ×1 / ×4 / ×10 | `game.dev_set_time_scale(x)` |
| Threats | Next invasion | `game.dev_trigger_invasion()` |
| | Spawn 1 psycho / Spawn 3 psychos | `game.dev_spawn(1)` / `(3)` |
| | Repair house | `game.dev_repair_house()` |
| Inspect | (live, twice a second) | day, time, night amount, exact stats, move speed, days survived, inventory with caps, crates, next invasion (`state.next_invasion_text()` if present, else from `run.next_invasion_at`), run info, cheats and time scale, `SaveGame.info()` (re-read every 4 s), `game.dev_info()` |

### Visual Experiments

The Experiment 001 launcher, retitled "Visual Experiments · Experiment 001" and restyled with the shared theme.
- Its three demo buttons and the 1/2/3 (A/B/C) keys still launch the demos, and each demo's Esc still returns here.
- Esc or **Back** here returns to `GameLaunch.MENU_SCENE`.

## Theme rules (for every module)

Use `UiTheme`; don't style controls by hand. The look:

- **Palette:**
  - `BG`: dark, translucent panels. `BG_SOFT`: lighter HUD cards. `SCRIM`: behind modals.
  - `TEXT`: warm off-white. `TEXT_DIM`: captions. `TEXT_FAINT`: hints and disabled text.
  - `ACCENT`: the siren amber, and the **only** accent colour. It marks titles, focus/hover, toggles that are on, and the badge.
  - `GOOD`/`WARN`/`BAD`: feedback only (toasts, warnings, costs you can't pay).
- **Type:**
  - Headings are small caps: upper case, a reduced size and wide tracking (`UiTheme.tracked_font(n)`).
  - Panel titles use `make_title` (amber, 22). Sections use `make_section` (dim, 12, with a hairline).
  - Body text is 16, captions 14, hints 13.
- **Spacing:** panel content margin `PAD` = 18, row gap `GAP` = 10, buttons `BUTTON_HEIGHT` = 38, corner radius 3–4.
- **Buttons:** one style. Hover and focus draw a 3 px amber stripe on the left plus an amber border. Disabled buttons are faint. Buttons in vertical menus are left-aligned (`UiModal._menu_button`). Sliders have a neutral fill, and the focused or hovered slider turns amber. `make_button(text, caption)` puts a dim caption on the right: a cost, a time, or the reason the button is disabled. Always give the reason.
- **Motion:** panels fade in over `FADE_IN` (0.16 s) with a 10 px rise, and fade out over `FADE_OUT` (0.12 s). Toasts fade in over 0.15 s and out over 0.4 s.
- **Sound:**
  - `make_button` / `make_toggle` play `ui/hover` and `ui/click`.
  - Every modal plays `ui/open` / `ui/close`.
  - Programmatic focus is silent (`UiTheme.focus_quietly`).
- **HUD:** small cards, outlined labels (`make_hud_label`), and every control with `MOUSE_FILTER_IGNORE`. No big debug panels.

### Helpers

| Helper | Returns | Use |
|---|---|---|
| `UiTheme.theme()` | `Theme` | Set on any root Control: `root.theme = UiTheme.theme()` |
| `make_panel()` / `make_card()` | `PanelContainer` | Panel / translucent HUD card |
| `make_title(text, size)` | `Label` | Small-caps amber heading |
| `make_section(text)` | `HBoxContainer` | Small-caps section rule |
| `make_label(text, size, color)` / `make_caption(text, width, color)` / `make_hud_label(...)` | `Label` | Body text / dim wrapped text / outlined HUD text |
| `make_button(text, caption := "")`, `set_caption(b, text)`, `caption_of(b)` | `Button` | The one button |
| `make_toggle(text, on)` | `UiToggle` | On/off with a pill switch |
| `make_slider(min, max, step)` | `HSlider` | Themed slider |
| `make_key_chip(key)` / `make_key_hint("I / Tab", "Inventory")` | chip / row | Key caps; `" / "` separates keys |
| `make_stat_bar(kind, label)` | `UiStatBar` | Icon, bar and number with warn/critical states; `set_value(v)` |
| `make_icon(kind, size, color)` | `UiIcon` | Vector icons: sun, moon, health, food, water, energy, ammo, warn, cheat |
| `make_scrim()`, `make_spacer(h)` | Control | Modal dimmer, vertical gap |
| `day_time_text(day, clock)`, `clock_from_minutes(m)`, `duration_text(m)`, `save_summary_text(summary)` | `String` | "Day 3 · 21:40", "21:40", "2 h 30", the save summary |
| `focus_quietly(c)`, `first_focusable(root)`, `fade(item, alpha, time)`, `ui_sound(name)` | — | Focus, motion, sound |

**A whole modal screen:** extend `UiModal` (as `PauseMenu` etc. do):

```gdscript
class_name MyScreen
extends UiModal

func _init() -> void:
	super()          # GDScript does not call the parent _init implicitly
	layer = 60

func open(state: GameState) -> void:
	var box := _begin("Into the fog", 560)      # scrim + centred panel + title; returns the content box
	box.add_child(UiTheme.make_section("Destinations"))
	box.add_child(UiTheme.make_button("Nearby homes", "2 h"))
	box.add_child(_footer("Esc", "Back", [UiTheme.make_button("Go")]))
	_show()                                     # fade in, focus the first enabled button

func _on_cancel() -> void:                       # Esc / ui_cancel
	close()
```

`UiModal` also provides `is_open`, `close()`, `_button_row(buttons)`, `_focus(control)`, and `dim_background` / `panel_width` / `fade_in_time`.

Layers: HUD 40, expedition (E) 60, panels 70, settings 72, death 76, developer 80, confirm 85, intro 90.

## Wiring checklist for the game root (G)

1. `hud = GameHud.new(); add_child(hud); hud.setup(state)`. Call `hud.setup(new_state)` again if the state object is replaced, `hud.set_prompt(...)` every frame, `hud.toast(...)`, `hud.set_banner(...)`, `hud.set_mode("build"/"play")`, and optionally `hud.flash_damage()`. Don't handle F3 or H/F1 yourself.
2. Pause: `pause.open(can_save())` with the tree paused. Connect `resume_requested` (unpause), `save_requested` (`var e := save_now(); pause.report_save(e)`) and `main_menu_requested` (unpause, change scene). Leave `settings_requested` unconnected.
3. Inventory: `inventory.open(state)` with the tree paused, and `closed` → unpause. The panel closes itself on I/Tab/Esc.
4. Sleep: `open_sleep()` → `sleep.open(state)`; `sleep_chosen(m)` (-1 = until morning), `closed` → unpause.
5. Death: `death.open(state.days_survived(), cause)`; `main_menu_requested` → change scene.
6. Intro: `intro.play()` on a new run; `done` → start. Ignore firing while `intro.is_playing`.
7. Dev menu: `dev.setup(state, self)` and `dev.toggle()` on `dev_menu`. Implement `dev_*` (SPEC §7.8).
8. Don't fire the gun while the mouse is over UI: `get_viewport().gui_get_hovered_control() != null` (relevant to the dev menu, which doesn't pause).

## How to test

- Unit/integration tests (headless):

  ```
  godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_ui
  ```

  | File | Covers |
  |---|---|
  | `test_ui_panels.gd` | Theme helpers, confirm dialog, pause menu (save block, signal order, `report_save`, Esc), built-in settings, settings persistence, inventory Use and close keys, sleep choices and `can_sleep`, death screen, intro (full run and skip, `done` once) |
  | `test_ui_main_menu.gd` | Continue with no save, a valid save and an invalid save (`SaveGame.path_override`); New Game confirmation; the notice; settings; Visual Experiments |
  | `test_ui_dev_menu.gd` | Dev API calls on a fake game; cheats, supplies, needs; inspect; a game with no dev methods |
  | `test_ui_hud.gd` | Clock and glyph, warnings, damage flash, cheats badge, ammo, invasion warning, prompt chip, toast coalescing/cap/fade, banner, build mode, F3 |

- Screenshots (Xvfb + lavapipe):
  - One screen:

    ```
    CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/menu/main_menu.tscn /abs/menu.png 2
    CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/ui/preview/ui_preview.tscn /abs/s.png 2 --base=menu --ui=settings
    ```

  - Many game-scene shots from one load (the game scene takes about 3 min per load under lavapipe):

    ```
    CAPTURE_TIMEOUT=1500 CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/ui/preview/ui_preview.tscn /abs/unused.png 9999 --sequence=/abs/dir
    ```

  - `src/ui/preview/ui_preview.gd` is a review harness only. It loads `res://src/game/game.tscn` (or the main menu with `--base=menu`) and opens one panel (`--ui=...`), or shoots the full sequence (`--sequence=`). It reads `state`, `hud` and `player` from the game root when they exist.
- Manual checklist (needs a person; not done by the agent): mouse hover and click sounds once A's sounds exist; slider feel; fullscreen toggle on a real desktop; keyboard-only navigation of every panel.
