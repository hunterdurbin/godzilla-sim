extends CardEffect

## ESD02-009: Super-X - Battle Rank 4
## <Awakening4> <Enter> If this card is in zone 8, reduce your opponent's <Rage> by 1.
## (Active if your monster card is in zone 4 or beyond and this card was played in zone 8.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "zone_dependent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(4)


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed) — effect only activates in zone 8


func on_enter(ctx: EffectContext) -> void:
	# Awakening4: requires monster in zone 4+
	if not ctx.is_awakening(4):
		return

	# Must be in zone 8 (index 7)
	if find_zone_of_card(ctx) != 7:
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
