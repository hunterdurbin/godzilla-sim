extends CardEffect

## EBP01-011: Godzilla(Fest Godzilla) - Monster Rank 1
## When this card advances into the same column as your opponent's monster card,
## advance your opponent's monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: 
##   Step2, own monster moves z3->z5, opponent monster in z2 => Opponent moves to z3
## Rules: None
## Interactions: Effect cares about checking any zones in between the advance sequence
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_monster_advance(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.monster_zone < 8


func on_monster_advance(ctx: EffectContext, _from_zone: int, to_zone: int) -> void:
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var opponent_columns := get_opponent_column_zones(to_zone - 1)
	if opp_monster_idx in opponent_columns:
		if ctx.opponent.monster_zone < 8:
			await ctx.effect_handler.advance_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone + 1)
