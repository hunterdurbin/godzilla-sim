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
	{
		"id": "EPR-017",
		"name": "Godzilla(GODZILLA THE RIDE: GREAT CLASH)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.GODZILLA_THE_RIDE],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "<Enter> Place 1 card with <《GODZILLA THE RIDE》> from your discard pile under your monster card.",
		"effect_script": "res://scripts/effects/epr/epr_017.gd"
	},
	{
		"id": "EPR-018",
		"name": "GODZILLA THE RIDE: GREAT CLASH",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA_THE_RIDE],
		"invasion_icon": 1,
		"description": "Discard 1 card from your hand. If you do, search your deck for up to 1 <《Mech》>, <《Weapon》>, or <《GODZILLA THE RIDE》> battle card, reveal it, add it to your hand, then shuffle your deck.",
		"effect_script": "res://scripts/effects/epr/epr_018.gd"
	},
	{
		"id": "EPR-019",
		"name": "Gravity Beam",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.FEST],
		"invasion_icon": 2,
		"description": "If you have a battle card with both <《Fest》> and <《King Ghidorah》> in your zones, you can play this card from your hand with its rank reduced by 3.\nYour opponent discards cards until they have 3 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/epr/epr_019.gd"
	},
	{
		"id": "EPR-020",
		"name": "Godzilla(2003)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 17000,
		"invasion_icon": 2,
		"description": "Whenever you discard a battle card from your hand, reduce your opponent's <Rage> by 1.\n<Your Turn> When your opponent's <Rage> becomes 0, increase this card's <Rage> by 2. (Does not activate if their <Rage> was already 0.)",
		"effect_script": "res://scripts/effects/epr/epr_020.gd"
	},
]
