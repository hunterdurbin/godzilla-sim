class_name BotDeckProfile
extends RefCounted

## Pure, static deck-shape analysis for the KAIJU evaluator: "can this deck
## realistically win by invasion?". The hard gate is the opponent's zone-8
## battle card — an invading monster cannot advance past zone 8 while it
## stands (invasion_resolver), so zone-destruction effects carry the largest
## share. Card tags come through an injected Callable (same pattern as
## ReplayMetrics.id_to_card) so unit tests run on fixture dicts without an
## EffectHandler.

const CLEAR_SATURATION := 2.0 # 2+ destroys_zone effects = full z8-clear capability
const ADVANCE_SATURATION := 3.0
const TEMPO_FULL_DENSITY := 0.40 # avg invasion steps per card for full tempo marks
const VIABILITY_FLOOR := 0.05 # never fully zero the zone terms


## tags_for_card: Callable(card: Dictionary) -> Array[String] (bot tags).
## invasion_score / counter_score: the analyze_deck playstyle scores.
static func compute(all_cards: Array, tags_for_card: Callable,
		invasion_score: float, counter_score: float) -> Dictionary:
	if all_cards.is_empty():
		return {}

	var destroy_count: int = 0
	var advance_count: int = 0
	var invade2_count: int = 0
	var invade_steps: int = 0
	for card in all_cards:
		var tags: Array = tags_for_card.call(card)
		if "destroys_zone" in tags:
			destroy_count += 1
		if "advances_opponent" in tags:
			advance_count += 1
		var icon: int = int(card.get("invasion_icon", 0))
		if icon >= 2:
			invade2_count += 1
		invade_steps += mini(icon, 2)

	var clear_capability := clampf(destroy_count / CLEAR_SATURATION, 0.0, 1.0)
	var tempo := clampf(invade_steps / (TEMPO_FULL_DENSITY * all_cards.size()), 0.0, 1.0)
	var advance := clampf(advance_count / ADVANCE_SATURATION, 0.0, 1.0)
	var style := invasion_score / maxf(invasion_score + counter_score, 0.001)

	return {
		"invasion_viability": clampf(
				0.40 * clear_capability + 0.30 * tempo + 0.15 * advance + 0.15 * style,
				VIABILITY_FLOOR, 1.0),
		"clear_capability": clear_capability,
		"destroy_count": destroy_count,
		"advance_opp_count": advance_count,
		"invade2_count": invade2_count,
		"invade_steps": invade_steps,
		"invasion_score": invasion_score,
		"counter_score": counter_score,
	}
