extends CardEffect

## EBP02-040: Interception Operation - Strategy Rank 7 (Blue)
## If you have 5 or more <Weapon> battle cards with "MB" in their name in your zones,
## discard your hand and draw 5 cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var mb_weapon_count: int = 0
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if top.is_empty():
			continue
		var traits: Array = top.get("traits", [])
		if CardEnums.CardTrait.WEAPON not in traits:
			continue
		var name: String = top.get("name", "")
		if "MB" in name:
			mb_weapon_count += 1

	if mb_weapon_count < 5:
		return

	# Discard entire hand
	for card in ctx.owner.hand:
		ctx.owner.discard_pile.append(card)
	ctx.owner.hand.clear()
	ctx.owner.hand_changed.emit()
	ctx.owner.discard_changed.emit()

	# Draw 5
	ctx.owner.draw_cards(5)
