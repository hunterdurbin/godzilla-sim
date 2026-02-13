extends CardEffect

## EBP01-009: Godzilla(2023) - Monster Rank 3 (Burst II)
## <Burst2> <When Invading> If this card has 2 or more <Rage>, <Destroy> 1 of your
## opponent's rank 6 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 2


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.rage >= 2:
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return card.get("rank", 0) <= 6,
			"Choose an opponent's rank 6 or lower battle card to destroy:")
