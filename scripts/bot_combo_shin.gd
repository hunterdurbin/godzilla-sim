class_name BotComboShin
extends BotCombo

## "Shin Combo" — single-turn win path from zone 3-6.
## Full combo: advance card #1 → zone 6, card #2 → zone 7,
##   (destroy z8 if blocked), invade 2-step → zone 9 = victory.
## From zone 6: only card #2 + (destroy) + invasion needed.

# Viability tuning
var proximity_scores: Array[int] = [50, 70, 90, 100] # zones 3,4,5,6
var low_pressure_bonus: int = 20
var high_pressure_penalty: int = 20
var critical_pressure_penalty: int = 40
var z8_clear_bonus: int = 20


func _init() -> void:
	combo_name = "Shin"
	full_min_bonus = 100
	partial_penalty = 100


func is_deck_compatible(player: PlayerState, bot) -> bool:
	## Check if the deck has the core shin combo pieces in main deck + hand:
	## 1. "advances_self" card with max_zone >= 7 (advancement to z7+)
	## 2. "advances_self" card with max_zone >= 6 (advance-to-6)
	## 3. Card with invasion_icon >= 2 (2-step invasion for the win)
	var effects: EffectHandler = bot.effect_handler
	var has_advancement := false
	var has_advance_to_6 := false
	var has_2step_invasion := false

	var all_cards: Array[Dictionary] = []
	all_cards.append_array(player.hand)
	all_cards.append_array(player.main_deck)
	for card in all_cards:
		if card.get("invasion_icon", 0) >= 2:
			has_2step_invasion = true
		var effect := effects.get_effect(card)
		if effect and "advances_self" in effect.get_bot_tags():
			var max_zone: int = effect.get_bot_max_advance_zone(player, player)
			if max_zone == -1 or max_zone >= 7:
				has_advancement = true
			if max_zone == -1 or max_zone >= 6:
				has_advance_to_6 = true
		if has_advancement and has_advance_to_6 and has_2step_invasion:
			return true

	return has_advancement and has_advance_to_6 and has_2step_invasion


