extends CardEffect
## EBP04-050: Battra Larva - Battle Rank 6 (Blue)
## Whenever your monster card invades, if this card is in zone 8, choose one:
## ・Draw 1 card, then discard 1 card.
## ・Discard 1 card from your hand. If you do, reduce your opponent’s <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_invasion_observed": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "draws_cards"]


func on_invasion_observed(ctx: EffectContext, invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	if invading_player_id != ctx.owner.player_id:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7: # Must be zone 8 (index 7)
		return

	var options: Array[String] = [
		tr("STR_EFF_EBP04_050_CHOICE_A"),
		tr("STR_EFF_EBP04_050_CHOICE_B"),
	]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options,
		tr("STR_EFF_CHOOSE_ONE"))

	match chosen:
		0:
			ctx.owner.draw_cards(1)
			await ctx.effect_handler.select_hand_card(
				ctx.owner.player_id,
				func(_card): return true,
				tr("STR_EFF_EBP04_050_HAND_DRAW"))
		1:
			var selected := await ctx.effect_handler.select_hand_card(
				ctx.owner.player_id,
				func(_card): return true,
				tr("STR_EFF_EBP04_050_HAND_RAGE"),
				true)
			if not selected.is_empty():
				await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
