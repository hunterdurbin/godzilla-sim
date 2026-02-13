extends CardEffect
# Mechagodzilla(1993) (Battle R6)
# <Enter> If 2+ other battle cards in your zones, reduce opponent rage by 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var my_id: String = ctx.card_data.get("id", "")
	var other_battle_count := 0
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("id", "") != my_id:
			other_battle_count += 1

	if other_battle_count < 2:
		return

	if ctx.opponent.rage > 0:
		var old_rage := ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
