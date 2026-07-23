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
	# EPR-011/012/013 are rage-card printings — rage cards live once in
	# card_set_system.gd, so promo printings get no entries here.
	{
		"id": "EPR-014",
		"name": "Anti-Gravity Beam",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"description": "<Destroy> all of your opponent's battle cards in the same column as your monster card.",
		"effect_script": "res://scripts/effects/epr/epr_014.gd"
	},
	{
		"id": "EPR-015",
		"name": "Godzilla(GODZILLA THE RIDE: GREAT CLASH)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.GODZILLA_THE_RIDE],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "If you have a card with <《GODZILLA THE RIDE》> in your discard pile, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/epr/epr_015.gd"
	},
	{
		"id": "EPR-016",
		"name": "KIJU Type 0 -G BREAKER-",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.GODZILLA_THE_RIDE],
		"counter_power": 8000,
		"invasion_icon": 2,
		"description": "At the beginning of your counter phase, you may place 1 <《Mech》>, <《Weapon》>, or <《GODZILLA THE RIDE》> battle card from your hand under this card. If you do, <Destroy> this card at the beginning of the end phase.\nIf there is a card under this card, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/epr/epr_016.gd"
	},
]
