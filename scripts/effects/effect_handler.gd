class_name EffectHandler
extends RefCounted

## Loads, caches, and dispatches card effect triggers across the game.
## Called by ActionHandler and TurnManager at appropriate trigger points.

## Emitted when a player must choose cards to discard from hand.
## Connect from presentation layer to show a selection UI.
## Call resolve_hand_discard() with the chosen hand indices when done.
signal hand_discard_requested(player_id: int, discard_count: int)

## Emitted internally after resolve_hand_discard() processes the selection.
signal _hand_discard_resolved()

## Emitted when a player must choose a card from their deck during a search effect.
## Connect from presentation layer to show a deck search selection UI.
## Call resolve_deck_search() with the chosen card when done.
signal deck_search_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String)

## Emitted internally after resolve_deck_search() stores the selection.
signal _deck_search_resolved()

## Emitted when a player must choose a specific card from their hand.
## Connect from presentation layer to show hand selection UI.
## Call resolve_hand_card_selection() with the chosen hand index when done.
signal hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool)

## Emitted internally after resolve_hand_card_selection() stores the selection.
signal _hand_card_selection_resolved()

## Emitted when a player must choose a target zone on a player's board.
## Connect from presentation layer to show zone highlighting UI.
## Call resolve_zone_target() with the chosen zone index when done.
signal zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool)

## Emitted internally after resolve_zone_target() stores the selection.
signal _zone_target_resolved()

## Emitted when a player must choose from multiple text options (e.g. "Choose one").
## Connect from presentation layer to show a choice dialog.
## Call resolve_choice() with the chosen index when done.
signal choice_requested(player_id: int, options: Array[String], prompt: String)

## Emitted internally after resolve_choice() stores the selection.
signal _choice_resolved()

## Emitted to highlight/unhighlight a zone card during effect resolution.
signal effect_zone_highlighted(player_id: int, zone_index: int)
signal effect_zone_unhighlighted(player_id: int, zone_index: int)

var game_state: GameState
var action_handler  # ActionHandler reference (set by TurnManager)
var _effect_cache: Dictionary = {}  # script_path -> CardEffect instance
var _deck_search_result: Dictionary = {}
var _zone_target_result: int = -1
var _hand_card_selection_result: int = -1
var _choice_result: int = -1


func setup(p_game_state: GameState) -> void:
	game_state = p_game_state


# --- Effect loading ---

func get_effect(card_data: Dictionary) -> CardEffect:
	## Load and cache a CardEffect for the given card. Returns null if no effect script.
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return null

	if _effect_cache.has(script_path):
		return _effect_cache[script_path]

	if not ResourceLoader.exists(script_path):
		push_warning("EffectHandler: Effect script not found: %s" % script_path)
		return null

	var script: GDScript = load(script_path)
	if script == null:
		push_warning("EffectHandler: Failed to load effect script: %s" % script_path)
		return null

	var effect: CardEffect = script.new()
	_effect_cache[script_path] = effect
	return effect


func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return EffectContext.create(game_state, owner_id, card_data, self)


# --- Trigger dispatchers ---

func trigger_enter(player_id: int, card_data: Dictionary) -> void:
	## Trigger <Enter> effect on the card that just entered play.
	var effect := get_effect(card_data)
	if effect:
		await effect.on_enter(_build_context(player_id, card_data))


