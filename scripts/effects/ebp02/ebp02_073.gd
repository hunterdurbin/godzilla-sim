extends CardEffect

## EBP02-073: Bloody Chainsaw - Strategy Rank 6 (Green)
## <Your Turn> Whenever you play a battle card, <Destroy> all of your opponent's
## rank 6 or lower battle cards in the same column as that battle card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_battle"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_battle_card_played(ctx: EffectContext, zone_index: int) -> void:
	# <Your Turn> — only active during owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	# Find opponent's zones in the same column
	var opp_column_zones := get_opponent_column_zones(zone_index)
	# Collect zones with rank 6 or lower battle cards
	var zones_to_destroy: Array[int] = []
	for opp_zi in opp_column_zones:
		var opp_card := ctx.opponent.get_zone_top_card(opp_zi)
		if not opp_card.is_empty() and ctx.field_rank(opp_card, ctx.opponent.player_id) <= 6:
			zones_to_destroy.append(opp_zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
