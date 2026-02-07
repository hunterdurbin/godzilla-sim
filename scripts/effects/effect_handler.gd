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

## Emitted when a player must choose a target zone on a player's board.
## Connect from presentation layer to show zone highlighting UI.
## Call resolve_zone_target() with the chosen zone index when done.
signal zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool)

## Emitted internally after resolve_zone_target() stores the selection.
signal _zone_target_resolved()

## Emitted to highlight/unhighlight a zone card during effect resolution.
signal effect_zone_highlighted(player_id: int, zone_index: int)
signal effect_zone_unhighlighted(player_id: int, zone_index: int)

var game_state: GameState
var _effect_cache: Dictionary = {}  # script_path -> CardEffect instance
var _deck_search_result: Dictionary = {}
var _zone_target_result: int = -1


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
		for i in range(to_discard):
			if player.hand.is_empty():
				break
			player.discard_pile.append(player.hand.pop_back())
		player.hand_changed.emit()
		player.discard_changed.emit()


func resolve_hand_discard(player_id: int, hand_indices: Array[int]) -> void:
	## Called by the presentation layer after the player selects cards to discard.
	## hand_indices are the indices in the player's hand to discard (sorted descending internally).
	var player := game_state.players[player_id]
	# Sort descending so removing doesn't shift indices
	var sorted_indices := hand_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		if idx >= 0 and idx < player.hand.size():
			player.discard_pile.append(player.hand.pop_at(idx))
	player.hand_changed.emit()
	player.discard_changed.emit()
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


func highlight_zone_card(player_id: int, zone_index: int) -> void:
	## Highlight a zone's card to show its effect is being resolved.
	effect_zone_highlighted.emit(player_id, zone_index)


func unhighlight_zone_card(player_id: int, zone_index: int) -> void:
	## Remove highlight from a zone's card after effect resolution.
	effect_zone_unhighlighted.emit(player_id, zone_index)


func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	## Let a player choose one of the target player's battle cards matching filter to destroy.
	## filter receives (card_data: Dictionary) -> bool for each zone's top card.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := target.get_zone_top_card(i)
		if not zone_card.is_empty() and filter.call(zone_card):
			valid_zones.append(i)

	if valid_zones.is_empty():
		return {}

	var chosen: int = await select_zone_target(player_id, target.player_id, valid_zones, prompt)
	if chosen < 0:
		return {}

	var zone_card := target.get_zone_top_card(chosen)
	if zone_card.is_empty():
		return {}

	var stack: Array = target.clear_zone(chosen)
	target.discard_pile.append_array(stack)
	target.zones_changed.emit()
	target.discard_changed.emit()
	await trigger_revenge(target.player_id, zone_card)
	return zone_card


func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	## Destroy all occupied zones in the given list on the target player's board.
	## Returns an array of the destroyed top cards. Triggers revenge on each.
	var destroyed: Array[Dictionary] = []
	for zi in zone_indices:
		if zi < 0 or zi >= 8 or target.is_zone_empty(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		var stack: Array = target.clear_zone(zi)
		target.discard_pile.append_array(stack)
		await trigger_revenge(target.player_id, top_card)
		destroyed.append(top_card)

	if not destroyed.is_empty():
		target.zones_changed.emit()
		target.discard_changed.emit()
	return destroyed


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
	## Get total counter power modifier from all active battle card effects.
	var total: int = 0
	var per_zone := get_zone_cp_modifiers(player_id)
	for mod in per_zone:
		total += mod
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
					modifiers[i] = effect.get_counter_power_modifier(ctx)
	return modifiers


func get_threat_level_modifier(player_id: int) -> int:
	## Get threat level modifier from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_threat_level_modifier(_build_context(player_id, player.current_monster))
	return 0


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