func check(player: PlayerState, opponent: PlayerState, bot) -> Dictionary:
	# Rank 4+: counter-retreat can't reach rank 3 anymore, combo is done.
	# Switch to normal counter/invasion play.
	if player.current_monster.get("rank", 0) >= 4:
		return {}
	# Zone 7+ with rank 3+: already past the combo setup window.
	if player.monster_zone >= 7 and player.current_monster.get("rank", 0) >= 3:
		return {}

	# Find all pieces independently — don't bail early so partial detection
	# works even when only 1 piece is in hand.
	var reserved: Array = []

	# Invasion card (2-step)
	var invade_idx: int = bot.find_invade_card_with_steps(player, 2)
	if invade_idx >= 0:
		reserved.append(invade_idx)

	# Clear zone 8 (if blocked): try destroy card first, then advance-opponent crush
	var z8_clear := not opponent.zone_has_battle_card(7)
	var destroy_idx: int = -1
	var crush_indices: Array[int] = []  # advance-opponent cards to push opp into z8
	if not z8_clear:
		destroy_idx = _find_zone_8_destroy_card(player, opponent, reserved, bot)
		if destroy_idx >= 0:
			reserved.append(destroy_idx)
		else:
			# No destroy card — try crush path: advance opponent to zone 8
			crush_indices = _find_crush_z8_cards(player, opponent, reserved, bot)
			for idx in crush_indices:
				reserved.append(idx)

	# Card #2 (advancement card: advances from zone 6 → zone 7+)
	var adv_result := _find_advancement_card(player, opponent, reserved, bot)
	var advancement_idx: int = adv_result[0]
	var advancement_is_monster: bool = adv_result[1]
	if advancement_idx >= 0:
		reserved.append(advancement_idx)

	# Card #1 (advance to zone 6) — not needed if already at zone 6
	var advance_to_6_idx: int = -1
	if player.monster_zone < 6:
		advance_to_6_idx = _find_advance_to_zone_6_card(player, opponent, reserved, bot)

	# Counter-retreat path: rank-up monster with "advances_opponent" in monster deck.
	# Getting countered auto-plays it, pushing opponent forward and crushing their z8.
	# This replaces the need for a hand advancement card AND destroy card.
	var counter_retreat_path: bool = _has_counter_retreat_path(player, opponent, bot)

	# Determine combo state
	var z8_can_clear: bool = z8_clear or destroy_idx >= 0 or not crush_indices.is_empty() \
			or counter_retreat_path
	var have_all: bool = invade_idx >= 0 \
			and (advancement_idx >= 0 or counter_retreat_path) \
			and z8_can_clear \
			and (player.monster_zone >= 6 or advance_to_6_idx >= 0)

	# Find effect cost reserves — cards needed to pay combo pieces' costs.
	# E.g. EBP02-003 requires discarding a strategy. Reserve one so it isn't wasted.
	var combo_indices: Array = [invade_idx, destroy_idx, advance_to_6_idx, advancement_idx]
	combo_indices.append_array(crush_indices)
	var cost_reserve_idx: int = _find_effect_cost_reserve(player, combo_indices, bot)

	# Verify combo pieces' effect costs don't consume other combo pieces.
	if have_all:
		var all_reserved := combo_indices.duplicate()
		if cost_reserve_idx >= 0:
			all_reserved.append(cost_reserve_idx)
		for piece_idx in combo_indices:
			if piece_idx < 0:
				continue
			var effects: EffectHandler = bot.effect_handler
			var effect := effects.get_effect(player.hand[piece_idx])
			if not effect:
				continue
			var costs: Array[Dictionary] = effect.get_bot_effect_costs()
			for cost in costs:
				var needed: int = cost.get("count", 1)
				var available := _count_non_combo_cards_of_type(
						player, cost.get("card_type", -1), combo_indices)
				if available < needed:
					have_all = false
					break
			if not have_all:
				break

	if have_all:
		var plan := _build_plan("full", advance_to_6_idx, advancement_idx,
				advancement_is_monster, destroy_idx, invade_idx, cost_reserve_idx, crush_indices)
		plan["counter_retreat_path"] = counter_retreat_path
		plan["viability"] = _compute_viability(player, opponent, plan, bot)
		return plan

	# Log why the combo isn't full
	var missing: PackedStringArray = []
	if invade_idx < 0:
		missing.append("no 2-step invasion card")
	if advancement_idx < 0:
		missing.append("no advancement card")
	if not z8_can_clear:
		missing.append("z8 blocked (no destroy/crush)")
	if player.monster_zone < 6 and advance_to_6_idx < 0:
		missing.append("no advance-to-6 card")
	if not missing.is_empty():
		print("[Bot Shin] Not full: %s (zone=%d hand=%d)" % [
			", ".join(missing), player.monster_zone, player.hand.size()])

	# Partial: at least one piece in hand and missing pieces exist in deck
	var has_any_piece: bool = invade_idx >= 0 or advancement_idx >= 0 \
			or advance_to_6_idx >= 0 or destroy_idx >= 0
	if not has_any_piece:
		has_any_piece = _has_any_advance_card_in_hand(player, bot)
	if not has_any_piece:
		print("[Bot Shin] No combo pieces in hand")
		return {}

	var missing_in_deck := _scan_deck_for_combo_pieces(player, opponent,
			advancement_idx < 0, not z8_clear and destroy_idx < 0,
			player.monster_zone < 6 and advance_to_6_idx < 0, bot)
	if not missing_in_deck:
		if advancement_idx < 0 and invade_idx < 0:
			print("[Bot Shin] Missing pieces not in deck, no key pieces in hand")
			return {}

	# Proactively reserve a destroy card even if z8 is currently clear
	var plan_destroy_idx := destroy_idx
	if plan_destroy_idx < 0:
		var partial_reserved := [invade_idx, advancement_idx, advance_to_6_idx]
		plan_destroy_idx = _find_any_destroy_card(player, partial_reserved, bot)
	var partial_plan := _build_plan("partial", advance_to_6_idx, advancement_idx,
			advancement_is_monster, plan_destroy_idx, invade_idx, cost_reserve_idx, crush_indices)
	partial_plan["counter_retreat_path"] = counter_retreat_path
	return partial_plan


