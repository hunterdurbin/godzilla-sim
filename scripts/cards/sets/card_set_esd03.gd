extends RefCounted
## ESD03: Starter Deck 03 — card data only.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD03-005",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"threat_level": 30000,
		"invasion_icon": 1,
		"description": "If there is a rank IV monster card underneath this, add +15,000 threat.\nAt the beginning of your end phase, if this has 3 or more <Rage>, you may advance 1 zone.\n<Awakening 8> This card gains +15,000 threat.",
		"effect_script": "res://scripts/effects/esd03/esd03_005.gd"
	},
]
