extends CardEffect

## EBP01-077: Oxygen Destroyer - Strategy Rank 4 (White)
## If your opponent has 2 or fewer <Rage>, move your opponent's monster card as though
## it were countered. (Do not play the next monster card from your monster deck.)
##
## "As though it were countered" means move directly to the counter retreat zone (no step-by-step,
## no ranking up). Uses the same direct zone assignment as ActionHandler.resolve_counter().
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

	# "As though countered" — direct zone move, not step-by-step retreat (5.15.1.1)
	ctx.effect_handler.counter_retreat_monster(ctx.opponent.player_id)
