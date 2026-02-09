extends CardEffect
# MBT-MB90 (Battle R3)
# <Enter> Look at the top card of your deck. You may send it to discard or put back on top.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck[0]
	# Show the card and let player choose
	var options: Array[Dictionary] = [top_card]
	var chosen := await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, options, options,
		"Top card of deck (select to send to discard, or skip to keep on top):")

	if not chosen.is_empty():
		# Send to discard
		ctx.owner.main_deck.pop_front()
		ctx.owner.discard_pile.append(top_card)
		ctx.owner.deck_changed.emit()
		ctx.owner.discard_changed.emit()
