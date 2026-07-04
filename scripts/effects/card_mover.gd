class_name CardMover
extends EffectModule

## Card traffic between hand / deck / discard / zones: prompt-driven
## searches and discards, plays from discard/hand/deck, tokens, evolution,
## zone-stack manipulation, and the add-to-hand logging helpers.



# --- Player choice helpers ---

func discard_hand_to(player_id: int, target_count: int) -> Array[Dictionary]:
	## Force a player to discard cards until they have target_count remaining.
	## The player picks which cards via the input layer (UI/RPC/bot); the
	## PlayerInput default discards from the back of hand.
	## Returns the cards that were actually discarded, so callers can react to what
	## left the hand (e.g. EBP03-010 gains rage if a battle card was discarded) without
	## a fragile before/after hand diff.
	var player := game_state.players[player_id]
	var to_discard: int = player.hand.size() - target_count
	if to_discard <= 0:
		return []

	_highlight_active_effect()
	var hand_indices: Array[int] = await input.choose_hand_discards(player_id, to_discard, player.hand.size())
	_unhighlight_active_effect()

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
	# Bundle all simultaneously-discarded triggers into one standby batch so
	# the player can choose resolution order when 2+ cards trigger (10.4.3).
	await h.trigger_hand_cards_discarded_batch(player_id, discarded_cards)
	return discarded_cards




