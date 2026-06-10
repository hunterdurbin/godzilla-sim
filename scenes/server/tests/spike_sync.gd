extends Node

## RPC endpoint for the branch-routing spike. The chain is named
## GameBoard/GameSession/MultiplayerSync to mirror the production contract so
## the path relative to each branch root matches on both ends.

signal got_ping(text: String)


@rpc("any_peer", "call_remote", "reliable")
func ping(text: String) -> void:
	got_ping.emit(text)
