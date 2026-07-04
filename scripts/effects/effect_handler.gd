class_name EffectHandler
extends RefCounted

## Loads, caches, and dispatches card effect triggers across the game.
## Called by ActionHandler and TurnManager at appropriate trigger points.
##
## Player decisions (deck search, zone targets, choices, ...) go through the
## injected PlayerInput — SignalPlayerInput in live play (request signals +
## resolve callbacks for UI/RPC/bot), ScriptedPlayerInput or the PlayerInput
## defaults in tests/headless runs.

## Emitted to highlight/unhighlight a zone card during effect resolution.
signal effect_zone_highlighted(player_id: int, zone_index: int)
signal effect_zone_unhighlighted(player_id: int, zone_index: int)

## Emitted to highlight/unhighlight the source card while awaiting a player decision.
signal effect_card_highlighted(player_id: int, card_id: String)
signal effect_card_unhighlighted(player_id: int, card_id: String)

## Emitted to send a message to the game log.
signal log_message(token: Dictionary)
signal card_evolved(player_id: int, card: Dictionary, zone_index: int)
signal card_destroyed(player_id: int, zone_index: int)

var game_state: GameState
var action_handler  # ActionHandler reference (set by TurnManager)
var input: PlayerInput
var events: GameEvents = null  # Notification bus (wired by MatchFactory; null in bare tests)
var registry := EffectRegistry.new()
var exec := EffectExecutionState.new()
var standby: StandbyResolver
var dispatcher: TriggerDispatcher
var destruction: DestructionEngine
var mover: CardMover
var monster_mover: MonsterMover
var queries: EffectQueries
var _card_select_pool_filter: Callable = Callable()  # Optional: func(card, selection) -> bool; read by the card-select UI

## Base card ids parallel to the most recent select_choice options ("" for
## options without a card). The choice UI reads this to show an artwork
## thumbnail on each button; cleared when the choice resolves.
var choice_card_ids: Array[String] = []

## Structured source locations parallel to the most recent select_choice
## options (see StandbyResolver.card_location_ref). The choice UI reads this
## to highlight the source card on the board while an option is hovered.
## Empty for generic effect choices; cleared when the choice resolves.
var choice_source_refs: Array[Dictionary] = []

## Base id of the card being placed by the most recent select_zone_target
## ("" when the prompt is zone-only, e.g. destroy). The zone-target UI reads
## this to show a preview of the card; cleared when the target resolves.
var zone_target_card_id: String = ""

## Forwarders into the shared EffectExecutionState — internal call sites and
## external readers (bot, UI) keep the historical names.
var pending_destroy_max_rank: int:  # Set before the zone-target prompt for bot rank filtering
	get: return exec.pending_destroy_max_rank
	set(v): exec.pending_destroy_max_rank = v
var _active_effect_player_id: int:
	get: return exec.active_player_id
	set(v): exec.active_player_id = v
var _active_effect_card: Dictionary:
	get: return exec.active_card
	set(v): exec.active_card = v
var _in_standby_resolution: bool:
	get: return exec.in_standby_resolution
	set(v): exec.in_standby_resolution = v
var _pending_standby_entries: Array:
	get: return exec.pending_standby_entries
	set(v): exec.pending_standby_entries = v



func setup(p_game_state: GameState, p_input: PlayerInput = null) -> void:
	game_state = p_game_state
	input = p_input if p_input else PlayerInput.new()
	standby = StandbyResolver.new()
	standby.game_state = game_state
	standby.exec = exec
	standby.handler = self
	dispatcher = TriggerDispatcher.new()
	dispatcher.h = self
	destruction = DestructionEngine.new()
	destruction.h = self
	mover = CardMover.new()
	mover.h = self
	monster_mover = MonsterMover.new()
	monster_mover.h = self
	queries = EffectQueries.new()
	queries.h = self




# --- Effect loading (delegates to EffectRegistry) ---