func should_prioritize_cycling(plan: Dictionary, player: PlayerState,
		opponent: PlayerState) -> bool:
	# Shin combo cycles hand to find pieces rather than building board.
	# Prioritize rage gain (discard monster → draw at end of turn) when:
	# - Combo is partial (still looking for pieces)
	# - Counter-retreat path exists (combo is viable)
	# - Not yet at the execution window
	if plan.get("state") != "partial":
		return false
	if not plan.get("counter_retreat_path", false):
		return false
	# Don't cycle when opponent is about to win — need to defend
	if opponent.monster_zone >= 7:
		return false
	return true


func should_suppress_invasion(plan: Dictionary, player: PlayerState, opponent: PlayerState) -> bool:
	var mz := player.monster_zone
	var opp_z := opponent.monster_zone
	var has_cr: bool = plan.get("counter_retreat_path", false)

	if not has_cr:
		return false

	# Counter-bait window: opponent at z7+ and bot at z5-7.
	# ALLOW invasion — we want to reach z6-7 and get countered.
	if opp_z >= 7 and mz >= 5 and mz <= 7:
		return false

	# Full state at z6-7: allow invasion for execution
	if plan.get("state") == "full" and mz >= 6 and mz <= 7:
		return false

	# Tempo control: pace-match the opponent tightly.
	# Never invade more than 1 zone ahead of opponent.
	if mz >= opp_z + 1:
		return true

	# At z5+: only invade for counter-bait (handled above), not aggressively
	if mz >= 5 and opp_z < 7:
		return true

	return false


func get_invasion_preference(plan: Dictionary, player: PlayerState, opponent: PlayerState) -> Dictionary:
	var pref := {"preferred_steps": 0, "max_zone": -1, "target_zone": -1}
	var mz := player.monster_zone
	var opp_z := opponent.monster_zone
	var has_cr: bool = plan.get("counter_retreat_path", false)

	if not has_cr:
		return pref

	# Shin combo invasion rules:
	# 1. Save 2-step invasion cards for the win — use 1-step for positioning
	# 2. Never invade past z7 unless overwhelming threat (35k+ surplus)
	# 3. Pace-match: don't invade past opponent's zone + 1
	# 4. Counter-bait at z6-7 only when opponent is at z7+

	var threat_surplus: int = _get_threat_surplus(player, opponent)
	if threat_surplus >= 35000:
		pref["max_zone"] = -1
	elif opp_z >= 7:
		# Opponent at z7+: they can invade 2-step to win. Don't advance
		# past z6 — z7 end-of-turn pushes to z8 which is suicidal.
		# Stay at z5-6 and focus on defense / counter-bait.
		pref["max_zone"] = 6
	else:
		# Cap at opponent zone + 1 or z7, whichever is lower
		pref["max_zone"] = mini(opp_z + 1, 7)

	# Always prefer 1-step to conserve 2-step cards for the win
	pref["preferred_steps"] = 1

	# Counter-bait: opponent at z7+ → position at z5-6 for counter setup.
	# Don't invade past z6 — let end-of-turn advance to z7 where counter happens.
	if opp_z >= 7 and mz >= 4 and mz <= 6:
		pref["target_zone"] = mini(mz + 1, 6)
		return pref

	# Positioning: stay within 1 zone of opponent
	if mz < opp_z:
		pref["target_zone"] = mini(mz + 1, opp_z)

	return pref


func adjust_card_score(plan: Dictionary, hand_idx: int, base_score: int,
		player: PlayerState, opponent: PlayerState) -> int:
	var score: int = base_score
	var mz := player.monster_zone
	var invade_idx: int = plan.get("invade_idx", -1)

	if plan.get("state") == "full":
		# Full: boost combo pieces, protect invasion card
		var boosted: Array = plan.get("boosted_indices", [])
		if hand_idx in boosted:
			score += maxi(plan.get("viability", 0), full_min_bonus)
		elif hand_idx == invade_idx:
			score -= partial_penalty
	else:
		# Partial: only protect invasion card from being played as battle card.
		# All other pieces can be played normally for immediate value.
		if hand_idx == invade_idx:
			score -= partial_penalty

	# Boost advance-to-6 cards at zone 4-5 (they enable the combo NOW)
	if mz >= 4 and mz <= 5 and plan.get("advance_to_6_idx", -1) == hand_idx:
		score += 30

	# Boost destroy cards when z8 is blocked and combo is near execution
	if plan.get("state") == "full" or mz >= 5:
		if opponent.zone_has_battle_card(7) and plan.get("destroy_idx", -1) == hand_idx:
			score += 20

	# Protect strategy cards: the combo needs strategies both as pieces
	# (advance-to-6) and as fuel (EBP02-003 costs a strategy discard).
	# Don't play a strategy if it would drop below 2 in hand.
	if hand_idx < player.hand.size() \
			and player.hand[hand_idx].get("card_type") == CardEnums.CardType.STRATEGY:
		var strat_count: int = _count_strategies_in_hand(player)
		if strat_count <= 2:
			score -= 80

	return score


