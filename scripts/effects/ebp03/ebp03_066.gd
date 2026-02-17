extends CardEffect
# Thousand-Year Dragon King Ghidorah (Battle R8)
# If opponent has 2+ strategy cards, play with rank reduced by 2 (self-modifier).
# <Enter> Destroy 1 opponent strategy card.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	var opp_strat_count := 0
	for sz in ctx.opponent.strategy_zones:
		if not sz.is_empty():
			opp_strat_count += 1
	if opp_strat_count >= 2:
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
		"Choose an opponent strategy to Destroy:")
	if idx_to_destroy >= 0:
		await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)
