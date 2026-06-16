class_name InvasionResolver
extends ActionResolver

## The INVADE action (rule 5.14), decomposed into its three phases:
##  1. pay the invasion cost (discard / replacement / invade1 block),
##  2. advance step by step with per-zone crush and victory checks,
##  3. post-movement consequences (<Base> destruction 12.9.2, invasion
##     observers, deferred standby resolution).
## Movement fully resolves before triggered abilities activate; cards removed
## during movement (crush) are filtered from the deferred queue.


func invade(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var start_zone: int = player.monster_zone

	var cost := await _pay_invasion_cost(hand_index, state)
	if not cost["paid"]:
		return

	var deferred_entries: Array = cost["deferred_entries"]
	var is_victory: bool = await _advance(cost["advance_amount"], state, deferred_entries)

	player.invasion_zones_crossed = player.monster_zone - start_zone

	if is_victory:
		state.game_over.emit(player.player_id, "STR_LOG_REASON_INVASION_VICTORY")
		return

	await _post_movement(state, start_zone, deferred_entries)


func _pay_invasion_cost(hand_index: int, state: GameState) -> Dictionary:
	## Pay the invasion cost: discard the chosen card, or a replacement cost
	## (e.g. EBP03-004 mill). Returns {"paid": bool, "advance_amount": int,
	## "deferred_entries": Array}; on an invade1 block the card returns to
	## hand and paid is false.
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var advance_amount: int = card.get("invasion_icon", 0)
	player.has_invaded_this_turn = true
	player.last_invasion_card = card

	# Check if invade1 cost is blocked by opponent (e.g. EBP04-029 Gigan R3)
	if advance_amount == 1 and effect_handler and effect_handler.is_invade1_cost_blocked(player.player_id):
		# Card stays in hand — return it and abort invasion. Emit play_cancelled
		# so the UI restores the dragged card's hand position (matches the
		# monster-cost-cancelled flow in play_monster).
		player.hand.insert(hand_index, card)
		player.has_invaded_this_turn = false
		effect_handler.log_message.emit(tr("STR_AH_INVADE1_BLOCKED"))
		events.play_cancelled.emit(player.player_id)
		return {"paid": false, "advance_amount": 0, "deferred_entries": []}

	# Check for invasion cost replacement (e.g. EBP03-004: mill from deck instead)
	var replaced_cost := false
	if effect_handler and effect_handler.can_replace_invasion_cost(player.player_id):
		var choice: int = await effect_handler.select_choice(
			player.player_id,
			[tr("STR_AH_INVADE_COST_MILL"), tr("STR_AH_INVADE_COST_HAND")] as Array[String],
			tr("STR_AH_INVADE_COST_PROMPT")
		)
		if choice == 0 and not player.main_deck.is_empty():
			# Mill from deck; return invasion card to hand
			player.hand.insert(hand_index, card)
			player.mill_cards(1)
			replaced_cost = true

	if not replaced_cost:
		player.discard_pile.append(card)
		events.card_discarded.emit(player.player_id, card)
		player.hand_changed.emit()
		player.discard_changed.emit()

	# Log the invade action right after the cost is paid, before movement and triggered
	# effects fire, so the log reads in causal order (action announced first, then effects).
	if effect_handler:
		effect_handler.log_message.emit(GameLog.invaded(
			player.player_id, card.get("id", ""),
			card.get("invasion_icon", 0) >= 2))

	# Apply per-monster invasion advance bonuses (e.g. EBP04-007 Godzilla 1962: +1 on Invade 1).
	if effect_handler:
		advance_amount += effect_handler.get_invasion_advance_bonus(player.player_id, card.get("invasion_icon", 0))

	# Collect discard triggers for deferred resolution alongside movement effects
	var deferred_entries: Array = []
	if not replaced_cost and effect_handler:
		deferred_entries.append_array(effect_handler.collect_discarded_for_invasion_entries(player.player_id, card))
		deferred_entries.append_array(effect_handler.collect_discard_from_hand_entries(player.player_id, card))
		deferred_entries.append_array(effect_handler.collect_hand_card_discarded_entries(player.player_id, card))

	return {"paid": true, "advance_amount": advance_amount, "deferred_entries": deferred_entries}


func _advance(advance_amount: int, state: GameState, deferred_entries: Array) -> bool:
	## The step loop: one zone per step, crush checked per step (deferred),
	## when-invading / monster-advance entries collected. Returns true on
	## invasion victory (monster crossed past an undefended zone 8).
	var player := state.get_current_player()
	for _step in range(advance_amount):
		if player.monster_zone >= 8:
			# Check invasion victory
			var opponent := state.get_opponent_of_current()
			if not opponent.zone_has_battle_card(7):  # Zone 8 = index 7
				var old_zone: int = player.monster_zone
				player.monster_zone = 9  # Past zone 8
				events.monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
				player.monster_changed.emit()
				if effect_handler:
					deferred_entries.append_array(effect_handler.collect_when_invading_entries(player.player_id, old_zone, player.monster_zone))
				return true
			else:
				# Opponent's zone 8 has a battle card, can't advance further
				return false
		else:
			var old_zone: int = player.monster_zone
			player.monster_zone += 1
			events.monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
			if effect_handler:
				deferred_entries.append_array(effect_handler.collect_when_invading_entries(player.player_id, old_zone, player.monster_zone))
				deferred_entries.append_array(effect_handler.collect_monster_advance_entries(player.player_id, old_zone, player.monster_zone))
			# Check crush rule at each step (effects deferred until after movement)
			await ah.check_crush_rule(state, deferred_entries)
	return false


func _post_movement(state: GameState, start_zone: int, deferred_entries: Array) -> void:
	## Post-movement consequences once the monster has stopped:
	## <Base> strategy destruction (12.9.2), invasion observers, and the
	## deferred standby resolution.
	var player := state.get_current_player()

	# Destroy <Base> strategies after movement completes but before standby (12.9.2).
	# Only fires when the monster actually advanced into zones 6-8 — a discard-only
	# invade (no movement) doesn't count as invading to a new zone.
	# The physical destruction happens now; strategy_discarded triggers join deferred_entries.
	if effect_handler and player.monster_zone > start_zone and player.monster_zone >= 6:
		await effect_handler.destroy_base_strategies_on_invasion(player.monster_zone, deferred_entries)

	# Collect invasion observed entries once for the entire invasion
	if effect_handler and player.monster_zone > start_zone:
		deferred_entries.append_array(effect_handler.collect_invasion_observed_entries(player.player_id, start_zone, player.monster_zone))

	# Resolve deferred effects after all movement and rule actions complete
	if effect_handler and not deferred_entries.is_empty():
		await effect_handler.resolve_deferred_entries(deferred_entries)

	player.hand_changed.emit()
	player.monster_changed.emit()
	player.discard_changed.emit()
