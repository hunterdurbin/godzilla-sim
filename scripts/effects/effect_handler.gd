class_name EffectHandler
extends RefCounted

## The card-script interface: the primitives per-card effect scripts
## (scripts/effects/<set>/) call through `ctx.effect_handler` — every public
## method here has a card-script caller (scripts/tools/
## check_effect_handler_card_api.py). The engine itself lives in the modules
## below, wired once in `setup` with direct references to each other; core,
## UI, bot and test code call those modules (`queries`, `dispatcher`,
## `check_timing`, `destruction`, `mover`, `monster_mover`, `enter_zone`,
## `registry`), never a facade delegate.
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
# Emitted by the modules via `h.card_evolved.emit(...)`, not from this class.
@warning_ignore("unused_signal")
signal card_evolved(player_id: int, card: Dictionary, zone_index: int)
@warning_ignore("unused_signal")
signal card_destroyed(player_id: int, zone_index: int)

var game_state: GameState
var action_handler  # ActionHandler reference (set by TurnManager)
var input: PlayerInput
var events: GameEvents = null  # Notification bus (wired by MatchFactory; null in bare tests)
var registry := EffectRegistry.new()
var check_timing: CheckTiming
var dispatcher: TriggerDispatcher
var destruction: DestructionEngine
var mover: CardMover
var monster_mover: MonsterMover
var enter_zone: EnterZone
var queries: EffectQueries
@warning_ignore("unused_private_class_variable") # written by effects, read by the card-select UI
var _card_select_pool_filter: Callable = Callable()  # Optional: func(card, selection) -> bool

## Base card ids parallel to the most recent select_choice options ("" for
## options without a card). The choice UI reads this to show an artwork
## thumbnail on each button; cleared when the choice resolves.
var choice_card_ids: Array[String] = []

## Structured source locations parallel to the most recent select_choice
## options (see CheckTiming.card_location_ref). The choice UI reads this
## to highlight the source card on the board while an option is hovered.
## Empty for generic effect choices; cleared when the choice resolves.
var choice_source_refs: Array[Dictionary] = []

## Base id of the card being placed by the most recent select_zone_target
## ("" when the prompt is zone-only, e.g. destroy). The zone-target UI reads
## this to show a preview of the card; cleared when the target resolves.
var zone_target_card_id: String = ""



func setup(p_game_state: GameState, p_input: PlayerInput = null) -> void:
	game_state = p_game_state
	input = p_input if p_input else PlayerInput.new()
	check_timing = CheckTiming.new()
	dispatcher = TriggerDispatcher.new()
	destruction = DestructionEngine.new()
	mover = CardMover.new()
	monster_mover = MonsterMover.new()
	enter_zone = EnterZone.new()
	queries = EffectQueries.new()
	check_timing.game_state = game_state
	check_timing.destruction = destruction
	check_timing.h = self
	for m: EffectModule in [dispatcher, destruction, mover, monster_mover, enter_zone, queries]:
		m.wire(self)


func teardown() -> void:
	## Break the internal RefCounted reference cycles (module <-> module,
	## module.h -> self, action_handler <-> self) so the match component graph
	## can be freed once the owner drops its reference. Idempotent.
	for m: EffectModule in [dispatcher, destruction, mover, monster_mover, enter_zone, queries]:
		if m:
			m.unwire()
	if check_timing:
		check_timing.teardown()
	check_timing = null
	dispatcher = null
	destruction = null
	mover = null
	monster_mover = null
	enter_zone = null
	queries = null
	action_handler = null
	events = null
	input = null
	game_state = null



# --- Effect loading (delegates to EffectRegistry) ---

func get_effect(card_data: Dictionary) -> CardEffect:
	return registry.get_effect(card_data)



# --- Active effect highlighting while a prompt waits on a decision ---
# CheckTiming owns which ability is resolving (check_timing.active_*).

func _highlight_active_effect() -> void:
	var pid: int = check_timing.active_player_id
	if pid >= 0:
		var card_id: String = check_timing.active_card.get("id", "")
		if not card_id.is_empty():
			effect_card_highlighted.emit(pid, card_id)



func _unhighlight_active_effect() -> void:
	var pid: int = check_timing.active_player_id
	if pid >= 0:
		var card_id: String = check_timing.active_card.get("id", "")
		if not card_id.is_empty():
			effect_card_unhighlighted.emit(pid, card_id)