func search_deck(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	## Search a player's deck for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from deck, deck shuffled).
	## Returns empty dict if no matches found or (when allow_skip) player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.main_deck:
		if filter.call(card):
			matching.append(card)

	_highlight_active_effect()
	var selected: Dictionary = await input.search_cards(player_id, matching, player.main_deck.duplicate(), prompt, allow_skip)
	_unhighlight_active_effect()

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




func arrange_deck_cards(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	## Present cards to the player for reordering and optional discarding.
	## Returns {"keep": Array[Dictionary], "discard": Array[Dictionary]}.
	## "keep" is ordered: first element = top of deck.
	if cards.is_empty():
		return {"keep": [], "discard": []}

	_highlight_active_effect()
	var result: Dictionary = await input.arrange_deck(player_id, cards, prompt)
	_unhighlight_active_effect()
	return result




func select_cards_from_pool(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int = -1, pool_filter: Callable = Callable()) -> Array[Dictionary]:
	## Ask a player to select between min_count and max_count cards from the matching pool.
	## If max_count == -1, it defaults to min_count (exact count required).
	## pool_filter is an optional Callable(card: Dictionary, selection: Array[Dictionary]) -> bool
	## that dynamically disables pool cards based on the current selection.
	## Player may skip (returns empty array) or must select within the count range to confirm.
	## Returns the selected cards, or empty array if skipped.
	## The caller is responsible for removing selected cards from their source.
	if max_count == -1:
		max_count = min_count
	if matching.size() < min_count:
		return []

	h._card_select_pool_filter = pool_filter
	_highlight_active_effect()
	var result: Array[Dictionary] = await input.select_cards(player_id, matching, all_cards, prompt, min_count, max_count)
	_unhighlight_active_effect()
	h._card_select_pool_filter = Callable()
	return result




func search_discard(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	## Search a player's discard pile for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from discard pile).
	## Returns empty dict if no matches found or (when allow_skip) player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.discard_pile:
		if filter.call(card):
			matching.append(card)

	# Force skip when nothing is selectable so the player gets feedback that
	# the search ran but found no valid cards (instead of a soft-locked UI
	# with nothing to click).
	var effective_skip: bool = allow_skip or matching.is_empty()

	_highlight_active_effect()
	var selected: Dictionary = await input.search_cards(player_id, matching, player.discard_pile.duplicate(), prompt, effective_skip)
	_unhighlight_active_effect()

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

	_highlight_active_effect()
	var chosen_index: int = await input.select_hand_card(player_id, valid_indices, prompt, allow_skip)
	_unhighlight_active_effect()

	if chosen_index < 0 or chosen_index >= player.hand.size():
		return {}

	var card: Dictionary = player.hand.pop_at(chosen_index)
	player.discard_pile.append(card)
	player.hand_changed.emit()
	player.discard_changed.emit()
	await h.trigger_discard_from_hand(player_id, card)
	await h.trigger_hand_card_discarded(player_id, card)
	return card




func select_from_cards(player_id: int, options: Array[Dictionary], all_visible: Array[Dictionary], prompt: String, allow_skip: bool = true) -> Dictionary:
	## Present a set of revealed cards to the player and let them choose one.
	## Uses the deck_search UI but does NOT modify the deck or shuffle.
	## When `options` is empty the reveal is still shown (the UI defaults to
	## "Show All" and skip is forced so the player can dismiss it) — "reveal"
	## effects must display the cards even with no valid targets. When
	## `allow_skip` is false the player must pick a card unless `options` is
	## empty. Returns the chosen card, or empty dict if no options or
	## (allow_skip) the player skipped.
	if all_visible.is_empty():
		return {}
	_highlight_active_effect()
	var selected: Dictionary = await input.search_cards(player_id, options, all_visible, prompt, allow_skip or options.is_empty())
	_unhighlight_active_effect()
	# Re-map the resolved selection back to the caller's own dict. In
	# multiplayer the client's pick round-trips through JSON, which converts
	# enums/ints to floats — the returned dict would no longer == the
	# originals, breaking callers that erase()/compare it (e.g. EBP04-079's
	# play-all loop). Match by id so we hand back the canonical reference.
	if not selected.is_empty():
		var selected_id: String = selected.get("id", "")
		for card in options:
			if card.get("id") == selected_id:
				return card
		for card in all_visible:
			if card.get("id") == selected_id:
				return card
	return selected


func reveal_deck_top(player_id: int, count: int, title_key: String = "STR_EFF_REVEALED_FROM_DECK_TOP") -> Array[Dictionary]:
	## Pop up to `count` cards from the top of the player's deck and present them
	## with a reveal overlay. Returns the popped cards — caller decides disposition
	## (discard, partition, play, etc.).
	var player := game_state.players[player_id]
	var revealed: Array[Dictionary] = []
	for i in range(count):
		if player.main_deck.is_empty():
			break
		revealed.append(player.main_deck.pop_front())
	if revealed.is_empty():
		return revealed
	player.deck_changed.emit()
	await h.reveal_cards(player_id, revealed, tr(title_key))
	return revealed




func discard_cards(player_id: int, cards: Array[Dictionary]) -> void:
	## Append a batch of cards to the player's discard pile and emit discard_changed.
	## For tokens or mixed batches, use banish_or_discard per-card instead.
	if cards.is_empty():
		return
	var player := game_state.players[player_id]
	for card in cards:
		player.discard_pile.append(card)
	player.discard_changed.emit()




func search_and_discard_deck_top(player_id: int, count: int, filter: Callable, prompt: String) -> Dictionary:
	## Pop up to `count` cards from the top of the player's deck and present them
	## in a search prompt. Filter-matching cards are selectable by default; the
	## non-matching cards are accessible via the "Show All" toggle in the UI so
	## the player can see the full reveal. Everything not picked is discarded.
	## Returns the picked card, or {} if there were no matches or the player skipped.
	var player := game_state.players[player_id]
	var popped: Array[Dictionary] = []
	for _i in range(count):
		if player.main_deck.is_empty():
			break
		popped.append(player.main_deck.pop_front())
	if popped.is_empty():
		return {}
	player.deck_changed.emit()

	var matching: Array[Dictionary] = []
	for card in popped:
		if filter.call(card):
			matching.append(card)

	var picked: Dictionary = await select_from_cards(player_id, matching, popped, prompt)

	var rest: Array[Dictionary] = []
	if picked.is_empty():
		rest = popped
	else:
		# Resolve picked back to the actual popped instance (the result may have
		# been round-tripped through JSON in multiplayer, losing reference identity).
		var picked_id: String = picked.get("id", "")
		var matched_one: bool = false
		for card in popped:
			if not matched_one and card.get("id", "") == picked_id:
				picked = card
				matched_one = true
				continue
			rest.append(card)
	discard_cards(player_id, rest)
	return picked




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
		tr("STR_EFF_SEARCH_EVOLVE_FMT") % evo_rank
	)

	if selected.is_empty():
		return false

	# Log the evolution
	h.log_message.emit(GameLog.evolution(player_id, zone_idx, evo_rank, zone_card.get("id", ""), selected.get("id", "")))

	h.card_evolved.emit(player_id, selected, zone_idx)
	# Mark as played through evolution for enter effects (e.g. ESD02-010)
	selected["played_through_evolution"] = true
	player.push_zone_card(zone_idx, selected)
	player.zones_changed.emit()
	await h.trigger_enter(player_id, selected, true)
	# Evolution pulls the card from the deck, so on_battle_card_played fires
	# with played_from_deck=true (e.g. EBP04-028 Gigan, EBP04-072 Sanda).
	await h.trigger_battle_card_played(player_id, selected, zone_idx, true)
	return true




func evolve_zones_in_order(player_id: int, eligible_zones: Array[int]) -> void:
	## Run perform_evolution over the given eligible zones, prompting the player to
	## choose order whenever 2+ remain. Single-eligible auto-resolves.
	var player := game_state.players[player_id]
	var remaining: Array[int] = eligible_zones.duplicate()
	while not remaining.is_empty():
		var zi: int
		if remaining.size() == 1:
			zi = remaining.pop_back()
		else:
			var options: Array[String] = []
			var option_card_ids: Array[String] = []
			for ez in remaining:
				var card := player.get_zone_top_card(ez)
				options.append(tr("STR_EFF_ZONE_OPTION_FMT") % [ez + 1, card.get("name", "?")])
				option_card_ids.append(CardUtils.base_id(card))
			var chosen: int = await h.select_choice(
				player_id, options, tr("STR_EFF_CHOOSE_EVOLVE_ZONE"), option_card_ids)
			zi = remaining.pop_at(chosen)
		await perform_evolution(player_id, zi)




func create_token_in_zone(player: PlayerState, token_id: String, zone_index: int) -> bool:
	## Create a token from CardData template and place it in the given zone.
	## Handles overload if zone is occupied. Returns true if token was placed.
	var token_data: Dictionary = CardData.get_card_by_id(token_id)
	if token_data.is_empty():
		push_warning("EffectHandler: Token not found: %s" % token_id)
		return false

	# Make a copy so each token instance is independent
	token_data = token_data.duplicate()

	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_index):
		overloaded_top = player.get_zone_top_card(zone_index)
		var destroyed_stack: Array = player.clear_zone(zone_index)
		EffectHandler.banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()

	player.push_zone_card(zone_index, token_data)
	player.zones_changed.emit()
	await h.trigger_leave_play(player.player_id, overloaded_top, zone_index)
	await h.trigger_enter(player.player_id, token_data, true)
	# Tokens are treated as normal plays — trigger battle card played effects
	# (but not considered played from hand).
	if token_data.get("card_type") == CardEnums.CardType.BATTLE:
		await h.trigger_battle_card_played(player.player_id, token_data, zone_index)
	return true




func create_tokens_in_zones(player: PlayerState, token_id: String, count: int, candidate_zones: Array[int] = [], prompt_key: String = "STR_EFF_TOKEN_ZONE_FMT") -> int:
	## Let the player select zones to place up to count tokens. Tokens can overload
	## occupied zones; when placing multiple from one effect each must go to a different
	## zone (rule 5.11.1.3). candidate_zones restricts the offered zones (e.g. adjacency);
	## when empty, any non-monster zone is allowed. prompt_key is a tr() key formatted with
	## the number of tokens still to place. Returns the number of tokens actually placed.
	var base_zones: Array[int] = candidate_zones if not candidate_zones.is_empty() else CardEffect.get_effect_play_zones(player)
	var placed: int = 0
	var used_zones: Array[int] = []
	for _i in range(count):
		var valid: Array[int] = []
		for z in base_zones:
			if z == player.monster_zone - 1:
				continue
			if z in used_zones:
				continue
			valid.append(z)
		if valid.is_empty():
			break
		var prompt: String = tr(prompt_key) % (count - placed)
		prompt += " " + tr("STR_EFF_AVAILABLE_ZONES_FMT") % _format_zone_list(valid)
		var chosen: int = await h.select_zone_target(
			player.player_id, player.player_id, valid, prompt)
		if chosen < 0:
			break
		used_zones.append(chosen)
		if await create_token_in_zone(player, token_id, chosen):
			placed += 1
	return placed




func play_battle_cards_in_zones(player: PlayerState, cards: Array[Dictionary], pick_prompt: String, candidate_zones: Array[int] = [], from_discard: bool = false, max_count: int = -1) -> Array[Dictionary]:
	## Play battle cards from `cards`, each into a DIFFERENT zone (rule 5.11.1.3).
	## The player is shown the card picker for each card (including the last, so they see
	## what they are placing) and chooses its zone; the zone prompt lists the still-
	## available zones. Cards may overload occupied zones, but no
	## zone is reused within this call. candidate_zones restricts the offered zones (e.g.
	## adjacency); empty means any non-monster zone. from_discard plays each card out of
	## the discard pile (play_from_discard) instead of the deck. max_count caps how many
	## are played (-1 = no cap). Stops when no available zone remains.
	## Returns the cards that were not played (caller decides their fate).
	var base_zones: Array[int] = candidate_zones if not candidate_zones.is_empty() else CardEffect.get_effect_play_zones(player)
	var remaining := cards.duplicate()
	var used_zones: Array[int] = []
	var played: int = 0
	while not remaining.is_empty() and (max_count < 0 or played < max_count):
		var valid: Array[int] = []
		for z in base_zones:
			if z == player.monster_zone - 1:
				continue
			if z in used_zones:
				continue
			valid.append(z)
		if valid.is_empty():
			break
		# Always present the card picker — even for the final card — so the player
		# sees which card they are about to place.
		var card: Dictionary = await h.select_from_cards(player.player_id, remaining, remaining, pick_prompt, false)
		if card.is_empty():
			card = remaining[0]   # mandatory pick — fall back to first
		remaining.erase(card)
		var prompt: String = tr("STR_EFF_PLAY_ZONES_FMT") % card.get("name", "card")
		prompt += " " + tr("STR_EFF_AVAILABLE_ZONES_FMT") % _format_zone_list(valid)
		var chosen: int = await h.select_zone_target(
			player.player_id, player.player_id, valid, prompt)
		if chosen < 0:
			chosen = valid[0]         # mandatory placement — fall back to first available
		used_zones.append(chosen)
		if from_discard:
			await h.play_from_discard(player.player_id, card, chosen)
		else:
			await h.play_battle_card_from_deck(player.player_id, card, chosen)
		played += 1
	return remaining


func _format_zone_list(zones: Array[int]) -> String:
	var labels: Array[String] = []
	for z in zones:
		labels.append(str(z + 1))
	return ", ".join(labels)




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




func move_zone_card_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	## Move a card from its zone to the bottom of the player's deck.
	## Finds the zone containing the card, removes it, and appends to deck.
	var card_id: String = card_data.get("id", "")
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if zone_card.get("id", "") == card_id:
			var stack: Array = player.clear_zone(i)
			if not stack.is_empty():
				player.main_deck.append(stack[0])
				# Place any cards under it into discard
				for j in range(1, stack.size()):
					EffectHandler.banish_or_discard(player, [stack[j]])
			player.zones_changed.emit()
			player.deck_changed.emit()
			return




func apply_play_cost(player_id: int, card_data: Dictionary, zone_index: int) -> bool:
	## Call the card's apply_play_cost hook. Returns true if play should proceed.
	var effect := get_effect(card_data)
	if not effect:
		return true
	if not has_trigger(card_data, "apply_play_cost"):
		return true
	var ctx := _build_context(player_id, card_data)
	@warning_ignore("redundant_await")
	return await effect.apply_play_cost(ctx, zone_index)




func move_zone_stack(player: PlayerState, from_zone: int, to_zone: int) -> void:
	## Move a zone's full stack to another zone, overloading any existing
	## contents at the destination per rule 11.5. No-op if the source is empty
	## or from_zone == to_zone.
	if from_zone == to_zone:
		return
	if not player.zone_has_cards(from_zone):
		return
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(to_zone):
		overloaded_top = player.get_zone_top_card(to_zone)
		var overloaded: Array = player.clear_zone(to_zone)
		EffectHandler.banish_or_discard(player, overloaded)
		player.discard_changed.emit()
	var moved_top: Dictionary = player.get_zone_top_card(from_zone)
	var stack: Array = player.zones[from_zone]
	player.zones[from_zone] = []
	player.zones[to_zone] = stack
	player.zones_changed.emit()
	# Fire on_destroy for the overloaded card, then on_zone_changed for the
	# moved card — mirrors the linked-card semantics used by swap_zones and
	# play_from_discard so cards like EBP04-067 can react to forced movement.
	await h.trigger_leave_play(player.player_id, overloaded_top, to_zone)
	if not moved_top.is_empty() and has_trigger(moved_top, "on_zone_changed"):
		var me := get_effect(moved_top)
		@warning_ignore("redundant_await")
		await me.on_zone_changed(_build_context(player.player_id, moved_top), from_zone, to_zone)




func swap_zones(player: PlayerState, zone_a: int, zone_b: int) -> void:
	## Swap two zone stacks and fire on_zone_changed for each top card that moved.
	var top_a: Dictionary = player.get_zone_top_card(zone_a)
	var top_b: Dictionary = player.get_zone_top_card(zone_b)
	var stack_a: Array = player.zones[zone_a].duplicate()
	var stack_b: Array = player.zones[zone_b].duplicate()
	player.zones[zone_a] = stack_b
	player.zones[zone_b] = stack_a
	player.zones_changed.emit()
	if not top_a.is_empty() and has_trigger(top_a, "on_zone_changed"):
		var eff := get_effect(top_a)
		@warning_ignore("redundant_await")
		await eff.on_zone_changed(_build_context(player.player_id, top_a), zone_a, zone_b)
	if not top_b.is_empty() and has_trigger(top_b, "on_zone_changed"):
		var eff := get_effect(top_b)
		@warning_ignore("redundant_await")
		await eff.on_zone_changed(_build_context(player.player_id, top_b), zone_b, zone_a)




# --- Helpers for card placement and movement ---

func play_from_discard(player_id: int, card_data: Dictionary, zone_idx: int = -1) -> int:
	## Remove a card from the discard pile and play it into a zone.
	## If zone_idx is -1, the player selects an available zone.
	## Returns the zone index where the card was placed, or -1 if cancelled.
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
		var card_name: String = card_data.get("name", "card")
		zone_idx = await h.select_zone_target(player_id, player_id, valid_zones, tr("STR_EFF_PLAY_FROM_DISCARD_ZONE_FMT") % card_name)
		if zone_idx < 0:
			# Can't skip — put back in discard as fallback
			player.discard_pile.append(card_data)
			player.discard_changed.emit()
			return -1

	# Handle overload if zone occupied
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_idx):
		overloaded_top = player.get_zone_top_card(zone_idx)
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		EffectHandler.banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()

	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	await h.trigger_leave_play(player_id, overloaded_top, zone_idx)
	await h.trigger_enter(player_id, card_data, true)
	return zone_idx




