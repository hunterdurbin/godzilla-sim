class_name EffectUIRouter
extends Node

## Owns the dispatch of effect-driven prompts (deck search, card select, etc.)
## from EffectHandler signals to whatever UI the host scene wants to show.
##
## Designer workflow for a new GameBoard scene:
##   1. Add `GameSession`, `GameSession/MultiplayerSync`,
##      `GameSession/EffectUIRouter` as named children.
##   2. Place overlay scene instances in your scene tree (or instantiate them
##      at runtime).
##   3. In `_ready()`, after `session.start_host_session(...)`, register a
##      handler per prompt key:
##        effect_router.register_handler("deck_search", _my_show_deck_search)
##   4. Set `effect_router.card_zoom_request` to your card-zoom display
##      callable, so overlays know how to ask for a card zoom.
##   5. Call `effect_router.bind(session, multiplayer_sync, local_player_id)`.
##
## The router intercepts the EffectHandler / ActionHandler request signals,
## filters out bot-turn and remote-player cases (RPC'ing them to the right
## peer via multiplayer_sync), and for local-player prompts calls your
## registered handler with the request args plus a resolve callback. The
## resolve callback handles the host-vs-client RPC routing internally — the
## designer never deals with that.
##
## Handler signatures (the resolve callback is always the LAST arg):
##   "deck_search":      (matching, all_cards, prompt, allow_skip, resolve_cb)
##                        resolve_cb takes Dictionary (selected card, or {} for skip)
##   "deck_arrange":     (cards, prompt, resolve_cb)
##                        resolve_cb takes (Array keep, Array discard)
##   "card_select":      (matching, all_cards, prompt, min, max, pool_filter, resolve_cb)
##                        resolve_cb takes Array (selected cards, or [] for skip)
##   "choice":           (options, prompt, resolve_cb)
##                        resolve_cb takes int (chosen index)
##   "cards_revealed":   (cards, title, resolve_cb)
##                        resolve_cb takes nothing — call it when user dismisses
##   "monster_rankup":   (monsters, valid_indices, prompt, resolve_cb)
##                        resolve_cb takes int (chosen index)

const _OVERLAY_KEYS := [
	"deck_search",
	"deck_arrange",
	"card_select",
	"choice",
	"cards_revealed",
	"monster_rankup",
	# Inline interactions follow the same routing pattern but the host
	# scene's handler shows board-side selection UI rather than an overlay.
	"hand_discard",
	"hand_card_select",
	"zone_target",
	"strategy_target",
	"confirmation",
]

var session: GameSession
var multiplayer_sync: MultiplayerSync

## Set by the host scene to its card-zoom display function. Overlays use
## this when the player right-clicks / long-presses / double-clicks a card.
## Signature: (card_data: Dictionary, play_cost_modifier: int) -> void
var card_zoom_request: Callable = Callable()

## Optional pre-RPC hook (e.g. flush a buffered state broadcast so the
## remote peer has fresh state before showing the prompt).
var on_pre_remote_dispatch: Callable = Callable()

## Optional setter the host scene uses to record the in-flight prompt for
## reconnect/resync. Signature: (method: String, args: Array) -> void
var on_pending_interaction: Callable = Callable()

## Optional translator for prompt text. Defaults to TranslationServer.translate
## if not set. Signature: (raw: String) -> String
var translate_prompt: Callable = Callable()

## Optional view-board hook. When the user clicks "View Board" on an overlay,
## the overlay calls this with itself so the host scene can stash a reference
## (and show its "Show Cards" button) — the host re-shows the overlay later
## via `overlay.reshow()`. Signature: (overlay: Control) -> void
var on_view_board_request: Callable = Callable()

# --- Local context, set by bind() ---
var local_player_id: int = 0
var is_multiplayer: bool = false
var is_bot_game: bool = false
var bot_player_id: int = -1

# --- Persistent prefs ---
var match_stacked_view: bool = true

# --- Registered show-handlers ---
var _handlers: Dictionary = {}

# --- Backwards-compat: instances registered via register_overlay() ---
var _registered_overlays: Dictionary = {}

var _board: Node
var _session_node: Node


func _ready() -> void:
	_session_node = get_parent()
	if _session_node:
		_board = _session_node.get_parent()