func reduce_rage(player_id: int, amount: int) -> int:
	## Reduce a player's rage by amount. Returns actual amount reduced.
	## Respects rage reduction prevention effects (e.g. EBP03-004).
	## Populates the player's transient pending_rage_markers bucket with one
	## RAGE-MARKER per point reduced so claiming effects (e.g. EBP04-089) can
	## pop them; whatever isn't claimed is cleared once the check timing that
	## resolves the trigger ends (CheckTiming.resolve).
	var player := game_state.players[player_id]
	if not player.has_rage() or amount <= 0:
		return 0
	if queries.is_rage_reduction_prevented(player_id):
		return 0
	var old_rage: int = player.rage
	var actual: int = mini(amount, player.rage)
	player.rage -= actual
	player.rage_changed.emit(player.rage)
	player.push_pending_rage_markers(actual)
	dispatcher.trigger_rage_changed(player_id, old_rage, player.rage)
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
	dispatcher.trigger_rage_changed(player_id, old_rage, player.rage)
	return amount



func select_zone_target(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false, card_id: String = "", max_rank: int = -1) -> int:
	## Ask a player to choose one of the valid zones on the target player's board.
	## If allow_skip is true, the player can decline (returns -1).
	## `card_id` (optional) gives the base id of the card being placed so the
	## UI can show a preview of it next to the prompt.
	## `max_rank` (> 0) tells the chooser only cards of that rank or lower
	## will be destroyed (destroy_zone_and_adjacent) — the bot scores by it.
	## Returns the chosen zone index, or -1 if no valid zones or skipped.
	if valid_zones.is_empty():
		return -1

	zone_target_card_id = card_id
	_highlight_active_effect()
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
	var zone_index: int = await input.select_zone(player_id, target_player_id, valid_zones, prompt, allow_skip, max_rank)
	_unhighlight_active_effect()
	zone_target_card_id = ""
	return zone_index



func select_zones_target(player_id: int, target_player_id: int, valid_zones: Array[int], count: int, prompt: String, up_to: bool = false, constraints: Dictionary = {}) -> Array[int]:
	## Ask a player to choose multiple zones on the target player's board.
	## Exact mode (up_to = false): the player must pick exactly `count` zones —
	## callers pass count already clamped to valid_zones.size().
	## Up-to mode (up_to = true): the player may pick any 0..count zones and an
	## empty result declines the effect.
	## `constraints` (ZoneSelectConstraints) adds extra rules, e.g. a rank
	## budget — the UI, bot, and MP host all enforce it.
	if valid_zones.is_empty() or count <= 0:
		return []

	_highlight_active_effect()
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
	var zones: Array[int] = await input.select_zones(player_id, target_player_id, valid_zones, count, up_to, prompt, constraints)
	_unhighlight_active_effect()
	return zones