func play_from_discard_or_skip(player_id: int, card_data: Dictionary, prompt: String, zone_filter: Callable = Callable()) -> int:
	## 'May'-style helper: prompt the player for a zone (with skip), then play
	## the card from discard there. If the player skips or no zones are valid,
	## the card stays in discard and -1 is returned.
	## zone_filter is an optional Callable(zone_idx: int) -> bool to restrict
	## valid placement zones; if omitted, any non-monster zone is valid.
	var player := game_state.players[player_id]
	var monster_idx: int = player.monster_zone - 1
	var valid_zones: Array[int] = []
	for i in range(8):
		if i == monster_idx:
			continue
		if zone_filter.is_valid() and not zone_filter.call(i):
			continue
		valid_zones.append(i)
	if valid_zones.is_empty():
		return -1
	var zone_idx: int = await h.select_zone_target(
		player_id, player_id, valid_zones, prompt, true)
	if zone_idx < 0:
		return -1
	return await play_from_discard(player_id, card_data, zone_idx)




func play_battle_card_from_hand(player_id: int, card_data: Dictionary, zone_idx: int) -> void:
	## Play a battle card from the player's hand into a zone via an effect, then
	## fire enter and on_battle_card_played in the correct order. Handles zone
	## overload and logs the play attributed to the active effect. Use for
	## "add it to your hand... you may play it" effects (e.g. EBP04-077) so the
	## card's hand stop stays observable to sequencing-sensitive triggers —
	## don't stage the card in the discard pile to reuse play_from_discard.
	var player := game_state.players[player_id]
	var card_id: String = card_data.get("id", "")
	for i in range(player.hand.size() - 1, -1, -1):
		if player.hand[i].get("id", "") == card_id:
			player.hand.remove_at(i)
			break
	player.hand_changed.emit()

	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_idx):
		overloaded_top = player.get_zone_top_card(zone_idx)
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		EffectHandler.banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()
	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	h.log_message.emit(GameLog.effect_played_card(player_id, source_id, card_id, zone_idx))
	await h.trigger_leave_play(player_id, overloaded_top, zone_idx)
	await h.trigger_enter(player_id, card_data, true)
	await h.trigger_battle_card_played(player_id, card_data, zone_idx)




