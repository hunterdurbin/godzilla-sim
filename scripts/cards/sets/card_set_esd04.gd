extends RefCounted
## ESD04: Starter Deck 04 — card data only.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD04-001",
		"name": "Destoroyah Juvenile Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "<Overwhelm> At the beginning of your end phase, you may reveal 1 battle card from your hand and place it on the bottom of your deck. If you do, draw 1 card. (Active if your monster card is in the same zone as or ahead of your opponent's monster card.)",
		"effect_script": "res://scripts/effects/esd04/esd04_001.gd"
	},
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
	{
		"id": "ESD04-006",
		"name": "Godzilla vs. Destoroyah",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [],
		"invasion_icon": 2,
		"description": "<Opponent’s Turn> For each battle card with <《Destoroyah》> in your zones, your monster card gains +5000 threat. (Cards stacked through evolution count as 1 card.)",
		"effect_script": "res://scripts/effects/esd04/esd04_006.gd"
	},
]
