class_name NetContext
extends RefCounted

## Thin indirection over the NetworkManager autoload for session-layer code
## (MultiplayerSync, EffectUIRouter). The default instance delegates to the
## singleton; a dedicated-server room calls for_room() to get a context that
## answers from the room's own seat map (is_host() = true, host_peer_id = 1)
## so many rooms can coexist in one headless process.
##
## Room mode uses injected data instead of a subclass because GDScript cannot
## override property getters in child classes.

var _room_mode: bool = false
## Room mode: live reference to the room's {peer_id: player_id} map. The room
## mutates this same Dictionary as players seat/leave.
var _room_peer_player_map: Dictionary = {}

var peer_player_map: Dictionary:
	get: return _room_peer_player_map if _room_mode else NetworkManager.peer_player_map

var host_peer_id: int:
	get: return 1 if _room_mode else NetworkManager.host_peer_id


static func for_room(room_peer_player_map: Dictionary) -> NetContext:
	var ctx := NetContext.new()
	ctx._room_mode = true
	ctx._room_peer_player_map = room_peer_player_map
	return ctx


func is_host() -> bool:
	return true if _room_mode else NetworkManager.is_host()


func is_multiplayer() -> bool:
	return true if _room_mode else NetworkManager.is_multiplayer()


func is_bot_game() -> bool:
	return false if _room_mode else NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