func play_battle_card_from_deck(player_id: int, card_data: Dictionary, zone_idx: int, stack_on_top: bool = false) -> void:
	## Place a battle card directly from the deck into a zone, then fire enter and
	## on_battle_card_played (with played_from_deck=true) in the correct order.
	## Handles zone overload. Use this instead of manual push+trigger_enter+trigger_battle_card_played
	## so that standby entry ordering is correct when called from within effect callbacks.
	## Pass stack_on_top=true for "play on top of" effects (e.g. Star Falcon placing a
	## Moguera card on top of Land Moguera) so the existing stack is preserved instead of
	## overloaded/discarded.
	var player := game_state.players[player_id]
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_idx) and not stack_on_top:
		overloaded_top = player.get_zone_top_card(zone_idx)
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		EffectHandler.banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()
	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	await h.trigger_leave_play(player_id, overloaded_top, zone_idx)
	await h.trigger_enter(player_id, card_data, true)
	await h.trigger_battle_card_played(player_id, card_data, zone_idx, true)




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




func place_card_under_strategy_zone(player: PlayerState, card: Dictionary, strat_idx: int) -> void:
	## Place a card under the top card of a strategy zone (into strategy_zone_stacks).
	## Used by EBP04-089 (Inherited Life) to track rage card placements.
	if strat_idx < 0 or strat_idx >= player.strategy_zone_stacks.size():
		return
	player.strategy_zone_stacks[strat_idx].append(card)
	player.strategy_zones_changed.emit()




