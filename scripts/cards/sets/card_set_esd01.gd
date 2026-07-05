extends RefCounted
## ESD01: Starter Deck 01 - Godzilla Minus One — card data only, split verbatim from card_data.gd.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD01-001",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "ESD01-002",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 8000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_002.gd",
		"description": "<When Invading> Search your deck for up to 1 rank Ⅲ card named 「Godzilla(2023)」 with <Burst> , reveal it, add it to your hand, then shuffle your deck. (If you invaded 2 zones, activate this effect 2 times)"
	},
	{
		"id": "ESD01-003",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_003.gd",
		"description": "If this card has 2 or more <Rage> , this card gains +5000 threat level."
	},
	{
		"id": "ESD01-004",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 38000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_004.gd",
		"description": "<When Invading> If this card has 2 or more <Rage> , your opponent discards cards until they have 2 cards remaining in their hand."
	},
	{
		"id": "ESD01-005",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 12000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_005.gd",
		"description": "<Burst1> (You can play this card from rank I. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> Your opponent discards cards until they have 4 cards remaining in their hand."
	},
	{
		"id": "ESD01-006",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_006.gd",
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> <Destroy> 1 of your opponent’s rank 4 or lower battle cards."
	},
	{
		"id": "ESD01-007",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 38000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_007.gd",
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> <Destroy> all of your opponent’s battle cards in the same column as this card."
	},
	{
		"id": "ESD01-008",
		"name": "Shinseimaru",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.BOAT],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "(Battle cards in your hand can be played if their rank is equal to or lower than the number in the zone where the opponent's monster card is.)"
	},
	{
		"id": "ESD01-009",
		"name": "Reinforcements",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.BOAT],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_009.gd",
		"description": "<Awakening4> This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)"
	},
	{
		"id": "ESD01-010",
		"name": "City of Tokyo",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CITY],
		"counter_power": 0,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_010.gd",
		"description": "If your monster card has 2 or more <Rage> , your other battle card in zone 8 gains +5000 counter power.\n<Awakening6> Your other battle card in zone 8 gains +5000 counter power. (Active if your monster card is in zone 6 or beyond.)"
	},
	{
		"id": "ESD01-011",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_011.gd",
		"description": "<Enter> If your monster card has 2 or more <Rage> , reduce your opponent's <Rage> by 1.\nWhen this card is <Destroy> , place this card on the bottom of your deck instead."
	},
	{
		"id": "ESD01-012",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 7000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_012.gd",
		"description": "<Your Turn> When you play a monster card, you may move this card to an unoccupied zone.\nIf this card is in zone 8, this card gains +3000 counter power.\nWhen this card is <Destroy> , place this card on the bottom of your deck instead."
	},
	{
		"id": "ESD01-013",
		"name": "Ginza Annihilated",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_013.gd",
		"description": "<Your Turn> Whenever your monster card's <Rage> is increased, <Destroy> 1 of your opponent's rank 6 or lower battle cards."
	},
	{
		"id": "ESD01-014",
		"name": "Godzilla Emerges",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_014.gd",
		"description": "If your monster card has 2 or more <Rage> , search your deck for up to 1 battle card named 「Godzilla(2023)」, play it, then shuffle your deck."
	},
	{
		"id": "ESD01-015",
		"name": "Operation Wadatsumi",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_015.gd",
		"description": "Your opponent discards cards until they have 2 cards remaining in their hand."
	},
	{
		"id": "ESD01-016",
		"name": "Heat Ray",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_016.gd",
		"description": "<Destroy> all of your opponent’s battle cards in the same column as your monster card."
	},
]
