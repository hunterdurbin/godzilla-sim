extends CardEffect

## EBP01-078: Godzilla Attacks - Strategy Rank 4 (White)
## Advance your monster card to zone 6.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func get_bot_advance_reliability(owner: PlayerState, _opponent: PlayerState) -> int:
	# Guaranteed advance to zone 6, but strategy rank 4 requires monster zone 4+.
	# Less reliable when monster could be pushed back below zone 4.
	if owner.is_awakening(4):
		return 100
	return 30 # Can't play yet — needs zone 4+


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return not owner.is_awakening(6)


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
