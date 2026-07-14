extends RefCounted
## EPR: Promo Cards — card data only, split verbatim from card_data.gd.

var CARDS: Array[Dictionary] = [
	{
		"id": "EPR-001",
		"name": "Godzilla, King of the Monsters 70th",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-002",
		"name": "GODZILLA THE ART｜Eric Haze",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-003",
		"name": "Godzilla Galaxy Odyssey",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-004",
		"name": "Heat Ray",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "<Destroy> all of your opponent's battle cards in the same column as your monster card.",
		"effect_script": "res://scripts/effects/epr/epr_004.gd"
	},
	{
		"id": "EPR-005",
		"name": "Godzilla's Bite",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "<Destroy> all of your opponent's battle cards in the same column as your monster card.",
		"effect_script": "res://scripts/effects/epr/epr_005.gd"
	},
	{
		"id": "EPR-006",
		"name": "Godzilla, King of the Monsters - Kaiju on the Earth LEGENDS",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-007",
		"name": "Chibi Godzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CHIBI, CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-008",
		"name": "Chibi Godzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CHIBI, CardEnums.CardTrait.GODZILLA],
		"threat_level": 13000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-009",
		"name": "Chibi Godzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CHIBI, CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1
	},
	{
		"id": "EPR-010",
		"name": "Chibi Godzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CHIBI, CardEnums.CardTrait.GODZILLA],
		"threat_level": 37000,
		"invasion_icon": 1
	},
]
