extends RefCounted
## ESC01: Special Collection 01 — card data only, split verbatim from card_data.gd.

var CARDS: Array[Dictionary] = [
	{
		"id": "ESC01-001",
		"name": "Godzilla(1954)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "When playing this from your hand, if you discard a <Godzilla> card from your hand you can play this card at a -4 rank. (Afterwards it's a Rank 8). \nIf this is in the same column as your opponent's Monster card this gains +3000 counter power.\nWhen you successfully counter your opponent's Monster card, place this at the bottom of your deck. ",
		"effect_script": "res://scripts/effects/esc01/esc01_001.gd"
	},
	{
		"id": "ESC01-002",
		"name": "Godzilla(1995)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 37000,
		"invasion_icon": 1,
		"description": "<Enter> Play up to 1 rank 3 or lower battle card with <Evolution> from your discard pile, then evolve it.",
		"effect_script": "res://scripts/effects/esc01/esc01_002.gd"
	},
	{
		"id": "ESC01-003",
		"name": "Godzilla(2016) 4th Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FOURTH_FORM],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Enter> If this card is in zone 8 and your monster card invaded this turn, you may discard 1 strategy card from your hand. If you do, advance your monster card by 1 zone.",
		"effect_script": "res://scripts/effects/esc01/esc01_003.gd"
	},
	{
		"id": "ESC01-004",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "If your monster card has 3 or more <Rage>, this card gains +5000 counter power.\nIf this card would be <Destroy>, place it on the bottom of your deck instead.",
		"effect_script": "res://scripts/effects/esc01/esc01_004.gd"
	},
	{
		"id": "ESC01-005",
		"name": "King Ghidorah(1991)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 24000,
		"invasion_icon": 1,
		"description": "<When Invading> If there are 3 or more cards under this card, reveal the top card of your deck and send it to your discard pile; <Destroy> 1 of your opponent's battle cards with rank equal to or lower than the revealed card's rank.",
		"effect_script": "res://scripts/effects/esc01/esc01_005.gd"
	},
	{
		"id": "ESC01-006",
		"name": "Mothra(imago)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 7000,
		"invasion_icon": 2,
		"description": "<Enter> You may discard your entire hand; for each strategy card discarded by this effect, increase your monster card's <Rage> by 1.",
		"effect_script": "res://scripts/effects/esc01/esc01_006.gd"
	},
]
