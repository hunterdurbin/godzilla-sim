extends CardEffect

## EBP01-003: Godzilla(1954) - Monster Rank 3
## Whenever this card's <Rage> is increased, send the top card of your deck to your
## discard pile. If it is a monster card, <Destroy> 1 of your opponent's rank 6 or lower
## battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_rage_changed": {"direction": "increase"},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "mill_self"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func on_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	var card := ctx.mill_one()
	if card.is_empty():
		return

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		tr("STR_EFF_DISCARDED_PILE"))

	if CardUtils.is_monster(card):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(c: Dictionary) -> bool: return ctx.field_rank(c, ctx.opponent.player_id) <= 6,
			tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)