func get_cards_under_strategy_top(player: PlayerState, strat_idx: int) -> Array:
	## Return cards stacked under a strategy zone's top card.
	if strat_idx < 0 or strat_idx >= player.strategy_zone_stacks.size():
		return []
	return player.strategy_zone_stacks[strat_idx]




func return_discard_to_hand(player_id: int, card: Dictionary) -> void:
	## Move a card from a player's discard pile to their hand and fire
	## on_card_returned_from_discard triggers. Safe to call when the card has already
	## been popped from discard (e.g. by search_discard) — the erase becomes a no-op.
	## Logs the return attributed to whichever effect is currently active.
	var player := game_state.players[player_id]
	var was_in_discard: bool = card in player.discard_pile
	if was_in_discard:
		player.discard_pile.erase(card)
		player.discard_changed.emit()
	player.hand.append(card)
	player.hand_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	h.log_message.emit(GameLog.effect_returned_card_to_hand(player_id, source_id, card.get("id", "")))
	await h.trigger_card_returned_from_discard(player_id, card)




func add_card_to_hand(player_id: int, card: Dictionary) -> void:
	## Add a card to a player's hand and log it, attributed to whichever effect is
	## currently active. The card must already be removed from wherever it came from
	## (deck top reveal, search result, etc.). Use this instead of a raw hand.append
	## so the add is visible in the game log. For returns from the discard pile use
	## return_discard_to_hand instead — it also fires on_card_returned_from_discard.
	var player := game_state.players[player_id]
	player.hand.append(card)
	player.hand_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	h.log_message.emit(GameLog.effect_added_card_to_hand(player_id, source_id, card.get("id", "")))




