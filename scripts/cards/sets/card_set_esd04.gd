extends RefCounted
## ESD04: Starter Deck 04 — card data only.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD04-004",
		"name": "Destoroyah Perfect Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"threat_level": 35000,
		"invasion_icon": 2,
		"description": "<Enter> You may discard a strategy card from your hand to decrease your opponent's <Rage> by 1.\n<Overwhelm> If you have a 「Godzilla vs. Destoroyah」 card in play, add +10,000 counter power to your total.",
		"effect_script": "res://scripts/effects/esd04/esd04_004.gd"
	},
]
