extends CardEffect

## ESD04-003: Destoroyah Flying Form - Monster Rank 3 (Blue)
## <Enter> Return up to 1 card named 「Godzilla vs. Destoroyah」 from your
## discard pile to your hand.
## <When Invading> Place 1 battle card with <《Destoroyah》> from your discard
## pile on the bottom of your deck. (If this card invades 2 zones, this
## activates twice.)
##
## Tested: Yes
## Known issues: None
## Edge cases: Enter is optional ("up to"); When Invading is mandatory — no
##   skip when a valid card exists, silent when none.
## Rules: None
## Interactions: EBP01-062 / EBP01-065 / EBP04-083 / ESD04-006 (Godzilla vs.
##   Destoroyah)
## Implementation notes: on_when_invading fires once per zone advanced, so an
##   invade-2 discard places twice (as ESD04-002). search_discard removes the
##   pick from the discard pile; put_card_on_bottom_of_deck logs the move.


const GVD_NAME := "Godzilla vs. Destoroyah"


func get_bot_tags() -> Array[String]:
	return ["recycles_from_discard"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.discard_pile.any(_is_gvd)


func on_enter(ctx: EffectContext) -> void:
	if not ctx.owner.discard_pile.any(_is_gvd):
		return
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id, _is_gvd, tr("STR_EFF_ESD04_003_ENTER_PROMPT"))
	if not selected.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, selected)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if not ctx.owner.discard_pile.any(_is_destoroyah_battle):
		return
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id, _is_destoroyah_battle,
		tr("STR_EFF_ESD04_003_INVADE_PROMPT"), false)
	if not selected.is_empty():
		ctx.effect_handler.put_card_on_bottom_of_deck(ctx.owner.player_id, selected)


static func _is_gvd(card: Dictionary) -> bool:
	return card.get("name", "") == GVD_NAME


static func _is_destoroyah_battle(card: Dictionary) -> bool:
	return CardUtils.is_battle(card) and CardUtils.has_trait(card, CardEnums.CardTrait.DESTOROYAH)
