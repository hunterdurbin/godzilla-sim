extends CardEffect

## EBP02-023: Godzilla(1999) - Monster Rank 4 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, 1 of your opponent's
## monster cards with 50,000 or less threat level retreats back by 1 zone.
## If you have 10 or more monster cards in your discard pile, this card gains +10,000 TL.


func on_enter(ctx: EffectContext) -> void:
	var monster_count := _count_monsters_in_discard(ctx.owner)
	if monster_count < 5:
		return

	var opp_tl: int = ctx.opponent.get_threat_level()
	if opp_tl <= 50000 and ctx.opponent.monster_zone > 1:
		ctx.opponent.monster_zone -= 1
		ctx.opponent.monster_changed.emit()


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if _count_monsters_in_discard(ctx.owner) >= 10:
		return 10000
	return 0


func _count_monsters_in_discard(player: PlayerState) -> int:
	var count: int = 0
	for card in player.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			count += 1
	return count