func get_execution_action(plan: Dictionary, valid_actions: Array,
		player: PlayerState, opponent: PlayerState, bot) -> Array:
	# Only sequence when combo is viable and all key pieces are in hand
	if plan.get("viability", 0) <= 0:
		return []
	var invade_idx: int = plan.get("invade_idx", -1)
	var adv_idx: int = plan.get("advancement_idx", -1)
	if invade_idx < 0 or adv_idx < 0:
		return []

	var mz := player.monster_zone
	var opp_z := opponent.monster_zone

	# Don't execute past z7 — z8 is past the combo's effective zone
	if mz >= 8:
		return []

	# Don't execute when advancing would be suicidal.
	# If opponent is at z7+ they can invade 2-step to win — don't push forward,
	# focus on defense. Exception: bot is already at z6+ with enough pieces to win NOW.
	if opp_z >= 7 and mz < 6:
		return []

	# Don't execute until opponent is in position.
	# Opponent at z6+ (about to reach z7) or already has a card in z8 = go time.
	if opp_z < 6 and not opponent.zone_has_battle_card(7):
		return []

	# Step 1: Get to zone 6 — play advance-to-6 card (only when below z6)
	if mz < 6:
		var adv6_idx: int = plan.get("advance_to_6_idx", -1)
		if adv6_idx >= 0:
			var action := _try_play_card(adv6_idx, player, opponent, valid_actions, bot)
			if not action.is_empty():
				return action

	# Check if advancement is ready to play (gates Steps 2-4)
	var adv_ready := false
	if mz >= 6 and adv_idx >= 0 and adv_idx < player.hand.size():
		if plan.get("advancement_is_monster", false):
			if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
				var playable: Array[int] = bot.rules_engine.get_playable_monsters(player)
				adv_ready = adv_idx in playable
		else:
			adv_ready = not _try_play_card(adv_idx, player, opponent, valid_actions, bot).is_empty()

	# Step 2: Advance from z6+ (only when advancement is playable)
	if adv_ready:
		if plan.get("advancement_is_monster", false):
			return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": adv_idx}]
		else:
			return _try_play_card(adv_idx, player, opponent, valid_actions, bot)

	# Steps 3-4 only when advancement is ready (don't invade prematurely)
	if adv_ready or mz >= 7:
		# Step 3: Clear z8 if blocked
		if mz >= 6 and opponent.zone_has_battle_card(7):
			var destroy_idx: int = plan.get("destroy_idx", -1)
			if destroy_idx >= 0:
				var action := _try_play_card(destroy_idx, player, opponent, valid_actions, bot)
				if not action.is_empty():
					return action

		# Step 4: Invade to z7 from z6
		if mz == 6 and CardEnums.ActionType.INVADE in valid_actions:
			var one_step: int = bot.find_invade_card_with_steps(player, 1, [])
			if one_step >= 0:
				return [CardEnums.ActionType.INVADE, {"hand_index": one_step}]

	return []


func _try_play_card(hand_idx: int, player: PlayerState, opponent: PlayerState,
		valid_actions: Array, bot) -> Array:
	## Try to play a specific card from hand. Returns action array or [].
	if hand_idx < 0 or hand_idx >= player.hand.size():
		return []
	var card: Dictionary = player.hand[hand_idx]
	var card_type: int = card.get("card_type", -1)
	var rules_eng: RulesEngine = bot.rules_engine

	if card_type == CardEnums.CardType.STRATEGY:
		if CardEnums.ActionType.PLAY_STRATEGY not in valid_actions:
			return []
		if hand_idx not in rules_eng.get_playable_strategy_cards(player):
			return []
		return [CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx}]

	elif card_type == CardEnums.CardType.BATTLE:
		if CardEnums.ActionType.PLAY_BATTLE not in valid_actions:
			return []
		if hand_idx not in rules_eng.get_playable_battle_cards(player, opponent):
			return []
		var valid_zones := rules_eng.get_valid_zones_for_card(card, player, opponent)
		if valid_zones.is_empty():
			return []
		var zone: int = bot._pick_battle_zone(valid_zones, player, opponent, card)
		return [CardEnums.ActionType.PLAY_BATTLE, {"hand_index": hand_idx, "zone_index": zone}]

	return []


