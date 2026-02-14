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


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 2:
		return

	# Retreat opponent's monster to its retreat zone
	var retreat_zone: int = ActionHandler.get_retreat_zone(ctx.opponent.monster_zone)
	if retreat_zone != ctx.opponent.monster_zone:
		ctx.opponent.monster_zone = retreat_zone
		ctx.opponent.monster_changed.emit()
