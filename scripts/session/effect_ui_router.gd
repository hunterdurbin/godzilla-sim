class_name EffectUIRouter
extends Node

## Owns the dispatch of effect-driven prompts (deck search, card select, etc.)
## from EffectHandler/ActionHandler signals to whatever UI the scene registers.
##
## Workflow:
##   1. The scene registers a handler per prompt key BEFORE the session
##      starts: effect_router.register_handler("deck_search", overlay.show_prompt)
##   2. The router self-binds on GameSession.session_started — but only for
##      keys that have a registered handler, so prompts that still have
##      legacy handlers on game_board.gd are untouched during extraction.
##   3. For local-player prompts the handler is called with the request args
##      plus a resolve callback as the LAST arg. The resolve callback handles
##      the host-vs-client RPC routing internally.
##   4. Bot prompts are skipped (the bot answers via its own listeners);
##      remote-player prompts are RPC'd to the right peer via MultiplayerSync.
##
## Handler signatures (resolve callback always last):
##   "deck_search":      (matching, all_cards, prompt, allow_skip, resolve_cb)
##                        resolve_cb takes Dictionary (selected card, {} = skip)
##   "deck_arrange":     (cards, prompt, resolve_cb)
##                        resolve_cb takes (Array keep, Array discard)
##   "card_select":      (matching, all_cards, prompt, min, max, resolve_cb)
##                        resolve_cb takes Array (selected cards, [] = skip)
##   "choice":           (options, prompt, resolve_cb)
##                        resolve_cb takes int (chosen index)
##   "cards_revealed":   (cards, title, resolve_cb)
##                        resolve_cb takes nothing — call on dismiss
##   "monster_rankup":   (monsters, valid_indices, prompt, resolve_cb)
##                        resolve_cb takes int (chosen index)
##   "hand_discard":     (player_id, count, resolve_cb)
##                        resolve_cb takes (player_id, Array[int] indices)
##   "hand_card_select": (player_id, valid_indices, prompt, allow_skip, resolve_cb)
##                        resolve_cb takes int (hand index, -1 = skip)
##   "zone_target":      (target_player_id, valid_zones, prompt, allow_skip, resolve_cb)
##                        resolve_cb takes int (zone index, -1 = skip)
##   "strategy_target":  (target_player_id, valid_indices, prompt, resolve_cb)
##                        resolve_cb takes int (strategy index)

const _OVERLAY_KEYS := [
	"deck_search", "deck_arrange", "card_select", "choice", "cards_revealed",
	"monster_rankup", "hand_discard", "hand_card_select", "zone_target",
	"strategy_target",
]

var session: GameSession
var multiplayer_sync: MultiplayerSync

## Set by the scene to its card-zoom display function. Overlays use this for
## right-click / long-press / double-click zoom.
## Signature: (card_data: Dictionary, play_cost_modifier: int) -> void
var card_zoom_request: Callable = Callable()

## Pre-RPC hook — flush the buffered state broadcast so the remote peer has
## fresh state before the prompt shows.
var on_pre_remote_dispatch: Callable = Callable()

## Records the in-flight prompt for reconnect/resync replay.
## Signature: (method: String, args: Array) -> void
var on_pending_interaction: Callable = Callable()

## Optional translator for prompt text (defaults to TranslationServer).
var translate_prompt: Callable = Callable()

## View-board hook: the overlay calls this with itself so the scene can stash
## it, hide it, and re-show it later. Signature: (overlay: Control) -> void
var on_view_board_request: Callable = Callable()

## In-game "stacked" gallery preference, shared by all card-grid overlays
## (initialized from GameSettings by the scene, remembered for the match).
var match_stacked_view: bool = true

var local_player_id: int = 0
var is_multiplayer: bool = false
var is_bot_game: bool = false

var _handlers: Dictionary = {}
var _board: Node


func _ready() -> void:
	var session_node := get_parent()
	if session_node is GameSession:
		session = session_node
		_board = session_node.get_parent()
		session.session_started.connect(_bind)
	else:
		push_error("[EffectUIRouter] Must be a child of GameSession.")
	multiplayer_sync = get_node_or_null("../MultiplayerSync")


## Register a Callable that knows how to display a given prompt locally.
## Must be called before the session starts (or before the next rematch).
func register_handler(key: String, handler: Callable) -> void:
	if not _OVERLAY_KEYS.has(key):
		push_warning("[EffectUIRouter] Unknown handler key: %s" % key)
	_handlers[key] = handler


