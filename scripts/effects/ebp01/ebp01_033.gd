extends CardEffect

## EBP01-033: Final Showdown - Strategy Rank 8
## You can play this card from your hand with its rank reduced by 1 for each zone
## your monster card invaded this turn.
## <Destroy> all battle cards of both players.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Reduce by 1 for each zone the monster invaded this turn
	return -ctx.owner.invasion_zones_crossed


func on_enter(ctx: EffectContext) -> void:
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zones(ctx.owner, all_zones)
	await ctx.effect_handler.destroy_zones(ctx.opponent, all_zones)
