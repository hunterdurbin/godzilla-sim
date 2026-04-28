extends CardEffect

## EBP01-019: Kamacuras(1967) - Battle Rank 3
## <Awakening6> <Enter> If this card was played from your hand, search your deck for
## up to 2 <Kamacuras> battle cards, play them, then shuffle your deck.
## (Active if your monster card is in zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_enter": {"played_from_hand": true},
}


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6)


func on_enter(ctx: EffectContext) -> void:
	if not ctx.is_awakening(6):
		return

	var valid_zones := CardEffect.get_effect_play_zones(ctx.owner)

	for _i in range(2):
		var selected := await ctx.effect_handler.search_deck(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				if not CardUtils.is_battle(card):
					return false
				return CardUtils.has_trait(card, CardEnums.CardTrait.KAMACURAS),
			tr("STR_EFF_EBP01_019_SEARCH")
		)
		if selected.is_empty():
			break

		var target_zone: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, valid_zones,
			tr("STR_EFF_PLAY_SEARCHED_ZONE"))
		if target_zone < 0:
			break

		await ctx.effect_handler.play_battle_card_from_deck(ctx.owner.player_id, selected, target_zone)

		# Rule 5.11.1.3: must play to different zones if possible
		valid_zones.erase(target_zone)