## Connect request signals for every registered key. Idempotent; runs on
## session_started (initial start and every rematch). Keys without a
## registered handler stay unconnected so legacy game_board handlers keep
## receiving them during the incremental extraction.
func _bind() -> void:
	local_player_id = _board.local_player_id
	is_multiplayer = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	if not session.is_running():
		return # Client peer: prompts arrive via MultiplayerSync RPCs

	var eh: EffectHandler = session.effect_handler
	var ah: ActionHandler = session.action_handler
	var signal_map := {
		"deck_search": [eh.deck_search_requested, _on_deck_search_requested],
		"deck_arrange": [eh.deck_arrange_requested, _on_deck_arrange_requested],
		"card_select": [eh.card_select_requested, _on_card_select_requested],
		"choice": [eh.choice_requested, _on_choice_requested],
		"cards_revealed": [eh.cards_revealed_requested, _on_cards_revealed_requested],
		"monster_rankup": [ah.monster_rankup_requested, _on_monster_rankup_requested],
		"hand_discard": [eh.hand_discard_requested, _on_hand_discard_requested],
		"hand_card_select": [eh.hand_card_selection_requested, _on_hand_card_selection_requested],
		"zone_target": [eh.zone_target_requested, _on_zone_target_requested],
		"strategy_target": [eh.strategy_target_requested, _on_strategy_target_requested],
	}
	for key in _handlers:
		if not signal_map.has(key):
			continue
		var sig: Signal = signal_map[key][0]
		var cb: Callable = signal_map[key][1]
		if not sig.is_connected(cb):
			sig.connect(cb)


# --- Routing helpers ---

func _bot_player_id() -> int:
	# Read live — the bot is constructed after session_started fires.
	return session.bot_player.bot_player_id if session.bot_player else -1


func _is_bot_target(player_id: int) -> bool:
	return is_bot_game and player_id == _bot_player_id()


func _send_to_remote(player_id: int, method: String, args: Array, dispatcher: Callable) -> void:
	if on_pending_interaction.is_valid():
		on_pending_interaction.call(method, args)
	for peer_id in NetworkManager.peer_player_map:
		if NetworkManager.peer_player_map[peer_id] == player_id:
			if on_pre_remote_dispatch.is_valid():
				on_pre_remote_dispatch.call()
			dispatcher.call(peer_id)
			return


func _translate(raw: String) -> String:
	if translate_prompt.is_valid():
		return translate_prompt.call(raw)
	return TranslationServer.translate(raw)


# --- Per-prompt dispatchers (host side) ---

func _on_deck_search_requested(player_id: int, matching: Array, all_cards: Array, prompt: String, allow_skip: bool = true) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var matching_json := JSON.stringify(StateCodec.cards_to_ids(matching))
		var all_json := JSON.stringify(StateCodec.cards_to_ids(all_cards))
		_send_to_remote(player_id, "deck_search", [matching_json, all_json, prompt, allow_skip], func(peer):
			RpcLogger.log_send("deck_search_requested", matching_json.length() + all_json.length() + prompt.length())
			multiplayer_sync._rpc_deck_search_requested.rpc_id(peer, matching_json, all_json, prompt, allow_skip))
		return
	show_deck_search(matching, all_cards, prompt, allow_skip)


func _on_deck_arrange_requested(player_id: int, cards: Array, prompt: String) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var cards_json := JSON.stringify(StateCodec.cards_to_ids(cards))
		_send_to_remote(player_id, "deck_arrange", [cards_json, prompt], func(peer):
			RpcLogger.log_send("deck_arrange_requested", cards_json.length() + prompt.length())
			multiplayer_sync._rpc_deck_arrange_requested.rpc_id(peer, cards_json, prompt))
		return
	show_deck_arrange(cards, prompt)


func _on_card_select_requested(player_id: int, matching: Array, all_cards: Array, prompt: String, min_count: int, max_count: int) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var matching_json := JSON.stringify(StateCodec.cards_to_ids(matching))
		var all_json := JSON.stringify(StateCodec.cards_to_ids(all_cards))
		_send_to_remote(player_id, "card_select", [matching_json, all_json, prompt, min_count, max_count], func(peer):
			RpcLogger.log_send("card_select_requested", matching_json.length() + all_json.length() + prompt.length())
			multiplayer_sync._rpc_card_select_requested.rpc_id(peer, matching_json, all_json, prompt, min_count, max_count))
		return
	show_card_select(matching, all_cards, prompt, min_count, max_count)


func _on_choice_requested(player_id: int, options: Array, prompt: String) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var options_json := JSON.stringify(options)
		_send_to_remote(player_id, "choice", [options_json, prompt], func(peer):
			RpcLogger.log_send("choice_requested", options_json.length() + prompt.length())
			multiplayer_sync._rpc_choice_requested.rpc_id(peer, options_json, prompt))
		return
	show_choice(options, prompt)


