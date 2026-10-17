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
		"id": "ESD04-002",
		"name": "Destoroyah Aggregate Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"threat_level": 10000,
		"invasion_icon": 1,
		"description": "<When Invading> Evolve 1 of your rank 6 or lower battle cards with <Evolution>. (If this card invades 2 zones, this activates twice.)",
		"effect_script": "res://scripts/effects/esd04/esd04_002.gd"
	},
	{
		"id": "ESD04-003",
		"name": "Destoroyah Flying Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"threat_level": 21000,
		"invasion_icon": 1,
		"description": "<Enter> Return up to 1 card named 「Godzilla vs. Destoroyah」 from your discard pile to your hand.\n<When Invading> Place 1 battle card with <《Destoroyah》> from your discard pile on the bottom of your deck. (If this card invades 2 zones, this activates twice.)",
		"effect_script": "res://scripts/effects/esd04/esd04_003.gd"
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
