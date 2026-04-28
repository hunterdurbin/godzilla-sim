extends CardEffect
# MBT-MB90 (Battle R3)
# <Enter> Look at the top card of your deck. You may send it to discard or put back on top.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck[0]
	# Show the card and let player choose
	var options: Array[Dictionary] = [top_card]
	var chosen := await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, options, options,
		tr("STR_EFF_DECK_TOP_OR_SKIP"))

	if not chosen.is_empty():
		# Skip the auto-reveal — the player already saw the card in the prompt above.
		await ctx.mill_one(false)