func get_effect(card_data: Dictionary) -> CardEffect:
	return registry.get_effect(card_data)




func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	return registry.has_trigger(card_data, method_name)




func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	return registry.get_trigger_filter(card_data, method_name)




func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return EffectContext.create(game_state, owner_id, card_data, self)




# --- Active effect tracking (for decision highlighting) ---

func _set_active_effect(player_id: int, card_data: Dictionary) -> void:
	_active_effect_player_id = player_id
	_active_effect_card = card_data




## {card_id, label} for the ability currently resolving ({} if none) — the
## UI shows this above effect prompt overlays. card_id is the base id; label
## matches the resolution-order choice option text.
func get_active_effect_summary() -> Dictionary:
	if _active_effect_card.is_empty():
		return {}
	return {
		"card_id": CardUtils.base_id(_active_effect_card),
		"label": _get_card_location_label(_active_effect_player_id, _active_effect_card),
	}




func _clear_active_effect() -> void:
	# Defensive: emit unhighlight when clearing, in case the leaf function that
	# emitted the matching highlight didn't reach its own _unhighlight call.
	# UI side is idempotent — clearing an already-clear highlight is a no-op.
	_unhighlight_active_effect()
	_active_effect_player_id = -1
	_active_effect_card = {}




func _highlight_active_effect() -> void:
	if _active_effect_player_id >= 0:
		var card_id: String = _active_effect_card.get("id", "")
		if not card_id.is_empty():
			effect_card_highlighted.emit(_active_effect_player_id, card_id)




func _unhighlight_active_effect() -> void:
	if _active_effect_player_id >= 0:
		var card_id: String = _active_effect_card.get("id", "")
		if not card_id.is_empty():
			effect_card_unhighlighted.emit(_active_effect_player_id, card_id)




func _get_card_location_label(player_id: int, card_data: Dictionary) -> String:
	return StandbyResolver.card_location_label(game_state, player_id, card_data)




func _resolve_standby_entries(entries: Array) -> void:
	await standby.resolve_entries(entries)




func apply_rage_reset(player_id: int) -> int:
	## Called at start phase rage reset. Returns new rage value (0 by default).
	## Effects can intercept by returning a non-zero value from on_rage_reset.
	var player := game_state.players[player_id]
	var candidates: Array = []
	var me := get_effect(player.current_monster)
	if me and has_trigger(player.current_monster, "on_rage_reset"):
		candidates.append({"card": player.current_monster, "effect": me})
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and has_trigger(zone_card, "on_rage_reset"):
				candidates.append({"card": zone_card, "effect": ze})
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se and has_trigger(sz_card, "on_rage_reset"):
				candidates.append({"card": sz_card, "effect": se})
	for entry in candidates:
		var ctx := _build_context(player_id, entry.card)
		var result: int = await entry.effect.on_rage_reset(ctx)
		if result != 0:
			return result
	return 0




func reduce_rage(player_id: int, amount: int) -> int:
	## Reduce a player's rage by amount. Returns actual amount reduced.
	## Respects rage reduction prevention effects (e.g. EBP03-004).
	## Populates the player's transient pending_rage_markers bucket with one
	## RAGE-MARKER per point reduced so claiming effects (e.g. EBP04-089) can
	## pop them; whatever isn't claimed is banished after the trigger resolves.
	var player := game_state.players[player_id]
	if not player.has_rage() or amount <= 0:
		return 0
	if is_rage_reduction_prevented(player_id):
		return 0
	var old_rage: int = player.rage
	var actual: int = mini(amount, player.rage)
	player.rage -= actual
	player.rage_changed.emit(player.rage)
	player.push_pending_rage_markers(actual)
	await trigger_rage_changed(player_id, old_rage, player.rage)
	player.pending_rage_markers.clear()
	return actual




