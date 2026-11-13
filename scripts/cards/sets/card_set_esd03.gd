extends RefCounted
## ESD03: Starter Deck 03 — card data only.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESD03-001",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "<When Invading> If this card invades by discarding a monster card from your hand, increase this card's <Rage> by 1. (If this card invades 2 zones, this activates twice.)",
		"effect_script": "res://scripts/effects/esd03/esd03_001.gd"
	},
	{
		"id": "ESD03-002",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"threat_level": 13000,
		"invasion_icon": 1,
		"description": "<Enter> <Destroy> all rank 3 or lower battle cards of each player.",
		"effect_script": "res://scripts/effects/esd03/esd03_002.gd"
	},
	{
		"id": "ESD03-003",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"threat_level": 21000,
		"invasion_icon": 1,
		"description": "<Enter> Reveal the top card of your deck. If it's a monster card, add it to your hand. Otherwise, discard it.\n<Opponent’s Turn> <Dominate> At the beginning of the counter phase, <Destroy> all of your opponent's rank 6 or lower battle cards in the same column as this card. (Active if your monster card is in the same zone as or ahead of your opponent's monster card.)",
		"effect_script": "res://scripts/effects/esd03/esd03_003.gd"
	},
	{
		"id": "ESD03-004",
		"name": "Godzilla(2026)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MINUS_ZERO],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "<Enter> Reveal cards from the top of your deck equal to the number of the zone this card is in. Add 1 red monster card with <《Godzilla》> from among them to your hand, then return the rest to your deck and shuffle it.",
		"effect_script": "res://scripts/effects/esd03/esd03_004.gd"
	},
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
		"description": "<Enter> Reduce your opponent's rank I monster card's <Rage> by 1.\n<Dominate> This card gains +3000 counter power. (Active if your monster card is in the same zone as or ahead of your opponent's monster card.)",
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
		"description": "<Awakening 6> This card gains +3000 counter power. (Active if your monster card is in zone 6 or beyond.)\n<Dominate> If your monster card invaded this turn, you may play this card from your hand with its rank reduced by 1. (Active if your monster card is in the same zone as or ahead of your opponent's monster card. After being played, this card is rank 6.)",
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