func add_cards_to_hand(player_id: int, cards: Array[Dictionary]) -> void:
	## Batch variant of add_card_to_hand: append a set of simultaneously-added cards
	## to a player's hand and log them as a single combined line. No-op when empty.
	if cards.is_empty():
		return
	var player := game_state.players[player_id]
	for card in cards:
		player.hand.append(card)
	player.hand_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	h.log_message.emit(GameLog.effect_added_cards_to_hand(player_id, source_id, cards))




func put_card_on_top_of_deck(player_id: int, card: Dictionary) -> void:
	## Place a card on top of (the front of) a player's main deck and log it,
	## attributed to whichever effect is currently active. Safe to call when the
	## card has already been popped from discard (e.g. by search_discard) — the
	## erase becomes a no-op. Fires deck_changed (and discard_changed when the card
	## was still in the discard pile). Use this instead of a raw main_deck.push_front
	## so the placement is visible in the game log.
	var player := game_state.players[player_id]
	if card in player.discard_pile:
		player.discard_pile.erase(card)
		player.discard_changed.emit()
	player.main_deck.push_front(card)
	player.deck_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	h.log_message.emit(GameLog.effect_put_card_on_top_of_deck(player_id, source_id, card.get("id", "")))




func shuffle_discard_into_deck(player_id: int) -> int:
	## Return every card from a player's discard pile to their main deck and shuffle.
	## Discard is public and the deck is private, so the move must be logged for both
	## players. Delegates to PlayerState._reshuffle_discard so the move is token-safe
	## and emits the same discard_reshuffled signal as an empty-deck draw — the board's
	## handler produces the single (clickable) log entry. Returns cards moved.
	## Use this instead of a raw main_deck.append_array + discard_pile.clear.
	return game_state.players[player_id]._reshuffle_discard().size()
