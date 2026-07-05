extends RefCounted
## EFC01: Festival Collection 01 — card data only, split verbatim from card_data.gd.

var CARDS: Array[Dictionary] = [
	{
		"id": "EFC01-001",
		"name": "Godzilla(Gojika Festival)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 28000,
		"invasion_icon": 1,
		"description": "<Burst3> If every area adjacent to this has a Battle Card with <Festival Godzilla>, add +10,000 counter power.",
		"effect_script": "res://scripts/effects/efc01/efc01_001.gd"
	},
	{
		"id": "EFC01-002",
		"name": "Gigan(Gojika Festival)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.FEST],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Enter> If this is in the adjacent area of your monster card, discard a card from the top of your deck. If it is a battle card, return up to one of your monster cards from your discard pile.",
		"effect_script": "res://scripts/effects/efc01/efc01_002.gd"
	},
	{
		"id": "EFC01-003",
		"name": "Jet Jaguar(Gojika Festival)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.JET_JAGUAR, CardEnums.CardTrait.MECH, CardEnums.CardTrait.FEST],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "<Enter> You may discard 1 card with both <Gigan> and <Festival Godzilla> from your hand. If you do, search your deck for 1 <Weapon> or <Mech> battle card with <Invade 2>. Reveal it, add it to your hand and shuffle the deck.",
		"effect_script": "res://scripts/effects/efc01/efc01_003.gd"
	},
	{
		"id": "EFC01-004",
		"name": "Hedorah(2021)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.HEDORAH, CardEnums.CardTrait.FEST],
		"counter_power": 7000,
		"invasion_icon": 1,
		"description": "When playing this card from your hand, you can reduce its rank by 1 for each battle card in your opponent's zones. (After being played this card is rank 8)",
		"effect_script": "res://scripts/effects/efc01/efc01_004.gd"
	},
	{
		"id": "EFC01-005",
		"name": "Godzilla Appears in Godzilla Festival",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [],
		"invasion_icon": 2,
		"description": "《Your Turn》 When your monster card enters, reveal the top 5 cards of your deck. Add all 《Festival Godzilla》 cards to your hand and discard the rest. At the beginning of your counter phase, discard your hand.",
		"effect_script": "res://scripts/effects/efc01/efc01_005.gd"
	},
	{
		"id": "EFC01-006",
		"name": "King Ghidorah's Defense",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [],
		"invasion_icon": 1,
		"description": "<Opponent's Turn> If the opponent has 2 or less battle cards in their zones, none of the battle cards in your zones can be destroyed by your opponent's effects.",
		"effect_script": "res://scripts/effects/efc01/efc01_006.gd"
	},
]