func gain_rage(player_id: int, amount: int, source_card_id: String = "") -> int:
	## Increase a player's rage by amount. Returns actual amount gained.
	## Mirror of reduce_rage — handles the old/new rage bookkeeping and trigger dispatch.
	## `source_card_id` (optional) attributes the rage gain to a card in the log.
	if amount <= 0:
		return 0
	var player := game_state.players[player_id]
	var old_rage: int = player.rage
	player.rage += amount
	player.rage_changed.emit(player.rage)
	log_message.emit(GameLog.rage_gained(player_id, amount, player.rage, source_card_id))
	await trigger_rage_changed(player_id, old_rage, player.rage)
	return amount




# --- Deferred movement resolution ---

func is_card_still_active(player_id: int, card_data: Dictionary) -> bool:
	return standby.is_card_still_active(player_id, card_data)




func resolve_deferred_entries(entries: Array) -> void:
	await standby.resolve_deferred_entries(entries)




func select_zone_target(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false, card_id: String = "") -> int:
	## Ask a player to choose one of the valid zones on the target player's board.
	## If allow_skip is true, the player can decline (returns -1).
	## `card_id` (optional) gives the base id of the card being placed so the
	## UI can show a preview of it next to the prompt.
	## Returns the chosen zone index, or -1 if no valid zones or skipped.
	if valid_zones.is_empty():
		return -1

	zone_target_card_id = card_id
	_highlight_active_effect()
	var zone_index: int = await input.select_zone(player_id, target_player_id, valid_zones, prompt, allow_skip)
	_unhighlight_active_effect()
	zone_target_card_id = ""
	return zone_index




