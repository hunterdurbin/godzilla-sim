extends CardEffect

## EBP01-008: Godzilla(2004) - Monster Rank 3 (Burst II)
## <Burst2> <Enter> Advance your opponent's monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: 
##   Opponent monster already in zone 8 => Opponent does not advance (works)
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.monster_zone < 8


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone < 8:
		await ctx.effect_handler.advance_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone + 1)
