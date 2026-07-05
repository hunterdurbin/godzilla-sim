class_name PlayActions
extends ActionResolver

## Main-phase card plays: battle cards, strategies, rage gain, monster plays
## (normal / burst / alternate-cost), and effect-driven monster plays.


func play_battle_card(hand_index: int, zone_index: int, state: GameState) -> void:
	var player := state.get_current_player()

	var card: Dictionary = player.hand.pop_at(hand_index)

	# Apply optional play costs (e.g., ESC01-001 discard a Godzilla card for rank reduction)
	if effect_handler:
		var proceed: bool = await effect_handler.apply_play_cost(player.player_id, card, zone_index)
		if not proceed:
			# Cost declined — restore card to hand and force visual rebuild
			player.hand.insert(mini(hand_index, player.hand.size()), card)
			player.hand_changed.emit()
			events.play_cancelled.emit(player.player_id)
			return

	# Rule 11.5 - Overloaded Cards: if zone is occupied, destroy existing cards
	# Unless the card's effect says to stack on top (e.g. Godzilla Jr. on Little Godzilla)
	if player.zone_has_cards(zone_index):
		var should_stack := false
		if effect_handler:
			should_stack = effect_handler.should_stack_on_play(player.player_id, card, zone_index)
		if not should_stack:
			# Overload IS <Destroy> (rule 11.5.1): on_would_be_destroyed
			# replacements apply, but revenge never fires (12.7.2 excludes
			# duplicate-card processing). on_leave_play fires either way so
			# linked-card effects clean up.
			if effect_handler:
				var overloaded_top: Dictionary = effect_handler.overload_zone(player, zone_index)
				await effect_handler.trigger_leave_play(player.player_id, overloaded_top, zone_index)
			else:
				var destroyed_stack: Array = player.clear_zone(zone_index)
				EffectHandler.banish_or_discard(player, destroyed_stack)
				player.discard_changed.emit()

	player.push_zone_card(zone_index, card)
	events.battle_card_played.emit(player.player_id, card, zone_index)
	player.hand_changed.emit()
	player.zones_changed.emit()
	if effect_handler:
		# Log the action before triggered effects fire so the log reads in causal order
		var has_enter := effect_handler.has_trigger(card, "on_enter")
		effect_handler.log_message.emit(
			GameLog.played_battle(player.player_id, card.get("id", ""), zone_index, has_enter))
		await effect_handler.trigger_enter(player.player_id, card)
		await effect_handler.trigger_battle_card_played(player.player_id, card, zone_index)


func play_strategy_card(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var sz_index: int = player.get_first_empty_strategy_zone_index()
	player.strategy_zones[sz_index] = card
	player.strategy_zone_turn_placed[sz_index] = state.turn_number
	events.strategy_card_played.emit(player.player_id, card, sz_index)
	player.hand_changed.emit()
	player.strategy_zones_changed.emit()
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.played_strategy(player.player_id, card.get("id", ""), card.get("is_base", false)))
		await effect_handler.trigger_enter(player.player_id, card)


func gain_rage(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var old_rage: int = player.rage
	player.discard_pile.append(card)
	player.rage += 1
	events.card_discarded.emit(player.player_id, card)
	events.rage_gained.emit(player.player_id, player.rage)
	player.hand_changed.emit()
	player.rage_changed.emit(player.rage)
	player.discard_changed.emit()
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.gained_rage(player.player_id, player.rage, card.get("id", "")))
		await effect_handler.trigger_discard_from_hand(player.player_id, card)
		await effect_handler.trigger_hand_card_discarded(player.player_id, card)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func play_monster(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var old_monster: Dictionary = player.current_monster
	var old_rage: int = player.rage

	# Alternate play cost (e.g. EBP04-012): execute cost before committing, allow cancel
	var rank_mismatch: bool = card.get("rank", 0) != old_monster.get("rank", 0)
	if rank_mismatch and effect_handler and effect_handler.has_trigger(card, "apply_play_cost"):
		var cost_ok: bool = await effect_handler.apply_play_cost(player.player_id, card, -1)
		if not cost_ok:
			# Cost declined — restore card to hand and force visual rebuild
			player.hand.insert(hand_index, card)
			player.hand_changed.emit()
			events.play_cancelled.emit(player.player_id)
			return
		rank_mismatch = false  # Not a burst play — cost was paid

	# Detect Burst play: card rank doesn't match current monster rank
	var is_burst_play: bool = rank_mismatch
	if is_burst_play:
		player.pre_burst_monster = old_monster
		player.burst_monster = card

	# Push old monster onto the stack (both normal and burst)
	if not old_monster.is_empty():
		player.monster_stack.push_front(old_monster)

	player.has_played_monster_this_turn = true

	player.current_monster = card
	player.rage += 1
	events.monster_played.emit(player.player_id, old_monster, card)
	events.rage_gained.emit(player.player_id, player.rage)
	player.hand_changed.emit()
	player.monster_changed.emit()
	player.rage_changed.emit(player.rage)
	if effect_handler:
		if is_burst_play:
			var burst_effect := effect_handler.get_effect(card)
			var burst_rank: int = burst_effect.get_burst_rank() if burst_effect else -1
			effect_handler.log_message.emit(
				GameLog.burst_played(player.player_id, card.get("id", ""), burst_rank, player.rage))
		else:
			effect_handler.log_message.emit(
				GameLog.played_monster(player.player_id, card.get("id", ""), player.rage))
		# Snapshot discard before on_enter so cards milled during enter don't
		# retroactively qualify for can_play_from_discard_on_monster_played
		# (e.g. EBP02-048 milling EBP03-063 into discard).
		var discard_snapshot: Array = player.discard_pile.duplicate()
		await effect_handler.trigger_enter(player.player_id, card)
		await effect_handler.trigger_monster_played(player.player_id, old_monster, card, discard_snapshot)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func play_monster_from_effect(state: GameState, player_id: int, monster_card: Dictionary) -> void:
	## Play a monster card from the monster deck without rage increase. Does
	## NOT set `has_played_monster_this_turn` — effect-driven plays don't
	## consume the player's once-per-turn monster-play action.
	## Used by strategy effects like EBP03-074 (A Journey of 130 Million Years).
	var player := state.players[player_id]
	var old_monster: Dictionary = player.current_monster

	# Push old monster onto the stack
	if not old_monster.is_empty():
		player.monster_stack.push_front(old_monster)

	# If a burst monster is active, the new monster buries it in the stack.
	# Clear burst state so the burst card isn't discarded at end of turn.
	if not player.burst_monster.is_empty():
		player.burst_monster = {}
		player.pre_burst_monster = {}

	player.current_monster = monster_card
	player.monster_deck.erase(monster_card)
	events.monster_played.emit(player_id, old_monster, monster_card)
	player.monster_changed.emit()
	if effect_handler:
		var discard_snapshot: Array = player.discard_pile.duplicate()
		await effect_handler.trigger_enter(player_id, monster_card, true)
		await effect_handler.trigger_monster_played(player_id, old_monster, monster_card, discard_snapshot)