func select_strategy_target(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	## Ask a player to choose one of the valid strategy zones on the target player's board.
	## Always prompts when at least one valid index exists so the player can see
	## which strategy is being targeted (no silent auto-pick on size==1).
	## Returns the chosen strategy index, or -1 if no valid indices.
	if valid_indices.is_empty():
		return -1

	_highlight_active_effect()
	var strategy_index: int = await input.select_strategy(player_id, target_player_id, valid_indices, prompt)
	_unhighlight_active_effect()
	return strategy_index




func select_choice(player_id: int, options: Array[String], prompt: String, card_ids: Array[String] = []) -> int:
	## Present multiple text options to the player and let them choose one.
	## Returns the chosen index (0-based), or 0 as fallback if no UI connected.
	## `card_ids` (optional) gives the base card id behind each option so the
	## UI can show the card's art next to the text.
	if options.is_empty():
		return -1

	choice_card_ids = card_ids
	_highlight_active_effect()
	var index: int = await input.choose_option(player_id, options, prompt)
	_unhighlight_active_effect()
	choice_card_ids = []
	choice_source_refs = []
	return index




func reveal_cards(player_id: int, cards: Array[Dictionary], title: String) -> void:
	## Show a set of cards to the player and wait for them to dismiss the overlay.
	if cards.is_empty():
		return
	await input.acknowledge_reveal(player_id, cards, title)




func highlight_zone_card(player_id: int, zone_index: int) -> void:
	## Highlight a zone's card to show its effect is being resolved.
	effect_zone_highlighted.emit(player_id, zone_index)




func unhighlight_zone_card(player_id: int, zone_index: int) -> void:
	## Remove highlight from a zone's card after effect resolution.
	effect_zone_unhighlighted.emit(player_id, zone_index)




static func banish_or_discard(player: PlayerState, stack: Array) -> void:
	## Route cards to banishment (tokens) or discard pile (non-tokens).
	## Tokens are removed from the game entirely; non-tokens go to discard pile.
	for card in stack:
		if not PlayerState.is_token(card):
			player.discard_pile.append(card)




func force_counter(target_player_id: int) -> void:
	## Force a successful counter against target_player_id's monster.
	## The target's monster retreats and ranks up; the other player is the winner.
	if action_handler:
		await action_handler.force_counter(game_state, target_player_id)


# --- Delegates to the split-out modules (the effect-script-facing API) ---

func trigger_enter(player_id: int, card_data: Dictionary, from_effect: bool = false) -> void:
	await dispatcher.trigger_enter(player_id, card_data, from_effect)


func trigger_when_invading(player_id: int, from_zone: int, to_zone: int) -> void:
	await dispatcher.trigger_when_invading(player_id, from_zone, to_zone)


func collect_when_invading_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	return dispatcher.collect_when_invading_entries(player_id, from_zone, to_zone)


func trigger_crush(player_id: int, card_data: Dictionary) -> void:
	await dispatcher.trigger_crush(player_id, card_data)


func trigger_revenge(player_id: int, card_data: Dictionary) -> void:
	await dispatcher.trigger_revenge(player_id, card_data)


func collect_crush_and_revenge_entries(player_id: int, card_data: Dictionary) -> Array:
	return dispatcher.collect_crush_and_revenge_entries(player_id, card_data)


func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:
	await dispatcher.trigger_discard_from_hand(player_id, card_data)


func collect_discard_from_hand_entries(player_id: int, card_data: Dictionary) -> Array:
	return dispatcher.collect_discard_from_hand_entries(player_id, card_data)


func trigger_hand_cards_discarded_batch(player_id: int, cards: Array) -> void:
	await dispatcher.trigger_hand_cards_discarded_batch(player_id, cards)


func collect_discarded_for_invasion_entries(player_id: int, card_data: Dictionary) -> Array:
	return dispatcher.collect_discarded_for_invasion_entries(player_id, card_data)


func trigger_burst_discard(player_id: int, card_data: Dictionary) -> void:
	await dispatcher.trigger_burst_discard(player_id, card_data)


func trigger_rage_changed(player_id: int, old_rage: int, new_rage: int) -> void:
	await dispatcher.trigger_rage_changed(player_id, old_rage, new_rage)


func trigger_monster_advance(player_id: int, from_zone: int, to_zone: int) -> void:
	await dispatcher.trigger_monster_advance(player_id, from_zone, to_zone)


func collect_monster_advance_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	return dispatcher.collect_monster_advance_entries(player_id, from_zone, to_zone)


func trigger_phase_start(phase: CardEnums.GamePhase) -> void:
	await dispatcher.trigger_phase_start(phase)


func trigger_phase_end(phase: CardEnums.GamePhase) -> void:
	await dispatcher.trigger_phase_end(phase)


func trigger_monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary, discard_snapshot: Array = []) -> void:
	await dispatcher.trigger_monster_played(player_id, old_monster, new_monster, discard_snapshot)


func trigger_battle_card_played(player_id: int, card_data: Dictionary, zone_index: int, played_from_deck: bool = false) -> void:
	await dispatcher.trigger_battle_card_played(player_id, card_data, zone_index, played_from_deck)


func trigger_hand_card_discarded(player_id: int, card_data: Dictionary) -> void:
	await dispatcher.trigger_hand_card_discarded(player_id, card_data)


func collect_hand_card_discarded_entries(player_id: int, card_data: Dictionary) -> Array:
	return dispatcher.collect_hand_card_discarded_entries(player_id, card_data)


func trigger_counter_success(counterer_player_id: int, countered_player_id: int) -> void:
	await dispatcher.trigger_counter_success(counterer_player_id, countered_player_id)


func trigger_strategy_discarded(player_id: int, strategy_card: Dictionary) -> void:
	await dispatcher.trigger_strategy_discarded(player_id, strategy_card)


func collect_strategy_discarded_entries(player_id: int, strategy_card: Dictionary) -> Array:
	return dispatcher.collect_strategy_discarded_entries(player_id, strategy_card)


func trigger_invasion_observed(invading_player_id: int, from_zone: int, to_zone: int) -> void:
	await dispatcher.trigger_invasion_observed(invading_player_id, from_zone, to_zone)


