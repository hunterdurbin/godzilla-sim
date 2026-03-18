extends CardEffect

## EBP02-075: Chibi Mothra - Battle Rank 3 (White)
## <Enter> If a card named "Chibi Mechagodzilla" is in your zones,
## reduce your opponent's <Rage> by 1.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	if opponent.rage <= 0:
		return false
	for i in range(8):
		var top := owner.get_zone_top_card(i)
		if top.get("name", "") == "Chibi Mechagodzilla":
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var has_mechagodzilla: bool = false
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if top.get("name", "") == "Chibi Mechagodzilla":
			has_mechagodzilla = true
			break

	if has_mechagodzilla:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