func _on_cards_revealed_requested(player_id: int, cards: Array, title: String) -> void:
	if _is_bot_target(player_id):
		# Bot handles via its own listener; auto-resolve so the engine continues.
		session.effect_handler.resolve_cards_revealed()
		return
	# Cards revealed always shows on local — no remote routing.
	show_cards_revealed(cards, title)


func _on_monster_rankup_requested(player_id: int, monsters: Array, valid_indices: Array, prompt: String) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var monsters_json := JSON.stringify(StateCodec.cards_to_ids(monsters))
		var indices_json := JSON.stringify(valid_indices)
		_send_to_remote(player_id, "monster_rankup", [monsters_json, indices_json, prompt], func(peer):
			RpcLogger.log_send("monster_rankup_requested", monsters_json.length() + indices_json.length() + prompt.length())
			multiplayer_sync._rpc_monster_rankup_requested.rpc_id(peer, monsters_json, indices_json, prompt))
		return
	show_monster_rankup(monsters, valid_indices, prompt)


func _on_hand_discard_requested(player_id: int, count: int) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		_send_to_remote(player_id, "hand_discard", [count], func(peer):
			RpcLogger.log_send("hand_discard_requested", 4)
			multiplayer_sync._rpc_hand_discard_requested.rpc_id(peer, count))
		return
	show_hand_discard(player_id, count)


func _on_hand_card_selection_requested(player_id: int, valid_indices: Array, prompt: String, allow_skip: bool) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var indices_json := JSON.stringify(valid_indices)
		_send_to_remote(player_id, "hand_card_selection", [indices_json, prompt, allow_skip], func(peer):
			RpcLogger.log_send("hand_card_selection_requested", indices_json.length() + prompt.length() + 1)
			multiplayer_sync._rpc_hand_card_selection_requested.rpc_id(peer, indices_json, prompt, allow_skip))
		return
	show_hand_card_selection(player_id, valid_indices, prompt, allow_skip)


