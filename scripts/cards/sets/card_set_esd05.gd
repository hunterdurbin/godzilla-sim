extends RefCounted
## ESD05: Starter Deck 05 — card data only.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD05-002",
		"name": "King Ghidorah(1991)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 37000,
		"invasion_icon": 2,
		"description": "<Enter> Send the top card of your main deck to your discard pile. When you do so, <Destroy> any number of your opponent's battle cards that add up to the discarded card's rank or less.",
		"effect_script": "res://scripts/effects/esd05/esd05_002.gd"
	},
]
