extends CardEffect

## EFC01-003: Jet Jaguar(Gojika Festival) - Battle Rank 6 (Red)
## <Enter> You may discard a card with both <Gigan> and <Festival Godzilla> from your hand.
## If you do, search your deck for a battle card with <Weapon> or <Mech> and
## invasion_icon = 2, add it to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	# Discard a card with both GIGAN and Festival Godzilla traits from hand (optional)
	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			var traits: Array = card.get("traits", [])
			return CardEnums.CardTrait.GIGAN in traits and CardEnums.CardTrait.FESTIVAL_GODZILLA in traits,
		"Discard a Gigan+Festival Godzilla card to search for a Weapon/Mech battle card (or skip):",
		true)

	if discarded.is_empty():
		return

	# Search deck for a battle card with WEAPON or MECH trait and invasion_icon = 2
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			if card.get("invasion_icon", 0) != 2:
				return false
			var traits: Array = card.get("traits", [])
			return CardEnums.CardTrait.WEAPON in traits or CardEnums.CardTrait.MECH in traits,
		"Choose a Weapon or Mech battle card with invasion icon 2:")

	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
