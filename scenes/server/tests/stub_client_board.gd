extends Node

## Minimal client-side `_board` surface for headless protocol tests against
## the dedicated server. Pairs with the REAL GameSession + MultiplayerSync
## chain (node must be named "GameBoard" so the server's branch-relative RPC
## paths resolve). UI hooks are no-ops; prompts surface as signals so a test
## driver can answer them.

signal action_context_received(actions: Array, playable: Dictionary)
signal prompt_received(kind: String, args: Array)
signal state_applied
signal match_ended(winner_id: int, reason_key: String)

var is_multiplayer_game: bool = true
var is_bot_game: bool = false
var local_player_id: int = -1
var _first_player_id: int = 0
var _current_sub_phase: int = 0
var _client_playable: Dictionary = {}
var _pending_log_tokens: Array = []
var _pending_sound_events: PackedStringArray = []
var _player_elapsed_ms: Array[int] = [0, 0]
var _game_start_time_ms: int = 0
var _turn_start_time_ms: int = 0


# --- Client receive-path hooks (no UI) ---

func _append_log_entry(_entry) -> void: pass
func _apply_remote_player_names(_names) -> void: pass
func _update_turn_tracker(_pid: int, _phase, _sub: int) -> void: pass
func _sync_boards() -> void: state_applied.emit()
func _update_hand_visibility(_pid: int) -> void: pass
func _apply_client_monster_gradients() -> void: pass


# --- RPC forward targets ---

func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	action_context_received.emit(JSON.parse_string(actions_json), JSON.parse_string(playable_json))


func _rpc_first_player_waiting() -> void:
	prompt_received.emit("first_player_waiting", [])


func _rpc_first_player_choice_requested() -> void:
	prompt_received.emit("first_player_choice", [])


func _rpc_confirmation_requested(prompt: String, setting: String) -> void:
	prompt_received.emit("confirmation", [prompt, setting])


func _rpc_hand_discard_requested(count: int) -> void:
	prompt_received.emit("hand_discard", [count])


func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool) -> void:
	prompt_received.emit("hand_card_selection", [indices_json, prompt, allow_skip])


func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String, allow_skip: bool = true) -> void:
	prompt_received.emit("deck_search", [matching_json, all_json, prompt, allow_skip])


func _rpc_deck_arrange_requested(cards_json: String, prompt: String) -> void:
	prompt_received.emit("deck_arrange", [cards_json, prompt])


func _rpc_card_select_requested(matching_json: String, all_json: String, prompt: String, min_count: int, max_count: int) -> void:
	prompt_received.emit("card_select", [matching_json, all_json, prompt, min_count, max_count])


func _rpc_zone_target_requested(target_pid: int, zones_json: String, prompt: String, allow_skip: bool) -> void:
	prompt_received.emit("zone_target", [target_pid, zones_json, prompt, allow_skip])


func _rpc_strategy_target_requested(target_pid: int, indices_json: String, prompt: String) -> void:
	prompt_received.emit("strategy_target", [target_pid, indices_json, prompt])


func _rpc_choice_requested(options_json: String, prompt: String, card_ids_json: String = "[]") -> void:
	prompt_received.emit("choice", [options_json, prompt, card_ids_json])


func _rpc_monster_rankup_requested(monsters_json: String, indices_json: String, prompt: String) -> void:
	prompt_received.emit("monster_rankup", [monsters_json, indices_json, prompt])


func _rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	match_ended.emit(winner_id, reason_key)


func _rpc_first_player_choice_resolved(_id: int) -> void: pass
func _rpc_cleanup_first_player() -> void: pass
func _rpc_receive_log(_text: String) -> void: pass
func _rpc_receive_chat(_pid: int, _text: String) -> void: pass
func _rpc_receive_replay(_bytes: PackedByteArray) -> void: pass
func _rpc_effect_zone_highlighted(_p: int, _z: int) -> void: pass
func _rpc_effect_zone_unhighlighted(_p: int, _z: int) -> void: pass
func _rpc_effect_card_highlighted(_p: int, _c: String) -> void: pass
func _rpc_effect_card_unhighlighted(_p: int, _c: String) -> void: pass
func _rpc_concede() -> void: pass
func _rpc_rematch_requested() -> void: pass
func _rpc_rematch_with_deck(_p: String) -> void: pass
func _rpc_execute_rematch() -> void: pass
func _rpc_rematch_declined() -> void: pass
func _on_awaiting_action(_valid_actions: Array) -> void: pass