## Connect to session.effect_handler / session.action_handler signals.
## Idempotent — safe to call again after a rematch's start_host_session().
func bind(p_session: GameSession, p_multiplayer_sync: MultiplayerSync, p_local_player_id: int) -> void:
	session = p_session
	multiplayer_sync = p_multiplayer_sync
	local_player_id = p_local_player_id
	is_multiplayer = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	bot_player_id = -1
	if session.bot_player:
		bot_player_id = session.bot_player.bot_player_id

	if not session.is_running():
		return

	var eh := session.effect_handler
	if eh:
		_connect_once(eh.deck_search_requested, _on_deck_search_requested)
		_connect_once(eh.deck_arrange_requested, _on_deck_arrange_requested)
		_connect_once(eh.card_select_requested, _on_card_select_requested)
		_connect_once(eh.choice_requested, _on_choice_requested)
		_connect_once(eh.cards_revealed_requested, _on_cards_revealed_requested)
		_connect_once(eh.zone_target_requested, _on_zone_target_requested)
	var ah := session.action_handler
	if ah:
		_connect_once(ah.monster_rankup_requested, _on_monster_rankup_requested)


func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


## Register a Callable that knows how to display a given prompt locally.
## See class docstring for handler signatures.
func register_handler(key: String, handler: Callable) -> void:
	if not _OVERLAY_KEYS.has(key):
		push_warning("[EffectUIRouter] Unknown handler key: %s" % key)
	_handlers[key] = handler


## Backwards-compat with the old register_overlay(key, scene). Prefer
## register_handler() going forward.
func register_overlay(key: String, scene_or_node) -> void:
	_registered_overlays[key] = scene_or_node


func has_overlay(key: String) -> bool:
	return _registered_overlays.has(key) or _handlers.has(key)


func get_overlay_scene(key: String) -> PackedScene:
	var v = _registered_overlays.get(key, null)
	return v if v is PackedScene else null


# --- Routing helpers ---

func _is_local_target(player_id: int) -> bool:
	# Bot drives its own response — don't show UI.
	if is_bot_game and player_id == bot_player_id:
		return false
	# Other peer — they handle locally on their side.
	if is_multiplayer and player_id != local_player_id:
		return false
	return true


func _send_to_remote(player_id: int, dispatcher: Callable) -> void:
	for peer_id in NetworkManager.peer_player_map:
		if NetworkManager.peer_player_map[peer_id] == player_id:
			if on_pre_remote_dispatch.is_valid():
				on_pre_remote_dispatch.call()
			dispatcher.call(peer_id)
			return


func _set_pending(method: String, args: Array) -> void:
	if on_pending_interaction.is_valid():
		on_pending_interaction.call(method, args)


func _translate(raw: String) -> String:
	if translate_prompt.is_valid():
		return translate_prompt.call(raw)
	return TranslationServer.translate(raw)


func _cards_to_ids(cards: Array) -> Array[String]:
	var ids: Array[String] = []
	for card in cards:
		ids.append(card.get("id", ""))
	return ids


# --- Per-prompt dispatchers ---

func _on_deck_search_requested(player_id: int, matching: Array, all_cards: Array, prompt: String, allow_skip: bool = true) -> void:
	if is_bot_game and player_id == bot_player_id:
		return
	if is_multiplayer and player_id != local_player_id:
		var matching_json := JSON.stringify(_cards_to_ids(matching))
		var all_json := JSON.stringify(_cards_to_ids(all_cards))
		_set_pending("deck_search", [matching_json, all_json, prompt, allow_skip])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("deck_search_requested", matching_json.length() + all_json.length() + prompt.length())
			multiplayer_sync._rpc_deck_search_requested.rpc_id(peer, matching_json, all_json, prompt, allow_skip))
		return
	show_deck_search(matching, all_cards, prompt, allow_skip)


func _on_deck_arrange_requested(player_id: int, cards: Array, prompt: String) -> void:
	if is_bot_game and player_id == bot_player_id:
		return
	if is_multiplayer and player_id != local_player_id:
		var cards_json := JSON.stringify(_cards_to_ids(cards))
		_set_pending("deck_arrange", [cards_json, prompt])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("deck_arrange_requested", cards_json.length() + prompt.length())
			multiplayer_sync._rpc_deck_arrange_requested.rpc_id(peer, cards_json, prompt))
		return
	show_deck_arrange(cards, prompt)


