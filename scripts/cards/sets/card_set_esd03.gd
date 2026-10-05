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
	{
		"id": "ESD03-007",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "<Awakening 6> This card gains +3000 counter power. (Active if your monster card is in zone 6 or beyond.)\n<Overwhelm> If your monster card invaded this turn, you may play this card from your hand with its rank reduced by 1. (Active if your monster card is in the same zone as or ahead of your opponent's monster card. After being played, this card is rank 6.)",
		"effect_script": "res://scripts/effects/esd03/esd03_007.gd"
	},
]