func get_partial_reserved_indices(plan: Dictionary) -> Array[int]:
	# Shin combo needs: invasion card, advancement card, and advance-to-6 (strategy fuel)
	var critical: Array[int] = []
	for key in ["invade_idx", "advancement_idx", "advance_to_6_idx"]:
		var idx: int = plan.get(key, -1)
		if idx >= 0:
			critical.append(idx)
	return critical


func get_rankup_bonus(plan: Dictionary, monster: Dictionary,
		player: PlayerState, opponent: PlayerState, bot) -> int:
	# Strongly prefer rank 3 "advances_opponent" monster — getting countered into
	# this monster pushes the opponent forward and crushes their z8 defense.
	var effect: CardEffect = bot.effect_handler.get_effect(monster)
	if not effect:
		return 0
	if "advances_opponent" not in effect.get_bot_tags():
		return 0
	# Opponent at z7+: advancing them crushes their z8 card → huge bonus
	if opponent.monster_zone >= 7:
		return 200
	# Opponent at z5-6: advancing them is still beneficial positioning
	if opponent.monster_zone >= 5:
		return 50
	return 10


func get_battle_zone_avoidance(plan: Dictionary, player: PlayerState) -> Array[int]:
	var avoid: Array[int] = []
	var mz := player.monster_zone
	# Avoid zones the monster will crush when advancing to zone 6.
	# Zones mz+1 through 6 get crushed (1-indexed), convert to 0-indexed.
	if mz < 6 and (plan.get("state") == "full" or plan.get("advance_to_6_idx", -1) >= 0):
		for z in range(mz + 1, 7):  # zones mz+1 to 6 (1-indexed)
			avoid.append(z - 1)  # Convert to 0-indexed
	return avoid


func get_monster_play_rules(plan: Dictionary, player: PlayerState, bot) -> Dictionary:
	var rules := {"skip_all": false, "force_play_idx": - 1, "exclude_idx": - 1}
	if not plan.get("advancement_is_monster", false):
		return rules

	var adv_idx: int = plan.get("advancement_idx", -1)
	if adv_idx < 0:
		return rules

	# Partial: just exclude the specific advancement card from normal plays.
	# Other monsters can play freely — only restrict when executing.
	rules["exclude_idx"] = adv_idx

	if plan.get("state") != "full":
		return rules

	# Full: protect the rank slot for execution
	if plan.get("advance_to_6_idx", -1) >= 0:
		rules["skip_all"] = true
	else:
		var playable: Array[int] = bot.rules_engine.get_playable_monsters(player)
		if adv_idx in playable:
			rules["force_play_idx"] = adv_idx
			rules["exclude_idx"] = -1
		else:
			rules["skip_all"] = true

	return rules


func _build_plan(state: String, advance_to_6_idx: int, advancement_idx: int,
		advancement_is_monster: bool, destroy_idx: int, invade_idx: int,
		cost_reserve_idx: int = -1, p_crush_indices: Array[int] = []) -> Dictionary:
	# Collect reserved and boosted indices
	var reserved_indices: Array[int] = []
	var boosted_indices: Array[int] = []
	for idx in [advance_to_6_idx, advancement_idx, destroy_idx, invade_idx, cost_reserve_idx]:
		if idx >= 0:
			reserved_indices.append(idx)
	for idx in p_crush_indices:
		if idx >= 0:
			reserved_indices.append(idx)
	if state == "full":
		for idx in [advance_to_6_idx, advancement_idx, destroy_idx]:
			if idx >= 0:
				boosted_indices.append(idx)
		for idx in p_crush_indices:
			if idx >= 0:
				boosted_indices.append(idx)

	return {
		"combo_name": combo_name,
		"state": state,
		"viability": 0,
		"reserved_indices": reserved_indices,
		"boosted_indices": boosted_indices,
		# Shin-specific keys for monster play logic
		"advance_to_6_idx": advance_to_6_idx,
		"advancement_idx": advancement_idx,
		"advancement_is_monster": advancement_is_monster,
		"destroy_idx": destroy_idx,
		"invade_idx": invade_idx,
	}


