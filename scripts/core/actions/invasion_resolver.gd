class_name InvasionResolver
extends ActionResolver

## The INVADE action (rule 5.14), decomposed into its three phases:
##  1. pay the invasion cost (discard / replacement / invade1 block),
##  2. advance from an invasion through the monster movement module
##     (MonsterMover: per-zone crush, victory through invasion),
##  3. post-movement consequences (<Base> destruction 12.9.2, invasion
##     observers).
## Every ability the invasion triggers enters standby as it happens and
## resolves at the check timing after the action (10.4.4.1), once all
## movement is done.


func invade(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var start_zone: int = player.monster_zone

	var cost := await _pay_invasion_cost(hand_index, state)
	if not cost["paid"]:
		return

	# Advance from an invasion (5.13) through the monster movement module:
	# per-step Crush; <When invading> and monster-advance abilities enter standby.
	var is_victory: bool = monster_mover.advance(player.player_id, cost["advance_amount"], true)

	player.invasion_zones_crossed = player.monster_zone - start_zone

	if is_victory:
		state.game_over.emit(player.player_id, "STR_LOG_REASON_INVASION_VICTORY")
		return

	await _post_movement(state, start_zone)


func _pay_invasion_cost(hand_index: int, state: GameState) -> Dictionary:
	## Pay the invasion cost: discard the chosen card, or a replacement cost
	## (e.g. EBP03-004 mill). Returns {"paid": bool, "advance_amount": int};
	## on an invade1 block the card returns to hand and paid is false. The
	## discarded card's abilities enter standby.
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	var advance_amount: int = card.get("invasion_icon", 0)
	player.has_invaded_this_turn = true
	player.last_invasion_card = card

	# Check if invade1 cost is blocked by opponent (e.g. EBP04-029 Gigan R3)
	if advance_amount == 1 and effect_handler and queries.is_invade1_cost_blocked(player.player_id):
		# Card stays in hand — return it and abort invasion. Emit play_cancelled
		# so the UI restores the dragged card's hand position (matches the
		# monster-cost-cancelled flow in play_monster).
		player.insert_into_hand(hand_index, card)
		player.has_invaded_this_turn = false
		effect_handler.log_message.emit(GameLog.invade1_blocked())
		events.play_cancelled.emit(player.player_id)
		return {"paid": false, "advance_amount": 0}

	# Check for invasion cost replacement (e.g. EBP03-004: mill from deck instead)
	var replaced_cost := false
	if effect_handler and queries.can_replace_invasion_cost(player.player_id):
		var choice: int = await effect_handler.select_choice(
			player.player_id,
			[tr("STR_AH_INVADE_COST_MILL"), tr("STR_AH_INVADE_COST_HAND")] as Array[String],
			tr("STR_AH_INVADE_COST_PROMPT")
		)
		if choice == 0 and not player.main_deck.is_empty():
			# Mill from deck; return invasion card to hand
			player.insert_into_hand(hand_index, card)
			player.mill_cards(1)
			replaced_cost = true

	if not replaced_cost:
		player.add_to_discard(card)
		events.card_discarded.emit(player.player_id, card)

	# Log the invade action right after the cost is paid, before movement and triggered
	# effects fire, so the log reads in causal order (action announced first, then effects).
	if effect_handler:
		effect_handler.log_message.emit(GameLog.invaded(
			player.player_id, card.get("id", ""),
			card.get("invasion_icon", 0) >= 2))

	# Apply per-monster invasion advance bonuses (e.g. EBP04-007 Godzilla 1962: +1 on Invade 1).
	if effect_handler:
		advance_amount += queries.get_invasion_advance_bonus(player.player_id, card.get("invasion_icon", 0))

	# The discard's abilities enter standby; they resolve with the movement's
	# at the check timing after the action.
	if not replaced_cost and effect_handler:
		dispatcher.trigger_discarded_for_invasion(player.player_id, card)
		# The batch form fires both the card's own on_discard_from_hand and
		# the on_hand_card_discarded watchers.
		dispatcher.trigger_hand_cards_discarded_batch(player.player_id, [card])

	return {"paid": true, "advance_amount": advance_amount}


func _post_movement(state: GameState, start_zone: int) -> void:
	## Post-movement consequences once the monster has stopped:
	## <Base> strategy destruction (12.9.2) and invasion observers.
	var player := state.get_current_player()

	# Destroy <Base> strategies after movement completes but before standby (12.9.2).
	# Only fires when the monster actually advanced into zones 6-8 — a discard-only
	# invade (no movement) doesn't count as invading to a new zone.
	# The physical destruction happens now; strategy_discarded abilities enter standby.
	if effect_handler and player.monster_zone > start_zone and player.monster_zone >= 6:
		await destruction.destroy_base_strategies_on_invasion(player.monster_zone)

	# Invasion observers fire once for the entire invasion.
	if effect_handler and player.monster_zone > start_zone:
		dispatcher.trigger_invasion_observed(player.player_id, start_zone, player.monster_zone)
