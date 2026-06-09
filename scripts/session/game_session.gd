class_name GameSession
extends Node

## Owns the runtime layer of a game session. Migration is staged:
##   Step 1 (this step) — node exists in the scene tree as the stable parent
##     of MultiplayerSync; behavior unchanged.
##   Step 2 — TurnManager / BotPlayer / ReplayRecorder construction and the
##     client-side state caches move here from game_board.gd.
##
## Cross-scene multiplayer contract: every GameBoard scene's root node must be
## named "GameBoard" so MultiplayerSync's NodePath is identical on host and
## client even when they load different .tscn files.

## Fired once the session is ready for module binding. On host/solo this fires
## when the host session starts. On client peers it fires after the first
## state broadcast populates the client caches — modules can subscribe once
## and bind regardless of mode.
signal session_started

var _board: Node


func _ready() -> void:
	_board = get_parent()
	if _board and _board.name != "GameBoard":
		push_error("[GameSession] Parent node is named '%s' — must be named 'GameBoard' for cross-scene multiplayer to work." % _board.name)
	if get_node_or_null("MultiplayerSync") == null:
		push_error("[GameSession] No 'MultiplayerSync' child node — multiplayer RPCs will not route.")
