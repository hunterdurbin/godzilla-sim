extends CardEffect
## EBP04-014: Godzilla (2002) - Monster Rank 2 (Blue)
## Each time you discard a battle card from your hand and your opponent has 0
## <Rage>, <Destroy> 1 of your opponent's rank 4 or lower battle cards.
## <Opponent's Turn> <Awakening 6> At the beginning of the counter phase, if
## you have 2 or more cards in your zones you may discard 1 battle card from
## your hand so that during the turn this card cannot be countered by 30,000 or
## less counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


var _counter_immunity: int = 0


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_counter_immunity_threshold(_ctx: EffectContext) -> int:
	return _counter_immunity


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_end(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase == CardEnums.GamePhase.END:
		_counter_immunity = 0


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_own_turn():
		return
	if not ctx.is_awakening(6):
		return
	var zone_cards: Array = ctx.owner.get_all_zone_cards()
	if zone_cards.size() < 2:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return CardUtils.is_battle(card),
		tr("STR_EFF_EBP04_014_PROMPT"),
		true)
	if not selected.is_empty():
		_counter_immunity = 30000


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	if not CardUtils.is_battle(discarded_card):
		return
	if ctx.opponent_has_rage():
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
