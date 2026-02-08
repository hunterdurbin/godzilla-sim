extends CardEffect

## EBP01-077: Oxygen Destroyer - Strategy Rank 4 (White)
## If your opponent has 2 or fewer <Rage>, move your opponent's monster card as though
## it were countered. (Do not play the next monster card from your monster deck.)
##
## "As though it were countered" means retreat to the retreat zone without ranking up.


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 2:
		return

	# Retreat opponent's monster to its retreat zone
	var retreat_zone: int = _get_retreat_zone(ctx.opponent.monster_zone)
	if retreat_zone != ctx.opponent.monster_zone:
		ctx.opponent.monster_zone = retreat_zone
		ctx.opponent.monster_changed.emit()


func _get_retreat_zone(current_zone: int) -> int:
	match current_zone:
		1: return 1
		2: return 1
		3: return 2
		4: return 3
		5: return 4
		6: return 5
		7: return 4
		8: return 3
	return current_zone
