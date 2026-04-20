extends CardEffect
# Sanda
# <Opponent's Turn> Each time opp plays a card from their deck, if this is in area 5 →
# search own deck for up to 1 card, add to hand.
# Note: "plays from deck" is a rare case. on_battle_card_played fires when a battle card
# is played (including from deck effects). Using on_monster_played for monster plays.
# TODO: needs a generic on_card_played_from_deck hook for complete accuracy.


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_battle_card_played(ctx: EffectContext, _zone_index: int) -> void:
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 4:  # Zone 5 = index 4
		return
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(_card): return true,
		"Search your deck for a card to add to your hand (or skip):")
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
