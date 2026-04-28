extends CardEffect

## EBP02-074: Bite Attack - Strategy Rank 7 (Green)
## Increase your monster card's <Rage> by 1 for each rank of your opponent's monster.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_enter(ctx: EffectContext) -> void:
	var opp_rank: int = ctx.opponent.get_monster_rank()
	if opp_rank > 0:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, opp_rank, ctx.card_data.get("id", ""))