func _on_card_select_requested(player_id: int, matching: Array, all_cards: Array, prompt: String, min_count: int, max_count: int) -> void:
	if is_bot_game and player_id == bot_player_id:
		return
	if is_multiplayer and player_id != local_player_id:
		var matching_json := JSON.stringify(_cards_to_ids(matching))
		var all_json := JSON.stringify(_cards_to_ids(all_cards))
		_set_pending("card_select", [matching_json, all_json, prompt, min_count, max_count])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("card_select_requested", matching_json.length() + all_json.length() + prompt.length())
			multiplayer_sync._rpc_card_select_requested.rpc_id(peer, matching_json, all_json, prompt, min_count, max_count))
		return
	show_card_select(matching, all_cards, prompt, min_count, max_count)


func _on_choice_requested(player_id: int, options: Array, prompt: String) -> void:
	print("[EffectUIRouter] _on_choice_requested player=%d options=%d prompt=%s" % [player_id, options.size(), prompt])
	if is_bot_game and player_id == bot_player_id:
		print("[EffectUIRouter] Skipping — bot's choice (player_id == bot_player_id %d)" % bot_player_id)
		return
	if is_multiplayer and player_id != local_player_id:
		var options_json := JSON.stringify(options)
		_set_pending("choice", [options_json, prompt])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("choice_requested", options_json.length() + prompt.length())
			multiplayer_sync._rpc_choice_requested.rpc_id(peer, options_json, prompt))
		return
	show_choice(options, prompt)


func _on_monster_rankup_requested(player_id: int, monsters: Array, valid_indices: Array, prompt: String) -> void:
	if is_bot_game and player_id == bot_player_id:
		return
	if is_multiplayer and player_id != local_player_id:
		var monsters_json := JSON.stringify(_cards_to_ids(monsters))
		var indices_json := JSON.stringify(valid_indices)
		_set_pending("monster_rankup", [monsters_json, indices_json, prompt])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("monster_rankup_requested", monsters_json.length() + indices_json.length() + prompt.length())
			multiplayer_sync._rpc_monster_rankup_requested.rpc_id(peer, monsters_json, indices_json, prompt))
		return
	SfxManager.play("action_required")
	var typed_indices: Array[int] = []
	for v in valid_indices:
		typed_indices.append(int(v))
	show_monster_rankup(monsters, typed_indices, prompt)


func _on_cards_revealed_requested(player_id: int, cards: Array, title: String) -> void:
	if is_bot_game and player_id == bot_player_id:
		# Bot handles via its own listener; auto-resolve so the engine continues.
		session.effect_handler.resolve_cards_revealed()
		return
	# Cards revealed always shows on local — no remote routing.
	show_cards_revealed(cards, title)


