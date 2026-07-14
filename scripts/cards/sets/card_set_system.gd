extends RefCounted
## SYSTEM cards — non-deck marker cards (e.g. the Rage marker) that can
## be placed in stacks and counted by effects. They are never part of any
## deck. Card data only, split verbatim from card_data.gd.

var CARDS: Array[Dictionary] = [
	{
		"id": "RAGE-MARKER",
		"name": "Rage",
		"card_type": CardEnums.CardType.RAGE,
		"colors": [],
		"traits": [],
		"description": "Placeholder representing 1 <Rage> placed by an effect. Has its own card type so the engine never treats it as a Monster, Battle, or Strategy card. Never enters the deck or discard pile."
	},
]