func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array, prompt: String, allow_skip: bool) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var zones_json := JSON.stringify(valid_zones)
		_send_to_remote(player_id, "zone_target", [target_player_id, zones_json, prompt, allow_skip], func(peer):
			RpcLogger.log_send("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
			multiplayer_sync._rpc_zone_target_requested.rpc_id(peer, target_player_id, zones_json, prompt, allow_skip))
		return
	show_zone_target(target_player_id, valid_zones, prompt, allow_skip)


func _on_strategy_target_requested(player_id: int, target_player_id: int, valid_indices: Array, prompt: String) -> void:
	if _is_bot_target(player_id):
		return
	if is_multiplayer and player_id != local_player_id:
		var indices_json := JSON.stringify(valid_indices)
		_send_to_remote(player_id, "strategy_target", [target_player_id, indices_json, prompt], func(peer):
			RpcLogger.log_send("strategy_target_requested", 4 + indices_json.length() + prompt.length())
			multiplayer_sync._rpc_strategy_target_requested.rpc_id(peer, target_player_id, indices_json, prompt))
		return
	show_strategy_target(target_player_id, valid_indices, prompt)


# --- Local-display entry points (also called by the client RPC path) ---

func _show(key: String, args: Array) -> void:
	var handler: Callable = _handlers.get(key, Callable())
	if handler.is_valid():
		handler.callv(args)
	else:
		push_warning("[EffectUIRouter] No handler registered for '%s'" % key)


func show_deck_search(matching: Array, all_cards: Array, prompt: String, allow_skip: bool) -> void:
	_show("deck_search", [matching, all_cards, _translate(prompt), allow_skip, resolve_deck_search])


func show_deck_arrange(cards: Array, prompt: String) -> void:
	_show("deck_arrange", [cards, _translate(prompt), resolve_deck_arrange])


func show_card_select(matching: Array, all_cards: Array, prompt: String, min_count: int, max_count: int) -> void:
	_show("card_select", [matching, all_cards, _translate(prompt), min_count, max_count, resolve_card_select])


func show_choice(options: Array, prompt: String) -> void:
	var translated: Array[String] = []
	for opt in options:
		translated.append(_translate(str(opt)))
	_show("choice", [translated, _translate(prompt), resolve_choice])


func show_cards_revealed(cards: Array, title: String) -> void:
	var handler: Callable = _handlers.get("cards_revealed", Callable())
	if handler.is_valid():
		handler.call(cards, _translate(title), resolve_cards_revealed)
	else:
		resolve_cards_revealed() # Don't stall the engine


func show_monster_rankup(monsters: Array, valid_indices: Array, prompt: String) -> void:
	var typed: Array[int] = []
	for v in valid_indices:
		typed.append(int(v))
	_show("monster_rankup", [monsters, typed, _translate(prompt), resolve_monster_rankup])


func show_hand_discard(player_id: int, count: int) -> void:
	_show("hand_discard", [player_id, count, resolve_hand_discard])


func show_hand_card_selection(player_id: int, valid_indices: Array, prompt: String, allow_skip: bool) -> void:
	var typed: Array[int] = []
	for v in valid_indices:
		typed.append(int(v))
	_show("hand_card_select", [player_id, typed, _translate(prompt), allow_skip, resolve_hand_card_selection])


func show_zone_target(target_player_id: int, valid_zones: Array, prompt: String, allow_skip: bool) -> void:
	var typed: Array[int] = []
	for v in valid_zones:
		typed.append(int(v))
	_show("zone_target", [target_player_id, typed, _translate(prompt), allow_skip, resolve_zone_target])


func show_strategy_target(target_player_id: int, valid_indices: Array, prompt: String) -> void:
	var typed: Array[int] = []
	for v in valid_indices:
		typed.append(int(v))
	_show("strategy_target", [target_player_id, typed, _translate(prompt), resolve_strategy_target])


# --- Resolve callbacks: one place for the host-vs-client RPC dance ---

func resolve_deck_search(selected: Dictionary) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var json := JSON.stringify(selected)
		RpcLogger.log_send("deck_search_resolved", json.length())
		multiplayer_sync._rpc_deck_search_resolved.rpc_id(NetworkManager.host_peer_id, json)
	elif session.effect_handler:
		session.effect_handler.resolve_deck_search(selected)


func resolve_deck_arrange(keep: Array, discard: Array) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var keep_json := JSON.stringify(keep)
		var discard_json := JSON.stringify(discard)
		RpcLogger.log_send("deck_arrange_resolved", keep_json.length() + discard_json.length())
		multiplayer_sync._rpc_deck_arrange_resolved.rpc_id(NetworkManager.host_peer_id, keep_json, discard_json)
	elif session.effect_handler:
		var keep_typed: Array[Dictionary] = []
		for c in keep:
			keep_typed.append(c)
		var discard_typed: Array[Dictionary] = []
		for c in discard:
			discard_typed.append(c)
		session.effect_handler.resolve_deck_arrange(keep_typed, discard_typed)


func resolve_card_select(selected: Array) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var json := JSON.stringify(StateCodec.cards_to_ids(selected))
		RpcLogger.log_send("card_select_resolved", json.length())
		multiplayer_sync._rpc_card_select_resolved.rpc_id(NetworkManager.host_peer_id, json)
	elif session.effect_handler:
		var typed: Array[Dictionary] = []
		for c in selected:
			typed.append(c)
		session.effect_handler.resolve_card_select(typed)


func resolve_choice(index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("choice_resolved", 4)
		multiplayer_sync._rpc_choice_resolved.rpc_id(NetworkManager.host_peer_id, index)
	elif session.effect_handler:
		session.effect_handler.resolve_choice(index)


func resolve_cards_revealed() -> void:
	if session.effect_handler:
		session.effect_handler.resolve_cards_revealed()


func resolve_monster_rankup(index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("monster_rankup_resolved", 4)
		multiplayer_sync._rpc_monster_rankup_resolved.rpc_id(NetworkManager.host_peer_id, index)
	elif session.action_handler:
		session.action_handler.resolve_monster_rankup(index)


func resolve_hand_discard(player_id: int, indices) -> void:
	# `indices` may arrive as Array or typed Array[int] — coerce.
	var typed: Array[int] = []
	for v in indices:
		typed.append(int(v))
	if is_multiplayer and not NetworkManager.is_host():
		var indices_json := JSON.stringify(typed)
		RpcLogger.log_send("hand_discard_resolved", indices_json.length())
		multiplayer_sync._rpc_hand_discard_resolved.rpc_id(NetworkManager.host_peer_id, indices_json)
	elif session.effect_handler:
		session.effect_handler.resolve_hand_discard(player_id, typed)


func resolve_hand_card_selection(hand_index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("hand_card_selection_resolved", 4)
		multiplayer_sync._rpc_hand_card_selection_resolved.rpc_id(NetworkManager.host_peer_id, hand_index)
	elif session.effect_handler:
		session.effect_handler.resolve_hand_card_selection(hand_index)


func resolve_zone_target(zone_index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("zone_target_resolved", 4)
		multiplayer_sync._rpc_zone_target_resolved.rpc_id(NetworkManager.host_peer_id, zone_index)
	elif session.effect_handler:
		session.effect_handler.resolve_zone_target(zone_index)


func resolve_strategy_target(strategy_index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("strategy_target_resolved", 4)
		multiplayer_sync._rpc_strategy_target_resolved.rpc_id(NetworkManager.host_peer_id, strategy_index)
	elif session.effect_handler:
		session.effect_handler.resolve_strategy_target(strategy_index)