func trigger_when_invading(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger <When Invading> on the current monster card.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		await effect.on_when_invading(_build_context(player_id, player.current_monster), from_zone, to_zone)


func trigger_crush(player_id: int, card_data: Dictionary) -> void:
	## Trigger crush effect on a card being destroyed by the crush rule.
	var effect := get_effect(card_data)
	if effect:
		await effect.on_crush(_build_context(player_id, card_data))


func trigger_revenge(player_id: int, card_data: Dictionary) -> void:
	## Trigger <Revenge> on a card being destroyed by an effect.
	var effect := get_effect(card_data)
	if effect:
		await effect.on_revenge(_build_context(player_id, card_data))


func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:
	## Trigger discard-from-hand effect on the card being discarded.
	var effect := get_effect(card_data)
	if effect:
		await effect.on_discard_from_hand(_build_context(player_id, card_data))


func trigger_burst_discard(player_id: int, card_data: Dictionary) -> void:
	## Trigger on_burst_discard on the Burst monster being discarded at end of turn.
	var effect := get_effect(card_data)
	if effect:
		await effect.on_burst_discard(_build_context(player_id, card_data))


func trigger_rage_changed(player_id: int, old_rage: int, new_rage: int) -> void:
	## Trigger rage changed on all active cards for this player (monster + zones + strategies).
	var player := game_state.players[player_id]

	# Monster card
	await _trigger_rage_on_card(player_id, player.current_monster, old_rage, new_rage)

	# Battle cards in zones (top card only — stacked cards are inactive per 12.7.3)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			await _trigger_rage_on_card(player_id, zone_card, old_rage, new_rage)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			await _trigger_rage_on_card(player_id, sz_card, old_rage, new_rage)


func _trigger_rage_on_card(player_id: int, card_data: Dictionary, old_rage: int, new_rage: int) -> void:
	var effect := get_effect(card_data)
	if effect:
		await effect.on_rage_changed(_build_context(player_id, card_data), old_rage, new_rage)


func trigger_monster_advance(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger monster advance on all active cards for this player.
	var player := game_state.players[player_id]

	# Monster card itself
	var effect := get_effect(player.current_monster)
	if effect:
		await effect.on_monster_advance(_build_context(player_id, player.current_monster), from_zone, to_zone)

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_monster_advance(_build_context(player_id, zone_card), from_zone, to_zone)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				await se.on_monster_advance(_build_context(player_id, sz_card), from_zone, to_zone)


func trigger_phase_start(phase: CardEnums.GamePhase) -> void:
	## Trigger phase start on all active cards for both players.
	for player_id in range(2):
		await _trigger_phase_on_all_cards(player_id, phase, true)


func trigger_phase_end(phase: CardEnums.GamePhase) -> void:
	## Trigger phase end on all active cards for both players.
	for player_id in range(2):
		await _trigger_phase_on_all_cards(player_id, phase, false)


func _trigger_phase_on_all_cards(player_id: int, phase: CardEnums.GamePhase, is_start: bool) -> void:
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		if is_start:
			await me.on_phase_start(_build_context(player_id, player.current_monster), phase)
		else:
			await me.on_phase_end(_build_context(player_id, player.current_monster), phase)

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				if is_start:
					await ze.on_phase_start(_build_context(player_id, zone_card), phase)
				else:
					await ze.on_phase_end(_build_context(player_id, zone_card), phase)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				if is_start:
					await se.on_phase_start(_build_context(player_id, sz_card), phase)
				else:
					await se.on_phase_end(_build_context(player_id, sz_card), phase)


func trigger_monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary) -> void:
	## Trigger on_monster_played on all active cards for this player.
	var player := game_state.players[player_id]
	var triggered_ids: Array[String] = []

	# Battle cards in zones (top card only)
	# Track triggered IDs because effects can move cards to new zones during iteration.
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var card_id: String = zone_card.get("id", "")
			if card_id in triggered_ids:
				continue
			triggered_ids.append(card_id)
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_monster_played(_build_context(player_id, zone_card), old_monster, new_monster)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				await se.on_monster_played(_build_context(player_id, sz_card), old_monster, new_monster)

	# Check discard pile for cards that can play from discard on monster played
	var discard_copy: Array[Dictionary] = player.discard_pile.duplicate()
	for discard_card in discard_copy:
		var de := get_effect(discard_card)
		if de:
			var ctx := _build_context(player_id, discard_card)
			if de.can_play_from_discard_on_monster_played(ctx):
				await play_from_discard(player_id, discard_card)


func trigger_battle_card_played(player_id: int, card_data: Dictionary, zone_index: int) -> void:
	## Trigger on_battle_card_played on all active cards for this player.
	## Called after a battle card is placed in a zone and its enter effect resolves.
	var player := game_state.players[player_id]

	# Strategy cards (e.g. EBP02-073 Bloody Chainsaw)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				await se.on_battle_card_played(_build_context(player_id, sz_card), zone_index)

	# Battle cards in zones (top card only, skip the card that was just played)
	var played_id: String = card_data.get("id", "")
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("id", "") != played_id:
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_battle_card_played(_build_context(player_id, zone_card), zone_index)


func trigger_hand_card_discarded(player_id: int, card_data: Dictionary) -> void:
	## Trigger on ALL active cards when a card is discarded from the owner's hand.
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		await me.on_hand_card_discarded(_build_context(player_id, player.current_monster), card_data)

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_hand_card_discarded(_build_context(player_id, zone_card), card_data)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				await se.on_hand_card_discarded(_build_context(player_id, sz_card), card_data)


func trigger_counter_success(defender_player_id: int) -> void:
	## Trigger on ALL active cards for the defender when counter succeeds (CP >= threat).
	var player := game_state.players[defender_player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		await me.on_counter_success(_build_context(defender_player_id, player.current_monster))

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_counter_success(_build_context(defender_player_id, zone_card))

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				await se.on_counter_success(_build_context(defender_player_id, sz_card))


func trigger_strategy_discarded(player_id: int, strategy_card: Dictionary) -> void:
	## Trigger on ALL active cards when a strategy card is sent from strategy zone to discard.
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		await me.on_strategy_discarded(_build_context(player_id, player.current_monster), strategy_card)

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				await ze.on_strategy_discarded(_build_context(player_id, zone_card), strategy_card)

	# Strategy cards (skip the card being discarded)
	var discarded_id: String = strategy_card.get("id", "")
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("id", "") != discarded_id:
			var se := get_effect(sz_card)
			if se:
				await se.on_strategy_discarded(_build_context(player_id, sz_card), strategy_card)


func trigger_invasion_observed(invading_player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger on ALL active cards for BOTH players when a monster invades.
	for pid in range(2):
		var player := game_state.players[pid]

		# Monster card
		var me := get_effect(player.current_monster)
		if me:
			await me.on_invasion_observed(_build_context(pid, player.current_monster), invading_player_id, from_zone, to_zone)

		# Battle cards in zones (top card only)
		for i in range(8):
			var zone_card := player.get_zone_top_card(i)
			if not zone_card.is_empty():
				var ze := get_effect(zone_card)
				if ze:
					await ze.on_invasion_observed(_build_context(pid, zone_card), invading_player_id, from_zone, to_zone)

		# Strategy cards
		for sz_card in player.strategy_zones:
			if not sz_card.is_empty():
				var se := get_effect(sz_card)
				if se:
					await se.on_invasion_observed(_build_context(pid, sz_card), invading_player_id, from_zone, to_zone)


# --- Player choice helpers ---

func discard_hand_to(player_id: int, target_count: int) -> void:
	## Force a player to discard cards until they have target_count remaining.
	## If hand_discard_requested is connected (UI present), the player chooses which cards.
	## Otherwise falls back to discarding from the back of hand.
	var player := game_state.players[player_id]
	var to_discard: int = player.hand.size() - target_count
	if to_discard <= 0:
		return

	if hand_discard_requested.get_connections().size() > 0:
		hand_discard_requested.emit(player_id, to_discard)
		await _hand_discard_resolved
	else:
		# Fallback: discard from back of hand
		var discarded_cards: Array[Dictionary] = []
		for i in range(to_discard):
			if player.hand.is_empty():
				break
			var card: Dictionary = player.hand.pop_back()
			player.discard_pile.append(card)
			discarded_cards.append(card)
		player.hand_changed.emit()
		player.discard_changed.emit()
		for card in discarded_cards:
			await trigger_hand_card_discarded(player_id, card)


func resolve_hand_discard(player_id: int, hand_indices: Array[int]) -> void:
	## Called by the presentation layer after the player selects cards to discard.
	## hand_indices are the indices in the player's hand to discard (sorted descending internally).
	var player := game_state.players[player_id]
	var discarded_cards: Array[Dictionary] = []
	# Sort descending so removing doesn't shift indices
	var sorted_indices := hand_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		if idx >= 0 and idx < player.hand.size():
			var card: Dictionary = player.hand.pop_at(idx)
			player.discard_pile.append(card)
			discarded_cards.append(card)
	player.hand_changed.emit()
	player.discard_changed.emit()
	# Trigger hand card discarded for each card (after all are removed)
	for card in discarded_cards:
		await trigger_hand_card_discarded(player_id, card)
	_hand_discard_resolved.emit()


func search_deck(player_id: int, filter: Callable, prompt: String) -> Dictionary:
	## Search a player's deck for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from deck, deck shuffled).
	## Returns empty dict if no matches found or player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.main_deck:
		if filter.call(card):
			matching.append(card)

	if matching.is_empty():
		return {}

	var selected: Dictionary = {}
	if deck_search_requested.get_connections().size() > 0:
		deck_search_requested.emit(player_id, matching, player.main_deck.duplicate(), prompt)
		await _deck_search_resolved
		selected = _deck_search_result
	else:
		# Fallback: auto-pick first match
		selected = matching[0]

	if not selected.is_empty():
		# Look up the original card from the deck (the resolved selection may have come
		# through JSON in multiplayer, which converts enums/ints to floats)
		var card_id: String = selected.get("id", "")
		for i in range(player.main_deck.size()):
			if player.main_deck[i].get("id") == card_id:
				selected = player.main_deck[i]
				player.main_deck.remove_at(i)
				break
	player.main_deck.shuffle()
	player.deck_changed.emit()
	return selected


func resolve_deck_search(selected_card: Dictionary) -> void:
	## Called by the presentation layer after the player selects a card from the search.
	_deck_search_result = selected_card
	_deck_search_resolved.emit()


func select_zone_target(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false) -> int:
	## Ask a player to choose one of the valid zones on the target player's board.
	## If allow_skip is true, the player can decline (returns -1).
	## Returns the chosen zone index, or -1 if no valid zones or skipped.
	if valid_zones.is_empty():
		return -1

	if zone_target_requested.get_connections().size() > 0:
		zone_target_requested.emit(player_id, target_player_id, valid_zones, prompt, allow_skip)
		await _zone_target_resolved
		return _zone_target_result
	else:
		# Fallback: auto-pick first valid zone
		return valid_zones[0]


func resolve_zone_target(zone_index: int) -> void:
	## Called by the presentation layer after the player selects a target zone.
	_zone_target_result = zone_index
	_zone_target_resolved.emit()


func search_discard(player_id: int, filter: Callable, prompt: String) -> Dictionary:
	## Search a player's discard pile for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from discard pile).
	## Returns empty dict if no matches found or player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.discard_pile:
		if filter.call(card):
			matching.append(card)

	if matching.is_empty():
		return {}

	var selected: Dictionary = {}
	if deck_search_requested.get_connections().size() > 0:
		deck_search_requested.emit(player_id, matching, player.discard_pile.duplicate(), prompt)
		await _deck_search_resolved
		selected = _deck_search_result
	else:
		# Fallback: auto-pick first match
		selected = matching[0]

	if not selected.is_empty():
		# Look up the original card from discard pile by ID
		var card_id: String = selected.get("id", "")
		for i in range(player.discard_pile.size()):
			if player.discard_pile[i].get("id") == card_id:
				selected = player.discard_pile[i]
				player.discard_pile.remove_at(i)
				break
	player.discard_changed.emit()
	return selected


func select_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	## Ask a player to choose a card from their hand matching filter.
	## The selected card is removed from hand and added to discard pile.
	## Returns the selected card, or empty dict if no valid cards or player skips.
	var player := game_state.players[player_id]
	var valid_indices: Array[int] = []
	for i in range(player.hand.size()):
		if filter.call(player.hand[i]):
			valid_indices.append(i)

	if valid_indices.is_empty():
		return {}

	var chosen_index: int = -1
	if hand_card_selection_requested.get_connections().size() > 0:
		hand_card_selection_requested.emit(player_id, valid_indices, prompt, allow_skip)
		await _hand_card_selection_resolved
		chosen_index = _hand_card_selection_result
	else:
		# Fallback: auto-pick first valid
		chosen_index = valid_indices[0]

	if chosen_index < 0 or chosen_index >= player.hand.size():
		return {}

	var card: Dictionary = player.hand.pop_at(chosen_index)
	player.discard_pile.append(card)
	player.hand_changed.emit()
	player.discard_changed.emit()
	await trigger_hand_card_discarded(player_id, card)
	return card


func resolve_hand_card_selection(hand_index: int) -> void:
	## Called by the presentation layer after the player selects a card from hand.
	_hand_card_selection_result = hand_index
	_hand_card_selection_resolved.emit()


func select_from_cards(player_id: int, options: Array[Dictionary], all_visible: Array[Dictionary], prompt: String) -> Dictionary:
	## Present a set of revealed cards to the player and let them choose one.
	## Uses the deck_search UI but does NOT modify the deck or shuffle.
	## Returns the chosen card, or empty dict if no options or no UI connected.
	if options.is_empty():
		return {}

	if deck_search_requested.get_connections().size() > 0:
		deck_search_requested.emit(player_id, options, all_visible, prompt)
		await _deck_search_resolved
		return _deck_search_result
	else:
		return options[0]


func select_choice(player_id: int, options: Array[String], prompt: String) -> int:
	## Present multiple text options to the player and let them choose one.
	## Returns the chosen index (0-based), or 0 as fallback if no UI connected.
	if options.is_empty():
		return -1

	if choice_requested.get_connections().size() > 0:
		choice_requested.emit(player_id, options, prompt)
		await _choice_resolved
		return _choice_result
	else:
		# Fallback: auto-pick first option
		return 0


func resolve_choice(index: int) -> void:
	## Called by the presentation layer after the player selects a choice option.
	_choice_result = index
	_choice_resolved.emit()


func perform_evolution(player_id: int, zone_idx: int) -> bool:
	## Perform Evolution on the battle card in the given zone.
	## Reads evolution_rank and evolution_trait from the zone's top card,
	## searches deck for a matching battle card, and stacks it on top.
	## Returns true if evolution occurred.
	var player := game_state.players[player_id]
	var zone_card := player.get_zone_top_card(zone_idx)
	if zone_card.is_empty():
		return false

	var evo_rank: int = zone_card.get("evolution_rank", -1)
	var evo_trait: int = zone_card.get("evolution_trait", -1)
	if evo_rank < 0 or evo_trait < 0:
		return false

	var selected := await search_deck(
		player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			if card.get("rank", 0) > evo_rank:
				return false
			var traits: Array = card.get("traits", [])
			return evo_trait in traits,
		"Search for a rank %d or lower battle card to evolve into:" % evo_rank
	)

	if selected.is_empty():
		return false

	# Mark as played through evolution for enter effects (e.g. ESD02-010)
	selected["played_through_evolution"] = true
	player.push_zone_card(zone_idx, selected)
	player.zones_changed.emit()
	await trigger_enter(player_id, selected)
	return true


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


func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	## Let a player choose one of the target player's battle cards matching filter to destroy.
	## filter receives (card_data: Dictionary) -> bool for each zone's top card.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := target.get_zone_top_card(i)
		if not zone_card.is_empty() and filter.call(zone_card):
			# Check destroy prevention
			if not _can_destroy_card(target, zone_card):
				continue
			valid_zones.append(i)

	if valid_zones.is_empty():
		return {}

	var chosen: int = await select_zone_target(player_id, target.player_id, valid_zones, prompt)
	if chosen < 0:
		return {}

	var zone_card := target.get_zone_top_card(chosen)
	if zone_card.is_empty():
		return {}

	return await _execute_destroy_zone(target, chosen, zone_card)


func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	## Destroy all occupied zones in the given list on the target player's board.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns an array of the destroyed top cards. Triggers revenge on each.
	var destroyed: Array[Dictionary] = []
	for zi in zone_indices:
		if zi < 0 or zi >= 8 or target.is_zone_empty(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		if not _can_destroy_card(target, top_card):
			continue
		var result: Dictionary = await _execute_destroy_zone(target, zi, top_card)
		if not result.is_empty():
			destroyed.append(result)

	if not destroyed.is_empty():
		target.zones_changed.emit()
		target.discard_changed.emit()
	return destroyed


func _can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	## Check if a card can be destroyed (respects destroy prevention effects).
	var effect := get_effect(card_data)
	if effect and not effect.can_be_destroyed(_build_context(target.player_id, card_data)):
		return false
	return true


func _execute_destroy_zone(target: PlayerState, zone_idx: int, top_card: Dictionary) -> Dictionary:
	## Execute destruction of a single zone, handling replacement effects.
	## Returns the destroyed/replaced card, or empty dict on failure.
	var effect := get_effect(top_card)
	if effect and effect.on_would_be_destroyed(_build_context(target.player_id, top_card)):
		# Replacement: move to deck bottom instead of discard (skip revenge)
		var replaced_stack: Array = target.clear_zone(zone_idx)
		if replaced_stack.size() > 1:
			banish_or_discard(target, replaced_stack.slice(1))
		target.main_deck.append(top_card)
		target.zones_changed.emit()
		target.deck_changed.emit()
		target.discard_changed.emit()
		return top_card

	var stack: Array = target.clear_zone(zone_idx)
	banish_or_discard(target, stack)
	target.zones_changed.emit()
	target.discard_changed.emit()
	target.cards_destroyed_this_turn.append(top_card)
	await trigger_revenge(target.player_id, top_card)
	return top_card


func create_token_in_zone(player: PlayerState, token_id: String, zone_index: int) -> bool:
	## Create a token from CardData template and place it in the given zone.
	## Handles overload if zone is occupied. Returns true if token was placed.
	var token_data: Dictionary = CardData.get_card_by_id(token_id)
	if token_data.is_empty():
		push_warning("EffectHandler: Token not found: %s" % token_id)
		return false

	# Make a copy so each token instance is independent
	token_data = token_data.duplicate()

	if not player.is_zone_empty(zone_index):
		var destroyed_stack: Array = player.clear_zone(zone_index)
		var top_card: Dictionary = destroyed_stack[0]
		banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()
		await trigger_revenge(player.player_id, top_card)

	player.push_zone_card(zone_index, token_data)
	player.zones_changed.emit()
	await trigger_enter(player.player_id, token_data)
	return true


func create_tokens_in_empty_zones(player: PlayerState, token_id: String, count: int) -> int:
	## Let the player select empty zones to place up to count tokens.
	## Returns the number of tokens actually placed.
	var placed: int = 0
	for _i in range(count):
		var empty := player.get_empty_zone_indices()
		if empty.is_empty():
			break
		var chosen: int = await select_zone_target(
			player.player_id, player.player_id, empty,
			"Choose an empty zone for a token (%d remaining):" % (count - placed))
		if chosen < 0:
			break
		if await create_token_in_zone(player, token_id, chosen):
			placed += 1
	return placed


func return_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	## Move a card from discard pile to the bottom of the player's deck.
	## Used by cards with "place on bottom of deck instead of discard" effects.
	var card_id: String = card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = player.discard_pile.pop_at(i)
			player.main_deck.append(card)
			player.deck_changed.emit()
			player.discard_changed.emit()
			return


# --- Modifier queries ---

func get_counter_power_modifier(player_id: int) -> int:
	## Get total counter power modifier from all active effects (zones + strategies).
	var total: int = 0
	var per_zone := get_zone_cp_modifiers(player_id)
	for mod in per_zone:
		total += mod

	# Strategy card flat CP modifiers (e.g. EBP02-017)
	var player := game_state.players[player_id]
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				total += effect.get_counter_power_modifier(_build_context(player_id, sz_card))

	return total


func get_zone_cp_modifiers(player_id: int) -> Array[int]:
	## Get per-zone counter power modifiers from battle card effects.
	var player := game_state.players[player_id]
	var modifiers: Array[int] = []
	modifiers.resize(8)
	modifiers.fill(0)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(player_id, zone_card)
				if effect.can_engage(ctx):
					modifiers[i] += effect.get_counter_power_modifier(ctx)
				# Collect field modifiers (bonuses this card grants to other zones)
				var field_mods: Dictionary = effect.get_field_cp_modifiers(ctx)
				for zone_idx in field_mods:
					if zone_idx >= 0 and zone_idx < 8:
						modifiers[zone_idx] += field_mods[zone_idx]

	# Monster card field CP modifiers (e.g. EBP02-021, 041, 043)
	var monster_effect := get_effect(player.current_monster)
	if monster_effect:
		var monster_ctx := _build_context(player_id, player.current_monster)
		var monster_field_mods: Dictionary = monster_effect.get_field_cp_modifiers(monster_ctx)
		for zone_idx in monster_field_mods:
			if zone_idx >= 0 and zone_idx < 8:
				modifiers[zone_idx] += monster_field_mods[zone_idx]

	# Opponent's monster CP modifiers that affect this player's zones (e.g. EBP02-029 CP doubling)
	var opponent_id: int = 1 - player_id
	var opp_monster_effect := get_effect(game_state.players[opponent_id].current_monster)
	if opp_monster_effect:
		var opp_ctx := _build_context(opponent_id, game_state.players[opponent_id].current_monster)
		var opp_mods: Dictionary = opp_monster_effect.get_opponent_zone_cp_modifiers(opp_ctx)
		for zone_idx in opp_mods:
			if zone_idx >= 0 and zone_idx < 8:
				modifiers[zone_idx] += opp_mods[zone_idx]

	return modifiers


func get_threat_level_modifier(player_id: int) -> int:
	## Get threat level modifier from all active effects (monster, zones, strategies).
	var total: int = 0
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		total += me.get_threat_level_modifier(_build_context(player_id, player.current_monster))

	# Battle cards in zones (e.g. Crystal tokens grant +1000 TL)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				total += ze.get_threat_level_modifier(_build_context(player_id, zone_card))

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				total += se.get_threat_level_modifier(_build_context(player_id, sz_card))

	return total


func get_play_rank_modifier(player_id: int, card: Dictionary) -> int:
	## Get total play rank modifier for a card being played from hand.
	## Checks the card's own effect (self-modifier) and active strategy cards.
	var total: int = 0
	var player := game_state.players[player_id]

	# Check the card's own effect (self-modifier, e.g. EBP02-068)
	var card_effect := get_effect(card)
	if card_effect:
		total += card_effect.get_play_rank_modifier_for_card(_build_context(player_id, card), card)

	# Check active strategy cards (e.g. EBP02-039)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				total += effect.get_play_rank_modifier_for_card(_build_context(player_id, sz_card), card)

	return total


func is_invasion_blocked(defender_player_id: int) -> bool:
	## Check if any of the defender's battle cards prevent the opponent from invading.
	var player := game_state.players[defender_player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(defender_player_id, zone_card)
				if effect.prevents_opponent_invasion(ctx):
					return true
	return false


func get_cards_that_can_engage(player_id: int) -> Array[int]:
	## Return zone indices of battle cards that can engage (not blocked by "cannot engage" effects).
	## Used during counter phase to filter out restricted cards.
	var player := game_state.players[player_id]
	var engageable: Array[int] = []
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				if effect.can_engage(_build_context(player_id, zone_card)):
					engageable.append(i)
			else:
				engageable.append(i)
	return engageable


func get_opponent_blocked_zones(blocker_player_id: int) -> Array[int]:
	## Collect all opponent zone indices that the blocker's cards prevent placement in.
	## Queries monster card for get_blocked_opponent_zones().
	var player := game_state.players[blocker_player_id]
	var blocked: Array[int] = []

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		var monster_blocked: Array[int] = me.get_blocked_opponent_zones(_build_context(blocker_player_id, player.current_monster))
		for z in monster_blocked:
			if z not in blocked:
				blocked.append(z)

	# Zone cards
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				var zone_blocked: Array[int] = ze.get_blocked_opponent_zones(_build_context(blocker_player_id, zone_card))
				for z in zone_blocked:
					if z not in blocked:
						blocked.append(z)

	return blocked


func get_extra_end_phase_advance(player_id: int) -> int:
	## Get extra end phase advance zones from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_extra_end_phase_advance(_build_context(player_id, player.current_monster))
	return 0


func is_monster_advance_blocked(player_id: int) -> bool:
	## Check if the player's current monster cannot advance (e.g. Biollante Rose Form).
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return not effect.can_monster_advance(_build_context(player_id, player.current_monster))
	return false


func is_own_invasion_blocked(player_id: int) -> bool:
	## Check if the player's current monster or strategy cards prevent invasion.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		if not effect.can_monster_invade(_build_context(player_id, player.current_monster)):
			return true

	# Check strategy cards for prevents_own_invasion
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se and se.prevents_own_invasion(_build_context(player_id, sz_card)):
				return true

	return false


func get_counter_immunity_threshold(player_id: int) -> int:
	## Get the counter immunity threshold from the player's current monster.
	## If defender's CP <= this value, monster retreats without rank up.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_counter_immunity_threshold(_build_context(player_id, player.current_monster))
	return 0


func are_opponent_strategy_plays_blocked(player_id: int) -> bool:
	## Check if the opponent of the given player has cards that block strategy plays.
	## player_id is the player trying to play a strategy card.
	var opponent_id: int = 1 - player_id
	var opponent := game_state.players[opponent_id]

	# Check opponent's strategy cards
	for sz_card in opponent.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				if effect.blocks_opponent_strategy_plays(_build_context(opponent_id, sz_card)):
					return true

	# Check opponent's zone cards
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				if ze.blocks_opponent_strategy_plays(_build_context(opponent_id, zone_card)):
					return true

	return false


func force_counter(player_id: int) -> void:
	## Force a successful counter of the opponent's monster.
	## Used by EBP02-012 Godzilla(2016) Frozen.
	if action_handler:
		action_handler.force_counter(game_state, player_id)


func get_strategy_discard_interceptor(player_id: int) -> int:
	## Check if any zone card can intercept strategy discards (e.g. EBP02-012 in zone 8).
	## Returns the zone index (0-indexed) of the intercepting card, or -1 if none.
	var player := game_state.players[player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect and effect.can_intercept_strategy_discard(_build_context(player_id, zone_card)):
				return i
	return -1


func get_opponent_field_rank_modifier(player_id: int) -> int:
	## Get the field rank reduction applied to opponent's in-play battle cards.
	## Queries the player's current monster effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_opponent_field_rank_modifier(_build_context(player_id, player.current_monster))
	return 0


func get_effective_field_rank(card_data: Dictionary, owner_player_id: int) -> int:
	## Get the effective rank of an in-play battle card, accounting for opponent field rank modifiers.
	var base_rank: int = card_data.get("rank", 0)
	var opponent_id: int = 1 - owner_player_id
	var modifier: int = get_opponent_field_rank_modifier(opponent_id)
	return maxi(1, base_rank + modifier)


# --- Helpers for card placement and movement ---

func play_from_discard(player_id: int, card_data: Dictionary, zone_idx: int = -1) -> void:
	## Remove a card from the discard pile and play it into a zone.
	## If zone_idx is -1, the player selects an available zone.
	var player := game_state.players[player_id]

	# Remove from discard
	var card_id: String = card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			player.discard_pile.remove_at(i)
			break
	player.discard_changed.emit()

	# Select zone if not specified
	if zone_idx < 0:
		var valid_zones: Array[int] = []
		for i in range(8):
			if i != player.monster_zone - 1:  # Can't play in own monster zone
				valid_zones.append(i)
		zone_idx = await select_zone_target(player_id, player_id, valid_zones, "Choose a zone to play from discard:")
		if zone_idx < 0:
			# Can't skip — put back in discard as fallback
			player.discard_pile.append(card_data)
			player.discard_changed.emit()
			return

	# Handle overload if zone occupied
	if not player.is_zone_empty(zone_idx):
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		var top_card: Dictionary = destroyed_stack[0]
		banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()
		await trigger_revenge(player.player_id, top_card)

	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	await trigger_enter(player_id, card_data)


func place_card_under_zone(player: PlayerState, card: Dictionary, zone_idx: int) -> void:
	## Place a card under the top card of a zone (into the zone stack below the top).
	if zone_idx < 0 or zone_idx >= 8:
		return
	player.zones[zone_idx].append(card)
	player.zones_changed.emit()


func get_cards_under_top(player: PlayerState, zone_idx: int) -> Array:
	## Return the zone stack excluding the top card (cards stacked under).
	if zone_idx < 0 or zone_idx >= 8:
		return []
	var stack: Array = player.zones[zone_idx]
	if stack.size() <= 1:
		return []
	return stack.slice(1)