func collect_invasion_observed_entries(invading_player_id: int, from_zone: int, to_zone: int) -> Array:
	return dispatcher.collect_invasion_observed_entries(invading_player_id, from_zone, to_zone)


func trigger_leave_play(player_id: int, leaving_card: Dictionary, zone_index: int) -> void:
	await dispatcher.trigger_leave_play(player_id, leaving_card, zone_index)


func trigger_all_monster_enter_abilities(player_id: int) -> void:
	await dispatcher.trigger_all_monster_enter_abilities(player_id)


func collect_ally_zone_card_destroyed_entries(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	return dispatcher.collect_ally_zone_card_destroyed_entries(player_id, destroyed_card, zone_idx)


func trigger_ally_zone_card_destroyed(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	await dispatcher.trigger_ally_zone_card_destroyed(player_id, destroyed_card, zone_idx)


func collect_opponent_zone_card_destroyed_entries(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	return dispatcher.collect_opponent_zone_card_destroyed_entries(destroyed_player_id, destroyed_card, zone_idx)


func trigger_opponent_zone_card_destroyed(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	await dispatcher.trigger_opponent_zone_card_destroyed(destroyed_player_id, destroyed_card, zone_idx)


func collect_card_returned_from_discard_entries(returning_player_id: int, card: Dictionary) -> Array:
	return dispatcher.collect_card_returned_from_discard_entries(returning_player_id, card)


func trigger_card_returned_from_discard(returning_player_id: int, card: Dictionary) -> void:
	await dispatcher.trigger_card_returned_from_discard(returning_player_id, card)


func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	return await destruction.destroy_zone_target(player_id, target, filter, prompt)


func destroy_chosen_zone(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String) -> Dictionary:
	return await destruction.destroy_chosen_zone(player_id, target, valid_zones, prompt)


func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	return await destruction.destroy_zones(target, zone_indices)


func destroy_zone_and_adjacent(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String, max_rank: int = -1) -> Array[Dictionary]:
	return await destruction.destroy_zone_and_adjacent(player_id, target, valid_zones, prompt, max_rank)


func can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	return destruction.can_destroy_card(target, card_data)


func _can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	return destruction._can_destroy_card(target, card_data)


func _execute_destroy_zone(target: PlayerState, zone_idx: int, top_card: Dictionary, deferred_entries: Variant = null) -> Dictionary:
	return await destruction._execute_destroy_zone(target, zone_idx, top_card, deferred_entries)


func get_strategy_discard_interceptor(player_id: int) -> int:
	return destruction.get_strategy_discard_interceptor(player_id)


func destroy_strategy_zone(player: PlayerState, zone_index: int) -> Dictionary:
	return await destruction.destroy_strategy_zone(player, zone_index)


func discard_strategy_from_zone(player_id: int, zone_index: int, deferred_entries: Variant = null, bypass_protection: bool = false) -> Dictionary:
	return await destruction.discard_strategy_from_zone(player_id, zone_index, deferred_entries, bypass_protection)


func destroy_base_strategies_on_invasion(to_zone: int, deferred_entries: Variant = null) -> void:
	await destruction.destroy_base_strategies_on_invasion(to_zone, deferred_entries)


func discard_hand_to(player_id: int, target_count: int) -> Array[Dictionary]:
	return await mover.discard_hand_to(player_id, target_count)


func search_deck(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	return await mover.search_deck(player_id, filter, prompt, allow_skip)


func arrange_deck_cards(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	return await mover.arrange_deck_cards(player_id, cards, prompt)


func select_cards_from_pool(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int = -1, pool_filter: Callable = Callable()) -> Array[Dictionary]:
	return await mover.select_cards_from_pool(player_id, matching, all_cards, prompt, min_count, max_count, pool_filter)


func search_discard(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	return await mover.search_discard(player_id, filter, prompt, allow_skip)


func select_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	return await mover.select_hand_card(player_id, filter, prompt, allow_skip)


func select_from_cards(player_id: int, options: Array[Dictionary], all_visible: Array[Dictionary], prompt: String, allow_skip: bool = true) -> Dictionary:
	return await mover.select_from_cards(player_id, options, all_visible, prompt, allow_skip)


func reveal_deck_top(player_id: int, count: int, title_key: String = "STR_EFF_REVEALED_FROM_DECK_TOP") -> Array[Dictionary]:
	return await mover.reveal_deck_top(player_id, count, title_key)


func discard_cards(player_id: int, cards: Array[Dictionary]) -> void:
	mover.discard_cards(player_id, cards)


func search_and_discard_deck_top(player_id: int, count: int, filter: Callable, prompt: String) -> Dictionary:
	return await mover.search_and_discard_deck_top(player_id, count, filter, prompt)


func perform_evolution(player_id: int, zone_idx: int) -> bool:
	return await mover.perform_evolution(player_id, zone_idx)


func evolve_zones_in_order(player_id: int, eligible_zones: Array[int]) -> void:
	await mover.evolve_zones_in_order(player_id, eligible_zones)


func create_token_in_zone(player: PlayerState, token_id: String, zone_index: int) -> bool:
	return await mover.create_token_in_zone(player, token_id, zone_index)


func create_tokens_in_zones(player: PlayerState, token_id: String, count: int, candidate_zones: Array[int] = [], prompt_key: String = "STR_EFF_TOKEN_ZONE_FMT") -> int:
	return await mover.create_tokens_in_zones(player, token_id, count, candidate_zones, prompt_key)


func play_battle_cards_in_zones(player: PlayerState, cards: Array[Dictionary], pick_prompt: String, candidate_zones: Array[int] = [], from_discard: bool = false, max_count: int = -1) -> Array[Dictionary]:
	return await mover.play_battle_cards_in_zones(player, cards, pick_prompt, candidate_zones, from_discard, max_count)


func return_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	mover.return_to_deck_bottom(player, card_data)


func move_zone_card_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	mover.move_zone_card_to_deck_bottom(player, card_data)


func apply_play_cost(player_id: int, card_data: Dictionary, zone_index: int) -> bool:
	return await mover.apply_play_cost(player_id, card_data, zone_index)


func move_zone_stack(player: PlayerState, from_zone: int, to_zone: int) -> void:
	await mover.move_zone_stack(player, from_zone, to_zone)


func swap_zones(player: PlayerState, zone_a: int, zone_b: int) -> void:
	await mover.swap_zones(player, zone_a, zone_b)


func play_from_discard(player_id: int, card_data: Dictionary, zone_idx: int = -1) -> int:
	return await mover.play_from_discard(player_id, card_data, zone_idx)


func play_from_discard_or_skip(player_id: int, card_data: Dictionary, prompt: String, zone_filter: Callable = Callable()) -> int:
	return await mover.play_from_discard_or_skip(player_id, card_data, prompt, zone_filter)


func play_battle_card_from_hand(player_id: int, card_data: Dictionary, zone_idx: int) -> void:
	await mover.play_battle_card_from_hand(player_id, card_data, zone_idx)


func play_battle_card_from_deck(player_id: int, card_data: Dictionary, zone_idx: int, stack_on_top: bool = false) -> void:
	await mover.play_battle_card_from_deck(player_id, card_data, zone_idx, stack_on_top)


func place_card_under_zone(player: PlayerState, card: Dictionary, zone_idx: int) -> void:
	mover.place_card_under_zone(player, card, zone_idx)


func get_cards_under_top(player: PlayerState, zone_idx: int) -> Array:
	return mover.get_cards_under_top(player, zone_idx)


func place_card_under_strategy_zone(player: PlayerState, card: Dictionary, strat_idx: int) -> void:
	mover.place_card_under_strategy_zone(player, card, strat_idx)


func get_cards_under_strategy_top(player: PlayerState, strat_idx: int) -> Array:
	return mover.get_cards_under_strategy_top(player, strat_idx)


func return_discard_to_hand(player_id: int, card: Dictionary) -> void:
	await mover.return_discard_to_hand(player_id, card)


func add_card_to_hand(player_id: int, card: Dictionary) -> void:
	mover.add_card_to_hand(player_id, card)


func add_cards_to_hand(player_id: int, cards: Array[Dictionary]) -> void:
	mover.add_cards_to_hand(player_id, cards)


func put_card_on_top_of_deck(player_id: int, card: Dictionary) -> void:
	mover.put_card_on_top_of_deck(player_id, card)


func shuffle_discard_into_deck(player_id: int) -> int:
	return mover.shuffle_discard_into_deck(player_id)


func advance_monster_to_zone(player_id: int, target_zone: int) -> void:
	await monster_mover.advance_monster_to_zone(player_id, target_zone)


func retreat_monster_to_zone(player_id: int, target_zone: int) -> void:
	await monster_mover.retreat_monster_to_zone(player_id, target_zone)


func teleport_monster(player_id: int, target_zone: int) -> bool:
	return monster_mover.teleport_monster(player_id, target_zone)


func move_monster_as_countered(player_id: int) -> void:
	monster_mover.move_monster_as_countered(player_id)


func is_rage_reduction_prevented(player_id: int) -> bool:
	return queries.is_rage_reduction_prevented(player_id)


func can_monster_be_played_from_hand(player_id: int, card_data: Dictionary) -> bool:
	return queries.can_monster_be_played_from_hand(player_id, card_data)


func get_counter_power_modifier(player_id: int) -> int:
	return queries.get_counter_power_modifier(player_id)


func get_monster_cp_modifier(player_id: int) -> int:
	return queries.get_monster_cp_modifier(player_id)


func get_strategy_cp_modifiers(player_id: int) -> Array[int]:
	return queries.get_strategy_cp_modifiers(player_id)


func get_zone_cp_modifiers(player_id: int) -> Array[int]:
	return queries.get_zone_cp_modifiers(player_id)


func get_zone_cp_breakdown(player_id: int) -> Array:
	return queries.get_zone_cp_breakdown(player_id)


func get_threat_level_breakdown(player_id: int) -> Array:
	return queries.get_threat_level_breakdown(player_id)


func get_play_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	return queries.get_play_rank_breakdown(player_id, card)


func get_strategy_hand_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	return queries.get_strategy_hand_rank_breakdown(player_id, card)


func get_field_rank_breakdown(player_id: int) -> Array:
	return queries.get_field_rank_breakdown(player_id)


func get_zone_play_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	return queries.get_zone_play_rank_breakdown(player_id, card)


func get_hand_cp_preview(player_id: int, card: Dictionary) -> int:
	return queries.get_hand_cp_preview(player_id, card)


func get_hand_variable_base_cp(player_id: int, card: Dictionary) -> int:
	return queries.get_hand_variable_base_cp(player_id, card)


func get_threat_level_modifier(player_id: int) -> int:
	return queries.get_threat_level_modifier(player_id)


func get_effective_threat_level(player_id: int) -> int:
	return queries.get_effective_threat_level(player_id)


func get_play_rank_modifier(player_id: int, card: Dictionary) -> int:
	return queries.get_play_rank_modifier(player_id, card)


func should_stack_on_play(player_id: int, card: Dictionary, zone_index: int) -> bool:
	return queries.should_stack_on_play(player_id, card, zone_index)


func get_zone_play_rank_modifier(player_id: int, card: Dictionary, zone_index: int) -> int:
	return queries.get_zone_play_rank_modifier(player_id, card, zone_index)


func is_invasion_blocked(defender_player_id: int) -> bool:
	return queries.is_invasion_blocked(defender_player_id)


func get_engagement_restriction(attacker_player_id: int) -> int:
	return queries.get_engagement_restriction(attacker_player_id)


func get_engagement_restricted_cp(defender_player_id: int) -> int:
	return queries.get_engagement_restricted_cp(defender_player_id)


func get_cards_that_can_engage(player_id: int) -> Array[int]:
	return queries.get_cards_that_can_engage(player_id)


func get_opponent_blocked_zones(blocker_player_id: int) -> Array[int]:
	return queries.get_opponent_blocked_zones(blocker_player_id)


func get_extra_end_phase_advance(player_id: int) -> int:
	return queries.get_extra_end_phase_advance(player_id)


func get_invasion_advance_bonus(player_id: int, invasion_icon: int) -> int:
	return queries.get_invasion_advance_bonus(player_id, invasion_icon)


func can_play_as_monster(player_id: int, card: Dictionary) -> bool:
	return queries.can_play_as_monster(player_id, card)


func is_monster_advance_blocked(player_id: int) -> bool:
	return queries.is_monster_advance_blocked(player_id)


func is_own_invasion_blocked(player_id: int) -> bool:
	return queries.is_own_invasion_blocked(player_id)


func can_replace_invasion_cost(player_id: int) -> bool:
	return queries.can_replace_invasion_cost(player_id)


func get_counter_immunity_threshold(player_id: int) -> int:
	return queries.get_counter_immunity_threshold(player_id)


func is_counter_prevented(player_id: int, total_cp: int) -> bool:
	return queries.is_counter_prevented(player_id, total_cp)


func are_opponent_strategy_plays_blocked(player_id: int) -> bool:
	return queries.are_opponent_strategy_plays_blocked(player_id)


func get_opponent_field_rank_modifier(player_id: int) -> int:
	return queries.get_opponent_field_rank_modifier(player_id)


func is_base_strategy(card_data: Dictionary) -> bool:
	return queries.is_base_strategy(card_data)


func prevents_self_start_phase_discard(player_id: int, card_data: Dictionary) -> bool:
	return queries.prevents_self_start_phase_discard(player_id, card_data)


func can_card_be_played(player_id: int, card_data: Dictionary) -> bool:
	return queries.can_card_be_played(player_id, card_data)


func get_card_required_play_zones(player_id: int, card_data: Dictionary) -> Array[int]:
	return queries.get_card_required_play_zones(player_id, card_data)


func get_effective_field_rank(card_data: Dictionary, owner_player_id: int) -> int:
	return queries.get_effective_field_rank(card_data, owner_player_id)


func get_zones_in_rank_range(player_id: int, min_rank: int = -1, max_rank: int = -1) -> Array[int]:
	return queries.get_zones_in_rank_range(player_id, min_rank, max_rank)


func get_effective_zone_cp(player_id: int, zone_idx: int) -> int:
	return queries.get_effective_zone_cp(player_id, zone_idx)


func get_zones_in_cp_range(player_id: int, min_cp: int = -1, max_cp: int = -1) -> Array[int]:
	return queries.get_zones_in_cp_range(player_id, min_cp, max_cp)


func get_zone_rank_modifiers(player_id: int) -> Array:
	return queries.get_zone_rank_modifiers(player_id)


func is_opponent_end_phase_draw_blocked(drawing_player_id: int) -> bool:
	return queries.is_opponent_end_phase_draw_blocked(drawing_player_id)


func is_opponent_monster_move_blocked(target_player_id: int) -> bool:
	return queries.is_opponent_monster_move_blocked(target_player_id)


func is_invade1_cost_blocked(invading_player_id: int) -> bool:
	return queries.is_invade1_cost_blocked(invading_player_id)


func get_strategy_hand_rank_modifier(player_id: int, card: Dictionary) -> int:
	return queries.get_strategy_hand_rank_modifier(player_id, card)
