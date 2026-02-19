extends CardEffect

## EBP03-020: Mothra Leo - Monster Rank 3 (Blue)
## When you successfully counter your opponent's monster card, if you have a card
## with <Base> in play, Destroy 1 opponent's rank 7 or lower battle card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_counter_success(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 7,
		"Choose an opponent's rank 7 or lower battle card to destroy:")


func _has_base_in_play(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("is_base", false):
			return true
	return false