func select_strategy_target(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	## Ask a player to choose one of the valid strategy zones on the target player's board.
	## Always prompts when at least one valid index exists so the player can see
	## which strategy is being targeted (no silent auto-pick on size==1).
	## Returns the chosen strategy index, or -1 if no valid indices.
	if valid_indices.is_empty():
		return -1

	_highlight_active_effect()
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
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
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
	var index: int = await input.choose_option(player_id, options, prompt)
	_unhighlight_active_effect()
	choice_card_ids = []
	choice_source_refs = []
	return index



func reveal_cards(player_id: int, cards: Array[Dictionary], title: String) -> void:
	## Show a set of cards to the player and wait for them to dismiss the overlay.
	if cards.is_empty():
		return
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
	await input.acknowledge_reveal(player_id, cards, title)



func highlight_zone_card(player_id: int, zone_index: int) -> void:
	## Highlight a zone's card to show its effect is being resolved.
	effect_zone_highlighted.emit(player_id, zone_index)



func unhighlight_zone_card(player_id: int, zone_index: int) -> void:
	## Remove highlight from a zone's card after effect resolution.
	effect_zone_unhighlighted.emit(player_id, zone_index)



func force_counter(target_player_id: int) -> void:
	## Force a successful counter against target_player_id's monster.
	## The target's monster retreats and ranks up; the other player is the winner.
	if action_handler:
		await action_handler.force_counter(game_state, target_player_id)


# --- Delegates to the engine modules (card-script primitives) ---

func trigger_all_monster_enter_abilities(player_id: int) -> void:
	dispatcher.trigger_all_monster_enter_abilities(player_id)


func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	return await destruction.destroy_zone_target(player_id, target, filter, prompt)


func destroy_zone_targets(player_id: int, target: PlayerState, filter: Callable, count: int, prompt: String, up_to: bool = false) -> Array[Dictionary]:
	return await destruction.destroy_zone_targets(player_id, target, filter, count, prompt, up_to)


func destroy_zones_within_rank_budget(player_id: int, target: PlayerState, budget: int, prompt_fmt: String = "", filter: Callable = Callable()) -> Array[Dictionary]:
	return await destruction.destroy_zones_within_rank_budget(player_id, target, budget, prompt_fmt, filter)


func destroy_chosen_zone(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String) -> Dictionary:
	return await destruction.destroy_chosen_zone(player_id, target, valid_zones, prompt)


func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	return await destruction.destroy_zones(target, zone_indices)


func destroy_zones_reporting_destroyed(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	return await destruction.destroy_zones_reporting_destroyed(target, zone_indices)


func destroy_zone_and_adjacent(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String, max_rank: int = -1) -> Array[Dictionary]:
	return await destruction.destroy_zone_and_adjacent(player_id, target, valid_zones, prompt, max_rank)


func destroy_strategy_zone(player: PlayerState, zone_index: int) -> Dictionary:
	return await destruction.destroy_strategy_zone(player, zone_index)


func discard_strategy_from_zone(player_id: int, zone_index: int, deferred_entries: Variant = null, bypass_protection: bool = false) -> Dictionary:
	return await destruction.discard_strategy_from_zone(player_id, zone_index, deferred_entries, bypass_protection)


func discard_hand_to(player_id: int, target_count: int) -> Array[Dictionary]:
	return await mover.discard_hand_to(player_id, target_count)


func search_deck(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	return await mover.search_deck(player_id, filter, prompt, allow_skip)


func arrange_deck_top(player_id: int, count: int, prompt: String) -> Dictionary:
	return await mover.arrange_deck_top(player_id, count, prompt)


func take_deck_top(player_id: int, count: int) -> Array[Dictionary]:
	return mover.take_deck_top(player_id, count)


func shuffle_cards_into_deck(player_id: int, cards: Array[Dictionary]) -> void:
	mover.shuffle_cards_into_deck(player_id, cards)


func select_cards_from_pool(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int = -1, pool_filter: Callable = Callable()) -> Array[Dictionary]:
	return await mover.select_cards_from_pool(player_id, matching, all_cards, prompt, min_count, max_count, pool_filter)


func search_discard(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	return await mover.search_discard(player_id, filter, prompt, allow_skip)


func select_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	return await mover.select_hand_card(player_id, filter, prompt, allow_skip)


func take_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	return await mover.take_hand_card(player_id, filter, prompt, allow_skip)


func choose_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	return await mover.choose_hand_card(player_id, filter, prompt, allow_skip)


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
	return mover.create_token_in_zone(player, token_id, zone_index)


func create_tokens_in_zones(player: PlayerState, token_id: String, count: int, candidate_zones: Array[int] = [], prompt_key: String = "STR_EFF_TOKEN_ZONE_FMT") -> int:
	return await mover.create_tokens_in_zones(player, token_id, count, candidate_zones, prompt_key)


func play_battle_cards_in_zones(player: PlayerState, cards: Array[Dictionary], pick_prompt: String, candidate_zones: Array[int] = [], from_discard: bool = false, max_count: int = -1) -> Array[Dictionary]:
	return await mover.play_battle_cards_in_zones(player, cards, pick_prompt, candidate_zones, from_discard, max_count)


func move_zone_card_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	mover.move_zone_card_to_deck_bottom(player, card_data)


func move_zone_stack(player: PlayerState, from_zone: int, to_zone: int) -> void:
	mover.move_zone_stack(player, from_zone, to_zone)


func swap_zones(player: PlayerState, zone_a: int, zone_b: int) -> void:
	mover.swap_zones(player, zone_a, zone_b)


func play_from_discard(player_id: int, card_data: Dictionary, zone_idx: int = -1) -> int:
	return await mover.play_from_discard(player_id, card_data, zone_idx)


func play_from_discard_or_skip(player_id: int, card_data: Dictionary, prompt: String, zone_filter: Callable = Callable()) -> int:
	return await mover.play_from_discard_or_skip(player_id, card_data, prompt, zone_filter)


func can_play_in_zone(player_id: int, zone_idx: int) -> bool:
	return mover.can_play_in_zone(player_id, zone_idx)


func play_battle_card_from_hand(player_id: int, card_data: Dictionary, zone_idx: int) -> bool:
	return mover.play_battle_card_from_hand(player_id, card_data, zone_idx)


func play_battle_card_from_deck(player_id: int, card_data: Dictionary, zone_idx: int, stack_on_top: bool = false) -> bool:
	return mover.play_battle_card_from_deck(player_id, card_data, zone_idx, stack_on_top)


func place_card_under_zone(player: PlayerState, card: Dictionary, zone_idx: int) -> void:
	mover.place_card_under_zone(player, card, zone_idx)


func place_cards_under_monster(player_id: int, cards: Array[Dictionary]) -> void:
	mover.place_cards_under_monster(player_id, cards)


func play_strategy_from_effect(player_id: int, card: Dictionary, zone_idx: int = -1) -> int:
	return mover.play_strategy_from_effect(player_id, card, zone_idx)


func move_strategy_card_under_zone(player: PlayerState, strat_idx: int, zone_idx: int) -> bool:
	return mover.move_strategy_card_under_zone(player, strat_idx, zone_idx)


func ensure_strategy_zone_count(player: PlayerState, count: int) -> bool:
	return player.ensure_strategy_zone_count(count)


func move_zone_card_under_zone(player: PlayerState, from_zone: int, to_zone: int) -> bool:
	return mover.move_zone_card_under_zone(player, from_zone, to_zone)


func return_cards_under_top_to_hand(player: PlayerState, zone_idx: int) -> Array[Dictionary]:
	return mover.return_cards_under_top_to_hand(player, zone_idx)


func get_cards_under_top(player: PlayerState, zone_idx: int) -> Array:
	return mover.get_cards_under_top(player, zone_idx)


func place_card_under_strategy_zone(player: PlayerState, card: Dictionary, strat_idx: int) -> void:
	mover.place_card_under_strategy_zone(player, card, strat_idx)


func get_cards_under_strategy_top(player: PlayerState, strat_idx: int) -> Array:
	return mover.get_cards_under_strategy_top(player, strat_idx)


func return_discard_to_hand(player_id: int, card: Dictionary) -> void:
	mover.return_discard_to_hand(player_id, card)


func add_card_to_hand(player_id: int, card: Dictionary) -> void:
	mover.add_card_to_hand(player_id, card)


func add_cards_to_hand(player_id: int, cards: Array[Dictionary]) -> void:
	mover.add_cards_to_hand(player_id, cards)


func put_card_on_top_of_deck(player_id: int, card: Dictionary) -> void:
	mover.put_card_on_top_of_deck(player_id, card)


func put_card_on_bottom_of_deck(player_id: int, card: Dictionary) -> void:
	mover.put_card_on_bottom_of_deck(player_id, card)


func shuffle_discard_into_deck(player_id: int) -> int:
	return mover.shuffle_discard_into_deck(player_id)


func advance_monster_to_zone(player_id: int, target_zone: int) -> void:
	monster_mover.advance_monster_to_zone(player_id, target_zone)


func retreat_monster_to_zone(player_id: int, target_zone: int) -> void:
	monster_mover.retreat_monster_to_zone(player_id, target_zone)


func teleport_monster(player_id: int, target_zone: int) -> bool:
	return monster_mover.teleport_monster(player_id, target_zone)


func move_monster_as_countered(player_id: int) -> void:
	monster_mover.move_monster_as_countered(player_id)


func get_threat_level_modifier(player_id: int) -> int:
	return queries.get_threat_level_modifier(player_id)


func get_effective_threat_level(player_id: int) -> int:
	return queries.get_effective_threat_level(player_id)


func can_card_be_played(player_id: int, card_data: Dictionary) -> bool:
	return queries.can_card_be_played(player_id, card_data)


func get_card_required_play_zones(player_id: int, card_data: Dictionary) -> Array[int]:
	return queries.get_card_required_play_zones(player_id, card_data)


func get_zones_in_rank_range(player_id: int, min_rank: int = -1, max_rank: int = -1) -> Array[int]:
	return queries.get_zones_in_rank_range(player_id, min_rank, max_rank)


func get_zones_in_cp_range(player_id: int, min_cp: int = -1, max_cp: int = -1) -> Array[int]:
	return queries.get_zones_in_cp_range(player_id, min_cp, max_cp)


