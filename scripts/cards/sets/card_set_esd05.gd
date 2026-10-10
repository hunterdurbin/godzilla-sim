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
	{
		"id": "ESD05-003",
		"name": "Dorat",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.DORAT],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Overwhelm> <Enter> Send the top 3 cards of your deck to your discard pile. (Active if your monster card is in the same zone as or ahead of your opponent's monster card.)",
		"effect_script": "res://scripts/effects/esd05/esd05_003.gd"
	},
	{
		"id": "ESD05-004",
		"name": "Godzillasaurus",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GODZILLASAURUS],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "If there is a card under your monster card, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/esd05/esd05_004.gd"
	},
]
