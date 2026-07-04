class_name SignalPlayerInput
extends PlayerInput

## Live-play PlayerInput: every decision emits a request signal for the
## presentation layer (local UI, RPC routing to a remote peer, or the bot)
## and suspends until the matching resolve_*() callback delivers the answer.
##
## When a request signal has no connections the decision falls back to the
## PlayerInput base defaults — preserving the old EffectHandler behavior where
## prompts auto-resolved without a UI attached.
##
## Resolution is safe in either order: a handler may call resolve_*()
## synchronously during the request emit (the answer is recorded before the
## await starts) or any number of frames later.

## Decision-request signals. Signatures match the prompts that previously
## lived on EffectHandler / ActionHandler / TurnManager so presentation-side
## handlers connect unchanged.
signal choice_requested(player_id: int, options: Array[String], prompt: String)
signal deck_search_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool)
signal card_select_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int)
signal hand_discard_requested(player_id: int, discard_count: int)
signal hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool)
signal zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool)
signal strategy_target_requested(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String)
signal deck_arrange_requested(player_id: int, cards: Array[Dictionary], prompt: String)
signal cards_revealed_requested(player_id: int, cards: Array[Dictionary], title: String)
signal monster_rankup_requested(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String)
signal confirmation_requested(prompt: String, setting: String)

## Pending decisions keyed by kind: key -> {"resolved": bool, "value": Variant}.
var _pending: Dictionary = {}
signal _answer_delivered()

## Set by teardown(): late resolve_*() calls (e.g. bot SceneTreeTimer
## callbacks outliving the match) become silent no-ops instead of resuming
## engine coroutines into torn-down objects.
var _torn_down: bool = false


## Drop pending decisions at match teardown. Idempotent.
func teardown() -> void:
	_torn_down = true
	_pending.clear()


# --- Decision methods (engine-facing) ---

func choose_option(player_id: int, options: Array[String], prompt: String) -> int:
	if options.is_empty():
		return -1
	if choice_requested.get_connections().is_empty():
		return super(player_id, options, prompt)
	_open("choice")
	choice_requested.emit(player_id, options, prompt)
	return await _take("choice")


func search_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool) -> Dictionary:
	if deck_search_requested.get_connections().is_empty():
		return super(player_id, matching, all_cards, prompt, allow_skip)
	_open("deck_search")
	deck_search_requested.emit(player_id, matching, all_cards, prompt, allow_skip)
	return await _take("deck_search")


func select_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> Array[Dictionary]:
	if card_select_requested.get_connections().is_empty():
		return super(player_id, matching, all_cards, prompt, min_count, max_count)
	_open("card_select")
	card_select_requested.emit(player_id, matching, all_cards, prompt, min_count, max_count)
	return await _take("card_select")


func choose_hand_discards(player_id: int, count: int, hand_size: int) -> Array[int]:
	if hand_discard_requested.get_connections().is_empty():
		return super(player_id, count, hand_size)
	_open("hand_discard")
	hand_discard_requested.emit(player_id, count)
	return await _take("hand_discard")


func select_hand_card(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> int:
	if hand_card_selection_requested.get_connections().is_empty():
		return super(player_id, valid_indices, prompt, allow_skip)
	_open("hand_card_selection")
	hand_card_selection_requested.emit(player_id, valid_indices, prompt, allow_skip)
	return await _take("hand_card_selection")


func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
	if zone_target_requested.get_connections().is_empty():
		return super(player_id, target_player_id, valid_zones, prompt, allow_skip)
	_open("zone_target")
	zone_target_requested.emit(player_id, target_player_id, valid_zones, prompt, allow_skip)
	return await _take("zone_target")


func select_strategy(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	if strategy_target_requested.get_connections().is_empty():
		return super(player_id, target_player_id, valid_indices, prompt)
	_open("strategy_target")
	strategy_target_requested.emit(player_id, target_player_id, valid_indices, prompt)
	return await _take("strategy_target")


func arrange_deck(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	if deck_arrange_requested.get_connections().is_empty():
		return super(player_id, cards, prompt)
	_open("deck_arrange")
	deck_arrange_requested.emit(player_id, cards, prompt)
	return await _take("deck_arrange")


func acknowledge_reveal(player_id: int, cards: Array[Dictionary], title: String) -> void:
	if cards_revealed_requested.get_connections().is_empty():
		return
	_open("cards_revealed")
	cards_revealed_requested.emit(player_id, cards, title)
	await _take("cards_revealed")


func choose_rankup(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> int:
	if monster_rankup_requested.get_connections().is_empty():
		return super(player_id, monsters, valid_indices, prompt)
	_open("monster_rankup")
	monster_rankup_requested.emit(player_id, monsters, valid_indices, prompt)
	return await _take("monster_rankup")


func confirm_step(_player_id: int, prompt: String, setting: String) -> void:
	if confirmation_requested.get_connections().is_empty():
		return
	_open("confirmation")
	confirmation_requested.emit(prompt, setting)
	await _take("confirmation")


# --- Resolve callbacks (presentation-facing; names kept from the old API) ---

func resolve_choice(index: int) -> void:
	_deliver("choice", index)


func resolve_deck_search(selected_card: Dictionary) -> void:
	_deliver("deck_search", selected_card)


func resolve_card_select(selected: Array[Dictionary]) -> void:
	_deliver("card_select", selected)


## player_id is accepted for signature compatibility with the old
## EffectHandler.resolve_hand_discard; the awaiting caller already knows
## whose hand is being discarded.
func resolve_hand_discard(_player_id: int, hand_indices: Array[int]) -> void:
	_deliver("hand_discard", hand_indices)


func resolve_hand_card_selection(hand_index: int) -> void:
	_deliver("hand_card_selection", hand_index)


func resolve_zone_target(zone_index: int) -> void:
	_deliver("zone_target", zone_index)


func resolve_strategy_target(strategy_index: int) -> void:
	_deliver("strategy_target", strategy_index)


func resolve_deck_arrange(keep: Array[Dictionary], discard: Array[Dictionary]) -> void:
	_deliver("deck_arrange", {"keep": keep, "discard": discard})


func resolve_cards_revealed() -> void:
	_deliver("cards_revealed", null)


func resolve_monster_rankup(index: int) -> void:
	_deliver("monster_rankup", index)


func resolve_confirmation() -> void:
	_deliver("confirmation", null)


## True if a decision of the given kind is awaiting an answer (diagnostics).
func pending_kinds() -> Array:
	return _pending.keys()


# --- Internals ---

func _open(key: String) -> void:
	_pending[key] = {"resolved": false, "value": null}


func _deliver(key: String, value: Variant) -> void:
	if _torn_down:
		# Late resolve after match teardown (e.g. a bot SceneTreeTimer that
		# outlived the scene) — expected, drop silently.
		return
	if not _pending.has(key):
		push_warning("[PlayerInput] Unsolicited resolve for '%s' ignored" % key)
		return
	if _pending[key]["resolved"]:
		push_warning("[PlayerInput] Duplicate resolve for '%s' ignored" % key)
		return
	_pending[key]["resolved"] = true
	_pending[key]["value"] = value
	_answer_delivered.emit()


func _take(key: String) -> Variant:
	while not _pending[key]["resolved"]:
		await _answer_delivered
	var value: Variant = _pending[key]["value"]
	_pending.erase(key)
	return value
