extends SceneTree

## Validates that a GameBoard scene satisfies the cross-scene multiplayer
## contract — root named "GameBoard" with a GameSession subtree containing
## MultiplayerSync and (recommended) EffectUIRouter.
##
## Usage:
##   godot --headless --quit --script scripts/tools/check_designer_contract.gd \
##       -- res://scenes/board/designer/DesignerGameBoard.tscn
##
## Or run against every *GameBoard.tscn in scenes/board/:
##   godot --headless --quit --script scripts/tools/check_designer_contract.gd \
##       -- --all
##
## Exit code: 0 if every checked scene passes, 1 otherwise.

const _BOARD_DIR := "res://scenes/board/"
const _EXCLUDE := [
	# Templates aren't meant to be runnable on their own.
	"GameBoardBase.tscn",
	"GameBoardTemplate.tscn",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Usage: -- <res://path/To/GameBoard.tscn> | -- --all")
		return
	var failures := 0
	if args[0] == "--all":
		var paths := _scan_all()
		print("[check] Checking %d scene(s) under %s..." % [paths.size(), _BOARD_DIR])
		for p in paths:
			if not _check_scene(p):
				failures += 1
	else:
		if not _check_scene(args[0]):
			failures += 1
	if failures > 0:
		print("\n[check] %d scene(s) failed the contract." % failures)
		quit(1)
	else:
		print("\n[check] All scenes passed.")
		quit(0)


## Recursively walk _BOARD_DIR, return paths to every *GameBoard.tscn
## not in _EXCLUDE. Mirrors MainMenu's picker scan logic.
func _scan_all() -> Array[String]:
	var out: Array[String] = []
	_scan_in(_BOARD_DIR, out)
	out.sort()
	return out


func _scan_in(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			_scan_in(dir_path.path_join(fname), out)
		elif fname.ends_with("GameBoard.tscn") and fname not in _EXCLUDE:
			out.append(dir_path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()


## Returns true if the scene satisfies the cross-scene multiplayer contract.
## Prints per-check pass/fail to stdout.
func _check_scene(path: String) -> bool:
	print("\n[check] %s" % path)
	var packed := load(path)
	if packed == null:
		print("  ✗ Failed to load scene.")
		return false
	var root: Node = packed.instantiate()
	if root == null:
		print("  ✗ Failed to instantiate root.")
		return false
	# Check structural fields BEFORE adding to tree, so sequential
	# checks don't cause Godot to auto-rename the root (it would clash
	# with the previously-checked scene's "GameBoard" sibling that's
	# still in /root awaiting deferred free).
	var ok := true
	if root.name != "GameBoard":
		print("  ✗ Root node is named '%s' — must be 'GameBoard' for cross-scene multiplayer." % root.name)
		ok = false
	else:
		print("  ✓ Root named 'GameBoard'.")
	var session := root.get_node_or_null("GameSession")
	if session == null:
		print("  ✗ Missing 'GameSession' child node.")
		ok = false
	else:
		print("  ✓ GameSession child present.")
		if session.get_node_or_null("MultiplayerSync") == null:
			print("  ✗ Missing 'GameSession/MultiplayerSync' — RPCs will not route.")
			ok = false
		else:
			print("  ✓ GameSession/MultiplayerSync child present.")
		if session.get_node_or_null("EffectUIRouter") == null:
			print("  ⚠ Missing 'GameSession/EffectUIRouter' — effect prompts will silently auto-resolve. (warning)")
		else:
			print("  ✓ GameSession/EffectUIRouter child present.")
	# Free the off-tree instance immediately. We never added it to the
	# tree, so no _ready warnings fire (and there are no orphaned RPCs
	# to clean up).
	root.free()
	return ok


func _fail(msg: String) -> void:
	push_error(msg)
	quit(1)
