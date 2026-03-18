extends CardEffect

## EBP01-013: Godzilla(Fest Godzilla) - Monster Rank 3 (Burst II)
## <Burst2> <Enter> If you have 4 or more battle cards in your zones,
## reduce your opponent's <Rage> by 1.
##
## Tested: Yes
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
	var battle_count: int = 0
	for i in range(8):
		if owner.zone_has_battle_card(i):
			battle_count += 1
			if battle_count >= 4:
				return true
	return false


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	var battle_count: int = 0
	for i in range(8):
		if ctx.owner.zone_has_cards(i):
			battle_count += 1
	if battle_count >= 4:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
