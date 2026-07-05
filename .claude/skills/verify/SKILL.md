---
name: verify
description: Drive the real game (GameBoard) headfully and capture screenshots to verify presentation changes end-to-end. Use when a change touches scenes/board/, overlays, or other UI and you need runtime evidence, not just tests.
---

# Verifying UI changes by driving the real game

Godot binary: use `godot` if it's on PATH; otherwise discover the local
install (e.g. `which godot`, shell aliases, or the platform's app location
such as `<Godot.app>/Contents/MacOS/Godot` on macOS).

## Recipe: temporary driver scene

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
  `board._save_game_button`), NOT node paths — the mobile layout reparents
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

`board._save_game_button.pressed.emit()` writes to
`user://saves/<version>/recent/` (macOS:
`~/Library/Application Support/Godot/app_userdata/Unofficial Godzilla Sim/saves/`).
To reload in-process: `GameSerializer.pending_load =
GameSerializer.load_save_file(path)` then instantiate a fresh GameBoard.
**Delete save files your runs created** (match by timestamp).

## Other scenes

Menu scenes are directly launchable the same way — e.g. instantiate
`res://scenes/ui/Options.tscn` in the driver and emit its buttons
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
- Run `godot --headless --path . --import` after adding scripts/scenes/csv
  rows (generates .uid files, recompiles .translation).
