extends CardEffect

## EBP01-077: Oxygen Destroyer - Strategy Rank 4 (White)
## If your opponent has 2 or fewer <Rage>, move your opponent's monster card as though
## it were countered. (Do not play the next monster card from your monster deck.)
##
## "As though it were countered" means retreat to the retreat zone without ranking up.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 2:
		return

	# "As though countered" — only zones 6-8 move back (5.15.1.1)
	var retreat_zone: int = ActionHandler.get_counter_retreat_zone(ctx.opponent.monster_zone)
	if retreat_zone != ctx.opponent.monster_zone:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, retreat_zone)
