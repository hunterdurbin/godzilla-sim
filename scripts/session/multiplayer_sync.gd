class_name MultiplayerSync
extends Node

## Owns the multiplayer RPC contract for the game board.
## Lives at a stable NodePath (GameBoard/MultiplayerSync) so RPC dispatch
## works on host and client without depending on the presentation script.
##
## Phase 1: forwarder pattern. Each @rpc method delegates back to the parent
## game board, where state and handler bodies still live. This makes
## MultiplayerSync the registered RPC receiver while leaving behavior unchanged.
## Phase 2 will move state ownership to GameSession.

var _board: Node
var _session: Node


func _ready() -> void:
	_session = get_parent()
	if _session:
		_board = _session.get_parent()


# --- First-player choice ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_waiting() -> void:
	if _board:
		_board._rpc_first_player_waiting()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_requested() -> void:
	if _board:
		_board._rpc_first_player_choice_requested()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_resolved(chosen_id: int) -> void:
	if _board:
		_board._rpc_first_player_choice_resolved(chosen_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cleanup_first_player() -> void:
	if _board:
		_board._rpc_cleanup_first_player()


# --- Concede / rematch ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_concede() -> void:
	if _board:
		_board._rpc_concede()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_requested() -> void:
	if _board:
		_board._rpc_rematch_requested()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_with_deck(payload_json: String) -> void:
	if _board:
		_board._rpc_rematch_with_deck(payload_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_execute_rematch() -> void:
	if _board:
		_board._rpc_execute_rematch()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_declined() -> void:
	if _board:
		_board._rpc_rematch_declined()


# --- Action submission and state sync ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action_type: int, params_json: String) -> void:
	if _board:
		_board._rpc_submit_action(action_type, params_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_state(state_bytes: PackedByteArray) -> void:
	if _board:
		_board._rpc_receive_state(state_bytes)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_resync() -> void:
	if _board:
		_board._rpc_request_resync()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	if _board:
		_board._rpc_receive_action_context(actions_json, playable_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_log(text: String) -> void:
	if _board:
		_board._rpc_receive_log(text)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_chat(sender_player_id: int, text: String) -> void:
	if _board:
		_board._rpc_receive_chat(sender_player_id, text)


# --- Effect overlay request/resolve pairs ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String, allow_skip: bool = true) -> void:
	if _board:
		_board._rpc_deck_search_requested(matching_json, all_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_resolved(selected_json: String) -> void:
	if _board:
		_board._rpc_deck_search_resolved(selected_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_requested(cards_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_deck_arrange_requested(cards_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_resolved(keep_json: String, discard_json: String) -> void:
	if _board:
		_board._rpc_deck_arrange_resolved(keep_json, discard_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_requested(matching_json: String, all_json: String, prompt: String, min_count: int, max_count: int) -> void:
	if _board:
		_board._rpc_card_select_requested(matching_json, all_json, prompt, min_count, max_count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_resolved(selected_json: String) -> void:
	if _board:
		_board._rpc_card_select_resolved(selected_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool) -> void:
	if _board:
		_board._rpc_hand_card_selection_requested(indices_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_resolved(hand_index: int) -> void:
	if _board:
		_board._rpc_hand_card_selection_resolved(hand_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_requested(prompt: String, setting: String) -> void:
	if _board:
		_board._rpc_confirmation_requested(prompt, setting)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_resolved() -> void:
	if _board:
		_board._rpc_confirmation_resolved()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_player_name(pname: String) -> void:
	if _board:
		_board._rpc_send_player_name(pname)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_requested(discard_count: int) -> void:
	if _board:
		_board._rpc_hand_discard_requested(discard_count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_resolved(indices_json: String) -> void:
	if _board:
		_board._rpc_hand_discard_resolved(indices_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_requested(target_player_id: int, zones_json: String, prompt: String, allow_skip: bool) -> void:
	if _board:
		_board._rpc_zone_target_requested(target_player_id, zones_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_resolved(zone_index: int) -> void:
	if _board:
		_board._rpc_zone_target_resolved(zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_requested(target_player_id: int, indices_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_strategy_target_requested(target_player_id, indices_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_resolved(strategy_index: int) -> void:
	if _board:
		_board._rpc_strategy_target_resolved(strategy_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_requested(options_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_choice_requested(options_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_resolved(index: int) -> void:
	if _board:
		_board._rpc_choice_resolved(index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_requested(monsters_json: String, indices_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_monster_rankup_requested(monsters_json, indices_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_resolved(index: int) -> void:
	if _board:
		_board._rpc_monster_rankup_resolved(index)


# --- Effect highlights ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if _board:
		_board._rpc_effect_zone_highlighted(pid, zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if _board:
		_board._rpc_effect_zone_unhighlighted(pid, zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_highlighted(pid: int, card_id: String) -> void:
	if _board:
		_board._rpc_effect_card_highlighted(pid, card_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if _board:
		_board._rpc_effect_card_unhighlighted(pid, card_id)


# --- Game end / replay ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	if _board:
		_board._rpc_receive_game_ended(winner_id, reason_key)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_replay(compressed: PackedByteArray) -> void:
	if _board:
		_board._rpc_receive_replay(compressed)
