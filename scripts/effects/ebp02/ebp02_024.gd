extends CardEffect

## EBP02-024: Biollante Rose Form - Monster Rank 1 (Blue)
## If this card is in your monster deck, at the start of the game it will be played in Zone 5.
## This card cannot advance nor invade.
## (Start zone handled via "start_zone": 5 in card_data.gd)


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false
