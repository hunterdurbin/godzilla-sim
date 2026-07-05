class_name EffectHighlightController
extends Node
## Effect-driven zone/card highlights and the card-attention pulse.
## Method bodies moved verbatim from game_board.gd (Phase 8 split);
## remaining board state/methods are reached via `_board`. The board
## keeps one-line delegates, so call sites, signal connections, and the
## session-layer `_board.*` contract are unchanged.

var _board: GameBoard

# Tracks the pulsing attention highlight (hovered effect-prompt / stack row).
# Separate from _highlighted_effect_card_node so the two visuals never stomp
# each other's reset.
var _attention_card_node: Control = null
var _attention_discard_pid: int = -1


func _ready() -> void:
	_board = get_parent() as GameBoard


func _on_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if _board.is_multiplayer_game and pid != _board.local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_highlighted", 8)
				_board._sync._rpc_effect_zone_highlighted.rpc_id(peer_id, pid, zone_index)
		return
	_board._apply_zone_highlight(pid, zone_index, true)


func _on_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if _board.is_multiplayer_game and pid != _board.local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_unhighlighted", 8)
				_board._sync._rpc_effect_zone_unhighlighted.rpc_id(peer_id, pid, zone_index)
		return
	_board._apply_zone_highlight(pid, zone_index, false)


func _apply_zone_highlight(pid: int, zone_index: int, highlighted: bool) -> void:
	var board: Control = _board.player1_board if pid == 0 else _board.player2_board
	if zone_index >= 0 and zone_index < board.zone_slots.size():
		var slot: Slot = board.zone_slots[zone_index]
		if slot and slot.held_card:
			slot.held_card.modulate = Color(1.2, 1.2, 0.6, 1.0) if highlighted else Color.WHITE


# --- Effect source card highlighting ---


func _on_effect_card_highlighted(pid: int, card_id: String) -> void:
	if _board.is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_highlighted", 4 + card_id.length())
				_board._sync._rpc_effect_card_highlighted.rpc_id(peer_id, pid, card_id)
	_board._apply_card_highlight(pid, card_id, true)


func _on_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if _board.is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_unhighlighted", 4 + card_id.length())
				_board._sync._rpc_effect_card_unhighlighted.rpc_id(peer_id, pid, card_id)
	_board._apply_card_highlight(pid, card_id, false)


func _apply_card_highlight(pid: int, card_id: String, highlighted: bool) -> void:
	if not highlighted:
		# Reset by node reference rather than card_id — the held_card's card_data
		# may have changed since highlight (e.g. evolution mutates the held node
		# in place), so an id-based lookup can miss the original target.
		if _board._highlighted_effect_card_node and is_instance_valid(_board._highlighted_effect_card_node):
			_board._highlighted_effect_card_node.modulate = Color.WHITE
		_board._highlighted_effect_card_node = null
		return
	var board: Control = _board.player1_board if pid == 0 else _board.player2_board
	var color := Color(1.2, 1.2, 0.6, 1.0)
	# Check zone slots (battle cards)
	for slot in board.zone_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			_board._highlighted_effect_card_node = slot.held_card
			return
	# Check strategy slots
	for slot in board.strategy_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			_board._highlighted_effect_card_node = slot.held_card
			return


# --- Prompt-driven chrome: tracker collapse + log dim ---

## Collapse the turn tracker to its one-line chip while the choice prompt or
## the effect-stack panel occupies the right edge.


func set_card_attention(loc: Dictionary, on: bool) -> void:
	## Pulse the attention border on the board card described by `loc`
	## (StandbyResolver.card_location_ref shape). Turning it off with a
	## non-empty loc only clears when that loc still matches the tracked
	## target, so a stale mouse_exited from one row can't kill the highlight
	## a newer row just turned on.
	if not on:
		if not loc.is_empty():
			if str(loc.get("kind", "")) == "discard":
				if _attention_discard_pid >= 0 and _attention_discard_pid != int(loc.get("player_id", -1)):
					return
			elif _attention_card_node and is_instance_valid(_attention_card_node):
				var node := _board._resolve_attention_card(loc)
				if node != null and node != _attention_card_node:
					return
		_board._clear_card_attention()
		return

	_board._clear_card_attention()
	if loc.is_empty():
		return
	var pid: int = int(loc.get("player_id", -1))
	if pid < 0 or pid > 1:
		return
	if str(loc.get("kind", "")) == "discard":
		var board: Control = _board.player1_board if pid == 0 else _board.player2_board
		board.highlight_discard_zone(true)
		_attention_discard_pid = pid
		return
	var target := _board._resolve_attention_card(loc)
	if target and target.has_method("set_attention_highlight"):
		# Ownership color language: cyan for the viewer's own effects, purple
		# for the opponent's (matches the stack panel's purple rows).
		var border := Color(0.7, 0.4, 1.0) if pid != _board.local_player_id else Color(0.25, 0.85, 1.0)
		target.set_attention_highlight(true, border)
		_attention_card_node = target


func _clear_card_attention() -> void:
	if _attention_card_node and is_instance_valid(_attention_card_node):
		_attention_card_node.set_attention_highlight(false)
	_attention_card_node = null
	if _attention_discard_pid >= 0:
		var board: Control = _board.player1_board if _attention_discard_pid == 0 else _board.player2_board
		board.highlight_discard_zone(false)
		_attention_discard_pid = -1


func _resolve_attention_card(loc: Dictionary) -> Control:
	## Resolve a card_location_ref to its on-board Card node, verifying the
	## per-copy instance id and falling back to an id scan when the recorded
	## index went stale (the card moved since the ref was built).
	var pid: int = int(loc.get("player_id", -1))
	if pid < 0 or pid > 1:
		return null
	var board: Control = _board.player1_board if pid == 0 else _board.player2_board
	var index: int = int(loc.get("index", -1))
	var instance_id: String = str(loc.get("instance_id", ""))
	match str(loc.get("kind", "")):
		"monster":
			return board.monster_card
		"zone":
			if index >= 0 and index < board.zone_slots.size():
				var slot: Slot = board.zone_slots[index]
				if slot and slot.held_card and (instance_id.is_empty() or slot.held_card.card_data.get("id", "") == instance_id):
					return slot.held_card
		"strategy":
			if index >= 0 and index < board.strategy_slots.size():
				var strat_slot: Slot = board.strategy_slots[index]
				if strat_slot and strat_slot.held_card and (instance_id.is_empty() or strat_slot.held_card.card_data.get("id", "") == instance_id):
					return strat_slot.held_card
	if instance_id.is_empty():
		return null
	for slot in board.zone_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == instance_id:
			return slot.held_card
	for slot in board.strategy_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == instance_id:
			return slot.held_card
	return null


# --- Discard view UI ---
