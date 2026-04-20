extends CardEffect
# Godzilla (2002)
# On hand battle card discard + opp rage=0 → Destroy opp rank 4 or lower battle card.
# <Opponent's Turn> <Awakening 6> Counter phase start: discard battle →
# this card cannot be countered by 30,000 or less CP this turn.

var _counter_immunity: int = 0


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_counter_immunity_threshold(_ctx: EffectContext) -> int:
	return _counter_immunity


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	_counter_immunity = 0
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	if ctx.owner.monster_zone < 6:
		return
	var zone_cards := ctx.owner.get_all_zone_cards()
	if zone_cards.size() < 2:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.BATTLE,
		"Discard a battle card: this card cannot be countered by 30,000 or less CP this turn (or skip):",
		true)
	if not selected.is_empty():
		_counter_immunity = 30000


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	if discarded_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if ctx.opponent.rage != 0:
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		"Destroy an opponent's Rank 4 or lower battle card (or skip):",
		true)
