class_name CardUtils

## Pure static helpers for querying card Dictionary data.
## Stateless — use for trait/color/type checks that otherwise inline
## `card.get("traits", [])` / `card.get("card_type") == ...` patterns.


static func has_trait(card: Dictionary, trait_id: int) -> bool:
	return trait_id in card.get("traits", [])


static func has_any_trait(card: Dictionary, trait_ids: Array) -> bool:
	var card_traits: Array = card.get("traits", [])
	for t in trait_ids:
		if t in card_traits:
			return true
	return false


static func has_color(card: Dictionary, color: int) -> bool:
	return color in card.get("colors", [])


static func is_type(card: Dictionary, card_type: int) -> bool:
	return card.get("card_type") == card_type


static func is_battle(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.BATTLE


static func is_strategy(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.STRATEGY


static func is_monster(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.MONSTER
