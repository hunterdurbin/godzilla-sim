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
		"id": "ESD03-006",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 2000,
		"invasion_icon": 2,
		"description": "<Enter> Reduce your opponent's rank I monster card's <Rage> by 1.\n<Overwhelm> This card gains +3000 counter power. (Active if your monster card is in the same zone as or ahead of your opponent's monster card.)",
		"effect_script": "res://scripts/effects/esd03/esd03_006.gd"
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
	{
		"id": "ESD03-008",
		"name": "Humanity's Crime and Punishment",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MINUS_ZERO],
		"invasion_icon": 1,
		"description": "If your monster card is rank III or higher, each player chooses 1 battle card in their zones, then <Destroy> all other battle cards. (You declare which of your battle cards remains first.)\nIf your monster card has 3 or more <Rage>, your opponent discards cards until they have 2 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/esd03/esd03_008.gd"
	},
]
