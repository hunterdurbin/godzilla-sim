extends CardEffect

## EBP01-030: Godzilla Landing - Strategy Rank 3
## Advance the opponent's monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.monster_zone < 8


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone < 8:
		await ctx.effect_handler.advance_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone + 1)
