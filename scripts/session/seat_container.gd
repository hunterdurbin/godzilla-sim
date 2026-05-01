class_name SeatContainer
extends Control

## Marks a subtree of a GameBoard scene as belonging to a particular
## seat. Modules placed under this container (PlayerBoard, RageDisplay,
## ThreatDisplay, DeckCountLabel, DiscardCountLabel, ...) auto-resolve
## their player_id from this seat's `role` instead of needing per-module
## inspector configuration.
##
## Seat is a UI concept only — the engine and multiplayer sync still
## know just player_id 0 and 1. SeatContainer is the layer that maps
## "which side of the screen is this" to a concrete player_id at scene
## load, using NetworkManager.local_player_id.
##
## Usage in a scene:
##   GameBoard
##   ├── GameSession ...
##   └── BoardLayoutSlot
##       ├── LocalSeat       (SeatContainer, role=LOCAL)
##       │   ├── PlayerBoard
##       │   ├── RageDisplay
##       │   └── DiscardCountLabel
##       └── OpponentSeat    (SeatContainer, role=OPPONENT)
##           └── PlayerBoard
##
## See docs/new_game_board.md for the full pattern.

enum Role {
	LOCAL,      # this peer's player — resolves to NetworkManager.local_player_id
	OPPONENT,   # the other player — resolves to 1 - NetworkManager.local_player_id
	PLAYER_0,   # explicit player 0 — for spectator / replay scenes
	PLAYER_1,   # explicit player 1
}

## Fired when the seat's role changes after _ready (e.g. spectator
## clicks a "swap sides" button). Modules subscribe in their _try_bind()
## and re-resolve / re-bind. Carries the newly-resolved player_id.
signal role_changed(new_player_id: int)

@export var role: Role = Role.LOCAL:
	set(value):
		if role == value:
			return
		role = value
		role_changed.emit(get_player_id())

## Optional explicit references for the two main module classes a seat
## typically contains. Populating these in the inspector documents the
## seat's contents at design-time.
@export_group("Wiring (optional — for designer reference)")
## The PlayerBoard rendering this seat's player. Auto-resolved at
## _ready: prefers a manually-dropped PlayerBoard child (WYSIWYG),
## otherwise falls back to instantiating `player_board_scene` below.
@export var player_board: Node
## The HUD container (HBox/VBox) holding RageDisplay, ThreatDisplay,
## DeckCountLabel, etc. for this seat.
@export var hud_bar: Node
@export_group("")

## PlayerBoard scene to instantiate at runtime when this seat has no
## manually-dropped PlayerBoard child. Set per-seat (LocalSeat vs
## OpponentSeat) to use a different variant per side.
##
## Default points at the standard PlayerBoard.tscn so out-of-the-box
## seats just work. Set to null if you want this seat to remain empty
## until something else populates it.
##
## A manually-dropped PlayerBoard child takes priority — designer who
## wants WYSIWYG editing can keep an inspector-visible child and ignore
## this slot.
@export_group("Auto-instantiation")
@export var player_board_scene: PackedScene = preload("res://scenes/board/PlayerBoardTemplate.tscn")
@export_group("")


func _ready() -> void:
	call_deferred("_auto_instantiate_player_board")


## If the seat has no PlayerBoard descendant, instantiate one from
## `player_board_scene`. Sets `auto_bind=true` and seat-derived
## `is_mirrored` / `player_id` so the new board self-resolves into the
## session without further wiring. Designer-dropped PlayerBoard children
## skip this entirely — the explicit child wins.
func _auto_instantiate_player_board() -> void:
	if player_board_scene == null:
		return
	# Existing PlayerBoard child wins (WYSIWYG path).
	var existing := find_children("*", "PlayerBoard", true, false)
	if not existing.is_empty():
		if player_board == null:
			player_board = existing[0]
		return
	var pb: Node = player_board_scene.instantiate()
	# Set fields BEFORE add_child so the child's _ready (which runs the
	# moment it enters the tree) sees the seat-derived values.
	if "auto_bind" in pb:
		pb.auto_bind = true
	if "player_id" in pb:
		pb.player_id = get_player_id()
	if "is_mirrored" in pb:
		pb.is_mirrored = (role == Role.OPPONENT)
	# Position the runtime-instantiated board to fill the seat. Designer
	# can override by manually placing a PlayerBoard child instead.
	if pb is Control:
		var c := pb as Control
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pb)
	player_board = pb


## Resolve this seat's role to a concrete player_id at the current
## NetworkManager state. Modules call this in `_try_bind()` to set their
## initial `player_id`, then re-call from `role_changed` to update.
func get_player_id() -> int:
	var local: int = NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0
	match role:
		Role.LOCAL: return local
		Role.OPPONENT: return 1 - local
		Role.PLAYER_0: return 0
		Role.PLAYER_1: return 1
	return 0


## Programmatic setter (equivalent to assigning `role = ...` but more
## explicit at call sites that swap sides). Triggers the role_changed
## signal so modules re-resolve.
func set_role(new_role: Role) -> void:
	role = new_role


## Convenience for spectator UIs: swap PLAYER_0 ↔ PLAYER_1, or LOCAL ↔
## OPPONENT. No-op for already-symmetric configurations.
func swap() -> void:
	match role:
		Role.LOCAL: role = Role.OPPONENT
		Role.OPPONENT: role = Role.LOCAL
		Role.PLAYER_0: role = Role.PLAYER_1
		Role.PLAYER_1: role = Role.PLAYER_0
