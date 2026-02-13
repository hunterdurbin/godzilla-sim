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


func on_enter(ctx: EffectContext) -> void:
	var has_mechagodzilla: bool = false
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if top.get("name", "") == "Chibi Mechagodzilla":
			has_mechagodzilla = true
			break

	if has_mechagodzilla and ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
