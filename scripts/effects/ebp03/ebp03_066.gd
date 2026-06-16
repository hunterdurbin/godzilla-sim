extends CardEffect
# Thousand-Year Dragon King Ghidorah (Battle R8)
# If your opponent has 2 or more strategy cards in play, you may play this card from
# your hand with its rank reduced by 2. (After being played, this card is rank 8.)
# <Enter> <Destroy> 1 of your opponent’s strategy cards.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_any_strategy_in_play()


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if ctx.opponent.count_strategies_in_play() >= 2:
		return -2
	return 0


func on_enter(ctx: EffectContext) -> void:
	var valid_strat: Array[int] = []
	for i in range(ctx.opponent.strategy_zones.size()):
		if not ctx.opponent.strategy_zones[i].is_empty():
			valid_strat.append(i)

	if valid_strat.is_empty():
		return

	var idx_to_destroy: int = await ctx.effect_handler.select_strategy_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_strat,
		tr("STR_EFF_DESTROY_OPP_STRATEGY"))
	if idx_to_destroy >= 0:
		await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)