func _find_effect_cost_reserve(player: PlayerState, combo_indices: Array, bot) -> int:
	## Find a hand card to reserve for paying combo pieces' effect costs.
	## E.g. if the advancement card needs a strategy discard, reserve one strategy.
	var effects: EffectHandler = bot.effect_handler
	for piece_idx in combo_indices:
		if piece_idx < 0:
			continue
		var effect := effects.get_effect(player.hand[piece_idx])
		if not effect:
			continue
		var costs: Array[Dictionary] = effect.get_bot_effect_costs()
		for cost in costs:
			var cost_type: int = cost.get("card_type", -1)
			if cost_type < 0:
				continue
			# Find a card of this type that isn't a combo piece
			for i in range(player.hand.size()):
				if i in combo_indices:
					continue
				if player.hand[i].get("card_type") == cost_type:
					return i
	return -1


func _count_non_combo_cards_of_type(player: PlayerState, card_type: int, combo_indices: Array) -> int:
	## Count hand cards of the given type that aren't reserved for the combo.
	var count: int = 0
	for i in range(player.hand.size()):
		if i in combo_indices:
			continue
		if player.hand[i].get("card_type") == card_type:
			count += 1
	return count


func _has_any_advance_card_in_hand(player: PlayerState, bot) -> bool:
	## Check if any card in hand has "advances_self" tag (fallback for partial detection).
	var effects: EffectHandler = bot.effect_handler
	for hand_idx in range(player.hand.size()):
		var effect := effects.get_effect(player.hand[hand_idx])
		if effect and "advances_self" in effect.get_bot_tags():
			return true
	return false


# --- Piece finding ---

func _find_advancement_card(player: PlayerState, opponent: PlayerState,
		reserved: Array, bot) -> Array:
	## Find card #2: advances_self with max_advance_zone >= 7 or == -1.
	## Evaluates as if monster is at zone 6 (card #2 fires after card #1).
	var saved_zone := player.monster_zone
	player.monster_zone = maxi(saved_zone, 6)
	var result := _find_advancement_card_at_zone_6(player, opponent, reserved, bot)
	player.monster_zone = saved_zone
	return result


func _find_advancement_card_at_zone_6(player: PlayerState, opponent: PlayerState,
		reserved: Array, bot) -> Array:
	## Find the most reliable advancement card (card #2). Returns [hand_idx, is_monster].
	var rules_eng: RulesEngine = bot.rules_engine
	var effects: EffectHandler = bot.effect_handler
	var best_idx: int = -1
	var best_is_monster: bool = false
	var best_reliability: int = -1

	# Check playable battle and strategy cards
	var all_playable: Array[int] = []
	all_playable.append_array(rules_eng.get_playable_battle_cards(player, opponent))
	all_playable.append_array(rules_eng.get_playable_strategy_cards(player))

	for hand_idx in all_playable:
		if hand_idx in reserved:
			continue
		var effect := effects.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "advances_self" not in effect.get_bot_tags():
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 7:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		var reliability: int = effect.get_bot_advance_reliability(player, opponent)
		if reliability > best_reliability:
			best_reliability = reliability
			best_idx = hand_idx
			best_is_monster = false

	# Check ALL monster cards in hand — always scan for protection purposes.
	# has_played_monster_this_turn is handled by get_monster_play_rules(),
	# not here (this is detection, not execution).
	var cur_rank: int = player.current_monster.get("rank", 0)
	for hand_idx in range(player.hand.size()):
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		var card_rank: int = card.get("rank", 0)
		var burst_rank: int = -1
		var effect := effects.get_effect(card)
		if effect and effect.has_method(&"get_burst_rank"):
			burst_rank = effect.get_burst_rank()
		if card_rank < cur_rank and burst_rank < cur_rank:
			continue
		if not effect:
			continue
		if "advances_self" not in effect.get_bot_tags():
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 7:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		var reliability: int = effect.get_bot_advance_reliability(player, opponent)
		if reliability > best_reliability:
			best_reliability = reliability
			best_idx = hand_idx
			best_is_monster = true

	if best_idx >= 0:
		return [best_idx, best_is_monster]
	return [-1, false]


