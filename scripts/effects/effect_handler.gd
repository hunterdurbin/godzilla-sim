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
signal deck_search_requested(player_id: int, matching_cards: Array[Dictionary], prompt: String)

## Emitted internally after resolve_deck_search() stores the selection.
signal _deck_search_resolved()

var game_state: GameState
var _effect_cache: Dictionary = {}  # script_path -> CardEffect instance
var _deck_search_result: Dictionary = {}


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
		effect.on_crush(_build_context(player_id, card_data))


func trigger_revenge(player_id: int, card_data: Dictionary) -> void:
	## Trigger <Revenge> on a card being destroyed by an effect.
	var effect := get_effect(card_data)
	if effect:
		effect.on_revenge(_build_context(player_id, card_data))


func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:
	## Trigger discard-from-hand effect on the card being discarded.
	var effect := get_effect(card_data)
	if effect:
		effect.on_discard_from_hand(_build_context(player_id, card_data))


func trigger_rage_changed(player_id: int, old_rage: int, new_rage: int) -> void:
	## Trigger rage changed on all active cards for this player (monster + zones + strategies).
	var player := game_state.players[player_id]

	# Monster card
	_trigger_rage_on_card(player_id, player.current_monster, old_rage, new_rage)

	# Battle cards in zones
	for zone_card in player.zones:
		if not zone_card.is_empty():
			_trigger_rage_on_card(player_id, zone_card, old_rage, new_rage)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			_trigger_rage_on_card(player_id, sz_card, old_rage, new_rage)


func _trigger_rage_on_card(player_id: int, card_data: Dictionary, old_rage: int, new_rage: int) -> void:
	var effect := get_effect(card_data)
	if effect:
		effect.on_rage_changed(_build_context(player_id, card_data), old_rage, new_rage)


func trigger_monster_advance(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger monster advance on all active cards for this player.
	var player := game_state.players[player_id]

	# Monster card itself
	var effect := get_effect(player.current_monster)
	if effect:
		effect.on_monster_advance(_build_context(player_id, player.current_monster), from_zone, to_zone)

	# Battle cards in zones
	for zone_card in player.zones:
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				ze.on_monster_advance(_build_context(player_id, zone_card), from_zone, to_zone)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				se.on_monster_advance(_build_context(player_id, sz_card), from_zone, to_zone)


func trigger_phase_start(phase: CardEnums.GamePhase) -> void:
	## Trigger phase start on all active cards for both players.
	for player_id in range(2):
		_trigger_phase_on_all_cards(player_id, phase, true)


func trigger_phase_end(phase: CardEnums.GamePhase) -> void:
	## Trigger phase end on all active cards for both players.
	for player_id in range(2):
		_trigger_phase_on_all_cards(player_id, phase, false)


func _trigger_phase_on_all_cards(player_id: int, phase: CardEnums.GamePhase, is_start: bool) -> void:
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		if is_start:
			me.on_phase_start(_build_context(player_id, player.current_monster), phase)
		else:
			me.on_phase_end(_build_context(player_id, player.current_monster), phase)

	# Battle cards in zones
	for zone_card in player.zones:
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				if is_start:
					ze.on_phase_start(_build_context(player_id, zone_card), phase)
				else:
					ze.on_phase_end(_build_context(player_id, zone_card), phase)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				if is_start:
					se.on_phase_start(_build_context(player_id, sz_card), phase)
				else:
					se.on_phase_end(_build_context(player_id, sz_card), phase)


func trigger_monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary) -> void:
	## Trigger on_monster_played on all active cards for this player.
	var player := game_state.players[player_id]

	# Battle cards in zones
	for zone_card in player.zones:
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				ze.on_monster_played(_build_context(player_id, zone_card), old_monster, new_monster)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				se.on_monster_played(_build_context(player_id, sz_card), old_monster, new_monster)


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
		deck_search_requested.emit(player_id, matching, prompt)
		await _deck_search_resolved
		selected = _deck_search_result
	else:
		# Fallback: auto-pick first match
		selected = matching[0]

	if not selected.is_empty():
		var card_id: String = selected.get("id", "")
		for i in range(player.main_deck.size()):
			if player.main_deck[i].get("id") == card_id:
				player.main_deck.remove_at(i)
				break
	player.main_deck.shuffle()
	player.deck_changed.emit()
	return selected


func resolve_deck_search(selected_card: Dictionary) -> void:
	## Called by the presentation layer after the player selects a card from the search.
	_deck_search_result = selected_card
	_deck_search_resolved.emit()


# --- Modifier queries ---

func get_counter_power_modifier(player_id: int) -> int:
	## Get total counter power modifier from all active battle card effects.
	var player := game_state.players[player_id]
	var total: int = 0
	for zone_card in player.zones:
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(player_id, zone_card)
				if effect.can_engage(ctx):
					total += effect.get_counter_power_modifier(ctx)
	return total


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
		var zone_card: Dictionary = player.zones[i]
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				if effect.can_engage(_build_context(player_id, zone_card)):
					engageable.append(i)
			else:
				engageable.append(i)
	return engageable
