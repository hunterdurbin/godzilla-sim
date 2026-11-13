---
name: verify
description: Drive the real game (GameBoard) headfully and capture screenshots to verify presentation changes end-to-end. Use when a change touches scenes/board/, overlays, or other UI and you need runtime evidence, not just tests; for a one-command smoke run (smoke.sh) after an engine/logic change; or to check a specific card/effect on the real board (scenario.sh).
---

# Verifying UI changes by driving the real game

Godot binary: use `godot` if it's on PATH; otherwise discover the local
install (e.g. `which godot`, shell aliases, or the platform's app location
such as `<Godot.app>/Contents/MacOS/Godot` on macOS).

## Smoke run: engine/logic changes

When the change is engine or logic only and you just need proof the real
board still runs, run `.claude/skills/verify/smoke.sh <godot> [turns]
[shots_dir]`: a solo game that ends the main phase for N turns (default 4)
with effect overlays auto-closed. Done = `SMOKE PASS` (exit 0); `SMOKE FAIL`
means a SCRIPT/Parse error, a stalled turn (`smoke_stall.png`), or a timeout.
Look at `smoke_end.png` before reporting. For specific behaviour on the
board, write a scenario (next section).

## Scenarios: specific behaviour on the real board

`.claude/skills/verify/scenario.sh <godot> <scenario.gd> [shots_dir]` starts
a real solo game and calls the scenario's `run(v)`. A scenario is a
`extends RefCounted` script compiled at runtime, so a throwaway in the
scratchpad works; copy `scenarios/effect_strategy_and_reveal.gd` to start,
and commit one under `scenarios/` when it is worth re-running.
Done = `SCENARIO PASS`; read the `[Scenario]` lines and look at the shots.

- **Stage state with `v.ed` (BoardEditor)**: `mint_card`, `set_strategy`,
  `add_to_hand` / `add_to_deck` / `add_to_discard`, `add_to_zone`,
  `set_rage`, … They mint unique instance ids, register effects for field
  cards and emit the change signals — never assign `strategy_zones[i]` /
  push onto piles by hand in a scenario.
- **Fire the thing under test on `v.h` (EffectHandler) or the board's
  buttons**. An entry point that opens an overlay awaits it: call it without
  `await`, `await v.wait(…)`, `v.shot(…)`, then `v.close_overlays()`.
- Helpers: `v.board v.tm v.gs v.h v.ed`, `await v.wait(sec)`, `v.shot(label)`,
  `v.close_overlays()`, `v.log_tail(n)`, `v.note(msg)` (full list:
  `scenario_driver.gd` header).

## Recipe: temporary driver scene (other scenes)

For scenes other than a running board (menus, deck builder) write a driver.
`GameBoard.tscn` is directly launchable: with default autoload state
(`NetworkManager.mode == Mode.SOLO`, `local_player_id -1 → 0`) it starts a
real solo hotseat game immediately (P1 goes first, decks load from
DecklistManager). Wrap it in a throwaway driver scene at the project root
(**delete both files when done**):

```
# __verify_driver.tscn
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://__verify_driver.gd" id="1"]
[node name="VerifyDriver" type="Node"]
script = ExtResource("1")
```

```gdscript
# __verify_driver.gd
extends Node
var board: Node
func _ready() -> void:
    # For mobile layout: GameSettings.use_mobile_layout = true (before instantiate)
    board = load("res://scenes/board/GameBoard.tscn").instantiate()
    add_child(board)
    _run()

func _run() -> void:
    await get_tree().create_timer(1.0).timeout
    _shot("01")
    ...

func _shot(n: String) -> void:
    get_viewport().get_texture().get_image().save_png("<scratchpad>/" + n + ".png")
```

Run **headfully** (viewport capture needs rendering): 
`godot --path . res://__verify_driver.tscn` — pass user args after `--`
(e.g. `-- --mobile-check` if the driver reads `OS.get_cmdline_user_args()`).

## Driving the game

- Press real buttons via `btn.pressed.emit()` — this exercises the same
  handlers as a click (including `await btn.pressed` confirmation flows).
- Use the board's **@onready refs** (`board.btn_end_main`, `board.btn_confirm`,
  `board._sys_menu._save_game_button`), NOT node paths — the mobile layout reparents
  the action panel, so `ActionPanel/Row2/EndMain` paths break there.
- Read state via `board._get_current_pid()`, `board.turn_manager.game_state`
  (turn_number/current_phase/current_sub_phase), and the game log tail:
  `board.get_node("LogPanel/LogVBox/LogOutput").get_parsed_text()`.
- **Card-effect overlays stall phase advance**: effects (e.g. mill reveals)
  pop a card-reveal overlay with a Close button and the engine awaits it.
  Poll for any visible enabled Button whose text contains "close"
  (text may be the raw `STR_GB_CLOSE` key) and emit `pressed`.
- Turn flow after End Main: PASS → Counter Phase (auto with default
  settings) → End Phase → next turn. Poll `_get_current_pid()` for the flip.

## Save/load probe

`board._sys_menu._save_game_button.pressed.emit()` writes to
`user://saves/<version>/recent/` (macOS:
`~/Library/Application Support/Godot/app_userdata/Unofficial Godzilla Sim/saves/`).
To reload in-process: `GameSerializer.pending_load =
GameSerializer.load_save_file(path)` then instantiate a fresh GameBoard.
**Delete save files your runs created** (match by timestamp).

## Other scenes

Menu scenes are directly launchable the same way — e.g. instantiate
`res://scenes/menus/Options.tscn` in the driver and emit its buttons
(`options.automation_button.pressed.emit()`). If a driver mutates
GameSettings for a test, snapshot the original values and restore + `save()`
before quitting — `user://settings.cfg` is the user's real config.

## Multiplayer harness

`./tests/harness/run_harness.sh 3 <godot>` defaults to port 12091,
which collides with the user's editor-launched dev server if one is running
(`lsof -nP -iTCP:12091 -sTCP:LISTEN` to check). Run `PORT=12191 ./scenes/...`
instead of killing anything — the user's processes are not yours to stop.

## Gotchas

- `godot --headless -s script.gd` does NOT register autoloads — every script
  referencing GameSettings/NetworkManager/CardData fails to compile. Scene
  runs (`--path . res://X.tscn`) load autoloads normally.
- Screenshots land at viewport resolution (1280x720). Zoom into details with
  `sips -c <h> <w> --cropOffset <y> <x> f.png` + `sips --resampleWidth 300`.
- Run `./tests/import.sh <godot>` after adding scripts/scenes/csv rows
  (generates .uid files, recompiles .translation).