func _find_crush_z8_cards(player: PlayerState, opponent: PlayerState,
		reserved: Array, bot) -> Array[int]:
	## Find enough "advances_opponent" cards to push opponent monster to zone 8.
	## Returns hand indices of the cards needed, or empty if not enough.
	var zones_needed: int = 8 - opponent.monster_zone
	if zones_needed <= 0 or zones_needed > 2:
		return []  # Opponent already at z8+ or too far away

	var effects: EffectHandler = bot.effect_handler
	var rules_eng: RulesEngine = bot.rules_engine
	var found: Array[int] = []

	# Search playable battle and strategy cards with "advances_opponent"
	var all_playable: Array[int] = []
	all_playable.append_array(rules_eng.get_playable_battle_cards(player, opponent))
	all_playable.append_array(rules_eng.get_playable_strategy_cards(player))

	for hand_idx in all_playable:
		if hand_idx in reserved or hand_idx in found:
			continue
		var effect := effects.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "advances_opponent" not in effect.get_bot_tags():
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		found.append(hand_idx)
		if found.size() >= zones_needed:
			return found

	return []  # Not enough advance-opponent cards


func _find_advance_to_zone_6_card(player: PlayerState, opponent: PlayerState,
		reserved: Array, bot) -> int:
	## Find the most reliable "advances_self" card that can reach zone 6+.
	## Scans ALL hand cards (not just currently playable) for combo protection.
	var effects: EffectHandler = bot.effect_handler
	var best_idx: int = -1
	var best_reliability: int = -1

	for hand_idx in range(player.hand.size()):
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		# Skip monsters — they use a different combo role (advancement)
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			continue
		var effect := effects.get_effect(card)
		if not effect:
			continue
		if "advances_self" not in effect.get_bot_tags():
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 6:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		var reliability: int = effect.get_bot_advance_reliability(player, opponent)
		if reliability > best_reliability:
			best_reliability = reliability
			best_idx = hand_idx

	return best_idx


func _find_zone_8_destroy_card(player: PlayerState, opponent: PlayerState,
		reserved: Array, bot) -> int:
	var z8_card := opponent.get_zone_top_card(7)
	if z8_card.is_empty():
		return -1
	var z8_rank: int = z8_card.get("rank", 0)
	var rules_eng: RulesEngine = bot.rules_engine
	var effects: EffectHandler = bot.effect_handler

	for hand_idx in rules_eng.get_playable_battle_cards(player, opponent):
		if hand_idx in reserved:
			continue
		var effect := effects.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "destroys_zone" not in effect.get_bot_tags():
			continue
		var max_rank: int = effect.get_bot_destroy_max_rank(player, opponent)
		if max_rank > 0 and z8_rank > max_rank:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	for hand_idx in rules_eng.get_playable_strategy_cards(player):
		if hand_idx in reserved:
			continue
		var effect := effects.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "destroys_zone" not in effect.get_bot_tags():
			continue
		var max_rank: int = effect.get_bot_destroy_max_rank(player, opponent)
		if max_rank > 0 and z8_rank > max_rank:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	return -1


func _find_any_destroy_card(player: PlayerState, reserved: Array, bot) -> int:
	var effects: EffectHandler = bot.effect_handler
	for hand_idx in range(player.hand.size()):
		if hand_idx in reserved:
			continue
		var effect := effects.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "destroys_zone" in effect.get_bot_tags():
			return hand_idx
	return -1