func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array, prompt: String, allow_skip: bool) -> void:
	if is_bot_game and player_id == bot_player_id:
		return  # Bot handles via its own listener
	if is_multiplayer and player_id != local_player_id:
		var zones_json := JSON.stringify(valid_zones)
		_set_pending("zone_target", [target_player_id, zones_json, prompt, allow_skip])
		_send_to_remote(player_id, func(peer):
			RpcLogger.log_send("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
			multiplayer_sync._rpc_zone_target_requested.rpc_id(peer, target_player_id, zones_json, prompt, allow_skip))
		return
	var typed_zones: Array[int] = []
	for v in valid_zones:
		typed_zones.append(int(v))
	show_zone_target(target_player_id, typed_zones, prompt, allow_skip)


# --- Local-display entry points (also called by RPC handlers on the client side) ---

func show_deck_search(matching: Array, all_cards: Array, prompt: String, allow_skip: bool) -> void:
	var handler: Callable = _handlers.get("deck_search", Callable())
	if handler.is_valid():
		handler.call(matching, all_cards, _translate(prompt), allow_skip, resolve_deck_search)
	else:
		push_warning("[EffectUIRouter] No handler registered for 'deck_search'")


func show_deck_arrange(cards: Array, prompt: String) -> void:
	var handler: Callable = _handlers.get("deck_arrange", Callable())
	if handler.is_valid():
		handler.call(cards, _translate(prompt), resolve_deck_arrange)
	else:
		push_warning("[EffectUIRouter] No handler registered for 'deck_arrange'")


func show_card_select(matching: Array, all_cards: Array, prompt: String, min_count: int, max_count: int) -> void:
	var pool_filter := Callable()
	if session and session.effect_handler:
		pool_filter = session.effect_handler._card_select_pool_filter
	var handler: Callable = _handlers.get("card_select", Callable())
	if handler.is_valid():
		handler.call(matching, all_cards, _translate(prompt), min_count, max_count, pool_filter, resolve_card_select)
	else:
		push_warning("[EffectUIRouter] No handler registered for 'card_select'")


func show_choice(options: Array, prompt: String) -> void:
	var translated: Array[String] = []
	for opt in options:
		translated.append(_translate(str(opt)))
	var handler: Callable = _handlers.get("choice", Callable())
	if handler.is_valid():
		handler.call(translated, _translate(prompt), resolve_choice)
	else:
		push_warning("[EffectUIRouter] No handler registered for 'choice'")


## Built-in zone-target flow: when a designer hasn't registered a custom
## "zone_target" handler, the router highlights the valid zones on the
## target PlayerBoard, listens for slot_clicked, and resolves with the
## chosen zone index. Skip is wired through ActionPanel's prompt panel
## when allow_skip is true and a SelectionModeController is present.
var _zone_target_active: bool = false
var _zone_target_valid: Array[int] = []
var _zone_target_board: Node = null


func show_zone_target(target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> void:
	var handler: Callable = _handlers.get("zone_target", Callable())
	if handler.is_valid():
		handler.call(target_player_id, valid_zones, _translate(prompt), allow_skip, resolve_zone_target)
		return
	# Built-in default. Find the target PlayerBoard, highlight valid zones,
	# wire each slot to call resolve_zone_target on click.
	var board := _find_player_board(target_player_id)
	if board == null:
		push_warning("[EffectUIRouter] No PlayerBoard found for player_id=%d — auto-skipping zone target." % target_player_id)
		resolve_zone_target(-1)
		return
	_zone_target_active = true
	_zone_target_valid = valid_zones
	_zone_target_board = board
	board.highlight_valid_zones(valid_zones)
	for i in range(board.zone_slots.size()):
		var slot = board.zone_slots[i]
		if slot and i in valid_zones:
			slot.in_selection_mode = true
			if not slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
				slot.slot_clicked.connect(_on_zone_target_slot_clicked)
	# Show the prompt + (optional) skip button via SelectionModeController
	# when one is reachable through the GameBoard root. Designer-built
	# scenes without an ActionPanel just see the highlighted zones; the
	# skip path is then unavailable (effect engine won't let allow_skip
	# stalls happen — the engine-side fallback only triggers when the
	# signal has no listeners; we ARE listening, so it'll wait for click).
	if _board:
		var sc = _board.get("selection_controller") if "selection_controller" in _board else null
		if sc and sc.has_method("prompt_confirmation"):
			# Reuse prompt_confirmation as a "skip" button when allow_skip,
			# else just show the prompt without a confirm button.
			if allow_skip:
				sc.prompt_confirmation(_translate(prompt), _on_zone_target_skip)
			else:
				# Show prompt without confirm/skip — disable confirm.
				if "_action_panel" in sc and sc._action_panel and sc._action_panel.has_method("show_prompt"):
					sc._action_panel.show_prompt(_translate(prompt), false)


func _find_player_board(target_player_id: int) -> Node:
	if _board == null:
		return null
	for pb in _board.find_children("*", "PlayerBoard", true, false):
		if "player_id" in pb and pb.player_id == target_player_id:
			return pb
	return null


func _on_zone_target_slot_clicked(zone_num: int, _pid: int) -> void:
	if not _zone_target_active:
		return
	var zone_idx: int = zone_num - 1
	if zone_idx not in _zone_target_valid:
		return
	resolve_zone_target(zone_idx)


func _on_zone_target_skip() -> void:
	if not _zone_target_active:
		return
	resolve_zone_target(-1)


func _cleanup_zone_target() -> void:
	if _zone_target_board:
		_zone_target_board.clear_highlights()
		for i in range(_zone_target_board.zone_slots.size()):
			var slot = _zone_target_board.zone_slots[i]
			if slot:
				slot.in_selection_mode = false
				if slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
					slot.slot_clicked.disconnect(_on_zone_target_slot_clicked)
	_zone_target_active = false
	_zone_target_valid.clear()
	_zone_target_board = null
	# Hide the prompt panel via SelectionModeController if present.
	if _board:
		var sc = _board.get("selection_controller") if "selection_controller" in _board else null
		if sc and "_action_panel" in sc and sc._action_panel and sc._action_panel.has_method("hide_prompt"):
			sc._action_panel.hide_prompt()


func show_cards_revealed(cards: Array, title: String) -> void:
	var handler: Callable = _handlers.get("cards_revealed", Callable())
	if handler.is_valid():
		handler.call(cards, _translate(title), resolve_cards_revealed)
	else:
		# Auto-resolve so the engine doesn't stall.
		resolve_cards_revealed()


func show_monster_rankup(monsters: Array, valid_indices: Array[int], prompt: String) -> void:
	var handler: Callable = _handlers.get("monster_rankup", Callable())
	if handler.is_valid():
		handler.call(monsters, valid_indices, _translate(prompt), resolve_monster_rankup)
	else:
		push_warning("[EffectUIRouter] No handler registered for 'monster_rankup'")


# --- Resolve callbacks: one place for the host vs client RPC dance ---

func resolve_deck_search(selected: Dictionary) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var json := JSON.stringify(selected)
		RpcLogger.log_send("deck_search_resolved", json.length())
		multiplayer_sync._rpc_deck_search_resolved.rpc_id(NetworkManager.host_peer_id, json)
	elif session and session.effect_handler:
		session.effect_handler.resolve_deck_search(selected)


func resolve_deck_arrange(keep: Array, discard: Array) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var keep_json := JSON.stringify(keep)
		var discard_json := JSON.stringify(discard)
		RpcLogger.log_send("deck_arrange_resolved", keep_json.length() + discard_json.length())
		multiplayer_sync._rpc_deck_arrange_resolved.rpc_id(NetworkManager.host_peer_id, keep_json, discard_json)
	elif session and session.effect_handler:
		var keep_typed: Array[Dictionary] = []
		for c in keep:
			keep_typed.append(c)
		var discard_typed: Array[Dictionary] = []
		for c in discard:
			discard_typed.append(c)
		session.effect_handler.resolve_deck_arrange(keep_typed, discard_typed)


func resolve_card_select(selected: Array) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		var json := JSON.stringify(_cards_to_ids(selected))
		RpcLogger.log_send("card_select_resolved", json.length())
		multiplayer_sync._rpc_card_select_resolved.rpc_id(NetworkManager.host_peer_id, json)
	elif session and session.effect_handler:
		var typed: Array[Dictionary] = []
		for c in selected:
			typed.append(c)
		session.effect_handler.resolve_card_select(typed)


func resolve_choice(index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("choice_resolved", 4)
		multiplayer_sync._rpc_choice_resolved.rpc_id(NetworkManager.host_peer_id, index)
	elif session and session.effect_handler:
		session.effect_handler.resolve_choice(index)


func resolve_cards_revealed() -> void:
	if session and session.effect_handler:
		session.effect_handler.resolve_cards_revealed()


func resolve_monster_rankup(index: int) -> void:
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("monster_rankup_resolved", 4)
		multiplayer_sync._rpc_monster_rankup_resolved.rpc_id(NetworkManager.host_peer_id, index)
	elif session and session.action_handler:
		session.action_handler.resolve_monster_rankup(index)


func resolve_zone_target(zone_index: int) -> void:
	_cleanup_zone_target()
	if is_multiplayer and not NetworkManager.is_host():
		RpcLogger.log_send("zone_target_resolved", 4)
		multiplayer_sync._rpc_zone_target_resolved.rpc_id(NetworkManager.host_peer_id, zone_index)
	elif session and session.effect_handler:
		session.effect_handler.resolve_zone_target(zone_index)
