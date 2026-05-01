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

@export var role: Role = Role.LOCAL


## Resolve this seat's role to a concrete player_id at the current
## NetworkManager state. Modules typically call this once during their
## `_try_bind()` and cache the result on `self.player_id`.
func get_player_id() -> int:
	var local: int = NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0
	match role:
		Role.LOCAL: return local
		Role.OPPONENT: return 1 - local
		Role.PLAYER_0: return 0
		Role.PLAYER_1: return 1
	return 0