func _scan_deck_for_combo_pieces(player: PlayerState, opponent: PlayerState,
		need_advancement: bool, need_destroy: bool, need_advance_to_6: bool, bot) -> bool:
	var effects: EffectHandler = bot.effect_handler
	var found_advancement := not need_advancement
	var found_destroy := not need_destroy
	var found_advance_to_6 := not need_advance_to_6

	var saved_zone := player.monster_zone
	var cur_rank: int = player.current_monster.get("rank", 0)
	for card in player.main_deck:
		var effect := effects.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()

		if not found_advancement and "advances_self" in tags:
			# For monster cards, check rank reachability
			if card.get("card_type") == CardEnums.CardType.MONSTER:
				var card_rank: int = card.get("rank", 0)
				var burst_rank: int = -1
				if effect.has_method(&"get_burst_rank"):
					burst_rank = effect.get_burst_rank()
				if card_rank < cur_rank and burst_rank < cur_rank:
					continue
			player.monster_zone = maxi(saved_zone, 6)
			var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
			player.monster_zone = saved_zone
			if max_zone == -1 or max_zone >= 7:
				found_advancement = true

		if not found_destroy and "destroys_zone" in tags:
			found_destroy = true

		if not found_advance_to_6 and "advances_self" in tags:
			var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
			if max_zone == -1 or max_zone >= 6:
				found_advance_to_6 = true

		if found_advancement and found_destroy and found_advance_to_6:
			return true

	return found_advancement and found_destroy and found_advance_to_6


# --- Threat / CP helpers ---

func _count_strategies_in_hand(player: PlayerState) -> int:
	var count: int = 0
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			count += 1
	return count


func _get_threat_surplus(player: PlayerState, opponent: PlayerState) -> int:
	## Returns bot's threat minus opponent's total CP. Positive = bot overwhelms counter.
	var bot_threat: int = player.get_threat_level()
	var opp_cp: int = opponent.get_total_counter_power()
	return bot_threat - opp_cp


# --- Counter-retreat path ---

func _has_counter_retreat_path(player: PlayerState, opponent: PlayerState, bot) -> bool:
	## Check if the monster deck has a rank 3+ monster with "advances_opponent" on_enter.
	## If so, getting countered will auto-play it, pushing the opponent forward.
	var cur_rank: int = player.current_monster.get("rank", 0)
	var effects: EffectHandler = bot.effect_handler
	for monster in player.monster_deck:
		var m_rank: int = monster.get("rank", 0)
		if m_rank != cur_rank + 1:
			continue
		var effect := effects.get_effect(monster)
		if not effect:
			continue
		if "advances_opponent" in effect.get_bot_tags():
			return true
	return false


# --- Viability ---

func _compute_viability(player: PlayerState, opponent: PlayerState,
		plan: Dictionary, bot) -> int:
	var score: int = 0

	# Proximity: based on monster zone (3-6)
	var zone_idx: int = player.monster_zone - 3
	if zone_idx >= 0 and zone_idx < proximity_scores.size():
		score += proximity_scores[zone_idx]

	# Opponent pressure — flipped when counter-retreat path is available:
	# opponent at z7 is GOOD (counter-bait ready), not bad.
	var has_cr: bool = plan.get("counter_retreat_path", false)
	var pressure: int = 0
	if has_cr and opponent.monster_zone >= 7:
		# Opponent at z7+ is ideal for counter-bait
		pressure = 30
	elif opponent.monster_zone <= 4:
		pressure = low_pressure_bonus
	elif opponent.monster_zone <= 6:
		pressure = 0
	elif opponent.monster_zone == 7:
		pressure = - high_pressure_penalty
	else:
		pressure = - critical_pressure_penalty
	if pressure < 0 and bot.can_counter_opponent():
		pressure /= 2
	score += pressure

	# Zone 8 clear bonus
	if plan.get("destroy_idx", -1) == -1:
		score += z8_clear_bonus

	# Hand flexibility penalty (reduced — combo near execution shouldn't be punished)
	var combo_pieces: int = 1 # invasion card
	if plan.get("advance_to_6_idx", -1) >= 0:
		combo_pieces += 1
	if plan.get("advancement_idx", -1) >= 0:
		combo_pieces += 1
	if plan.get("destroy_idx", -1) >= 0:
		combo_pieces += 1
	var remaining: int = player.hand.size() - combo_pieces
	if remaining >= 5:
		score -= 5
	elif remaining >= 3:
		score -= 10
	elif remaining >= 1:
		score -= 15
	else:
		score -= 20

	# CP gap penalty
	var cp_gap: int = bot.get_cp_gap()
	if cp_gap >= 10000:
		score -= 30
	elif cp_gap >= 5000:
		score -= 15

	# Invasion blocked
	if bot.effect_handler.is_own_invasion_blocked(player.player_id):
		score -= 100

	return maxi(score, 0)
