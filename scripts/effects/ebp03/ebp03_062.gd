extends CardEffect

## EBP03-062: Baragon(2001) - Battle Rank 6 (Green)
## When your opponent's monster card invades, Destroy this card.
## <Revenge> Return up to 1 Sacred Guardian Beast monster card from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_invasion_observed": {"own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	# Destroy self
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	var zones_to_destroy: Array[int] = [my_zone]
	await ctx.effect_handler.destroy_zones(ctx.owner, zones_to_destroy)


func on_revenge(ctx: EffectContext) -> void:
	# Return up to 1 Sacred Guardian Beast monster from discard to hand
	var selected: Dictionary = await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_monster(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS),
		tr("STR_EFF_EBP03_062_PROMPT"))

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
