extends CardEffect

## EBP01-077: Oxygen Destroyer - Strategy Rank 4 (White)
## If your opponent has 2 or fewer <Rage> , move your opponent's monster card as though
## it were countered. (Do not play the next monster card from your monster deck.)
##
## "As though it were countered" means a counter-retreat teleport (8→3, 7→4, 6→5)
## with no rank-up and no crush of intermediate zones.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.rage <= 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 2:
		return
	ctx.effect_handler.move_monster_as_countered(ctx.opponent.player_id)
