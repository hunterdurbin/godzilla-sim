class_name EnterZone
extends EffectModule

## The one "card enters a zone" operation (GLOSSARY: Play, Appear, Evolve).
## Every engine path that puts a battle card or token into a zone runs
## `enter(...)`: the main-phase Play action, the effect plays from hand /
## deck / discard, tokens and Evolution. All of them are one act in the
## Japanese rules, 出現 (5.11 "play", 5.11.4 "play a token", 5.17.1 Evolve
## "重ねて出現させます"); the English text's play / appear split is a
## translation artifact (comprehensive_rules/rules-ja.txt). (A stack moving between zones
## stays in play, so it is `move_stack`, not an entry.) `enter` owns, in
## this order:
##   1. rule legality (`is_rule_legal`) — refuse the zone and report "not
##      played"; the card stays in (or, for the deck, returns to) its area;
##   2. taking the card out of its area (hand / discard);
##   3. stack-on-play, or Overload of the old stack through the destroy
##      module (placement-time, ADR 0001);
##   4. placement and its signals / log line;
##   5. collecting the overloaded stack's leave-play entries, the card's
##      <Enter> entry and the "when played" watchers' entries, then
##      submitting them to CheckTiming together, so they share one pool.
##
## Legality is split: RULE legality lives here; COST legality (rank vs the
## opponent's monster zone + modifiers) stays in RulesEngine, which asks
## this class for rule legality. See "Rule legality" below for the checks,
## and `_fires_played` for which plays fire the "when played" watchers.

## Where the entering card comes from.
enum Source {
	HAND,        ## the Play action, or an effect playing it from the hand
	DECK,        ## an effect playing it from the deck (the caller took it out)
	DISCARD,     ## an effect playing it from the discard pile
	TOKEN,       ## an effect putting a token into existence
	EVOLUTION,   ## Evolve: played from the deck on top of the zone's battle card (5.17)
}

# --- Rule legality ---
#
# Every entry, Evolve included, is a play (出現), so every source shares one
# rule set. A zone (0-7) is rule-legal unless it is:
#   - the master's monster zone (5.11.1.1);
#   - a zone the opponent blocks — EBP02-055 "相手は…交戦カードを出現させる
#     ことができない"; Q270: "この効果は【進化】などのカードの効果による出現も
#     「できない」のですか？ A: はい、そうです。";
#   - for the Play action only (by_effect = false), outside the card's
#     required zones (an effect names its own zone).


static func rule_legal_zones(queries: EffectQueries, player: PlayerState, opponent: PlayerState,
		card: Dictionary, by_effect: bool = true) -> Array[int]:
	## The zones (0-7) `card` may enter by rule. An empty `card` asks for
	## "any card": the card's required zones are not applied.
	var blocked: Array[int] = queries.get_opponent_blocked_zones(opponent.player_id)
	var required: Array[int] = []
	if not by_effect and not card.is_empty():
		required = queries.get_card_required_play_zones(player.player_id, card)
	var legal: Array[int] = []
	for zone_idx in range(8):
		if zone_idx == player.monster_zone - 1:
			continue
		if zone_idx in blocked:
			continue
		if not required.is_empty() and zone_idx not in required:
			continue
		legal.append(zone_idx)
	return legal


static func is_rule_legal(queries: EffectQueries, player: PlayerState, opponent: PlayerState,
		card: Dictionary, zone_idx: int, by_effect: bool = true) -> bool:
	## Whether `card` may enter `zone_idx` by rule (cost legality is
	## RulesEngine's). Pure: reads state through `queries`.
	return zone_idx in rule_legal_zones(queries, player, opponent, card, by_effect)


func can_enter(player_id: int, card: Dictionary, zone_idx: int, by_effect: bool = true) -> bool:
	## `is_rule_legal` for `player_id` on the live state.
	return is_rule_legal(h.queries, game_state.players[player_id], game_state.players[1 - player_id],
			card, zone_idx, by_effect)


func legal_zones(player_id: int, card: Dictionary, by_effect: bool = true) -> Array[int]:
	## `rule_legal_zones` for `player_id` on the live state.
	return rule_legal_zones(h.queries, game_state.players[player_id], game_state.players[1 - player_id],
			card, by_effect)


func enter(player_id: int, card: Dictionary, zone_idx: int, source: Source,
		by_effect: bool = true, stack_on_top: bool = false) -> bool:
	## `card` enters `zone_idx` of `player_id`'s field from `source`.
	## by_effect: false only for the main-phase Play action, whose legality
	##   RulesEngine decided when it offered the action (cost + rule), and
	##   whose caller already took the card out of the hand to pay its cost.
	## stack_on_top: "play it on top of" (Source.DECK): keep the old stack.
	## Where the card must be: HAND / DISCARD — still in that area, or
	## already taken out by the caller; DECK — already taken out; TOKEN /
	## EVOLUTION — a card in no area.
	## Never prompts. Overload runs the destroy module, so replacement
	## effects (on_would_be_destroyed) apply at once; everything else it
	## triggers only enters standby (CheckTiming.submit).
	## Signals: hand_changed (HAND) / discard_changed (DISCARD) when it
	## takes the card out, deck_changed when a refused deck card goes back;
	## the destroy module's own signals on Overload; card_evolved (Evolve);
	## GameEvents.battle_card_played + hand_changed (the Play action);
	## zones_changed; one log_message (Play action, effect hand play, Evolve).
	## Returns false when the zone is rule-illegal for the source: nothing
	## enters, the card stays in its area (a deck or Evolve card goes back
	## on the deck bottom).
	var player := game_state.players[player_id]
	if by_effect and not can_enter(player_id, card, zone_idx):
		if (source == Source.DECK or source == Source.EVOLUTION) and not player.main_deck.has(card):
			player.main_deck.append(card)
			player.deck_changed.emit()
		return false

	_take_from_area(player, card, source)

	var entries: Array = []
	if not _stacks_on_entry(player, card, zone_idx, source, stack_on_top):
		entries.append_array(h.destroy(player, zone_idx, DestructionEngine.Cause.OVERLOAD).entries)

	if source == Source.EVOLUTION:
		_announce_evolution(player, card, zone_idx)
	player.push_zone_card(zone_idx, card)
	if not by_effect:
		if h.events != null:
			h.events.battle_card_played.emit(player_id, card, zone_idx)
		# The Play action's caller took the card out to pay its cost.
		player.hand_changed.emit()
	player.zones_changed.emit()
	_log_entry(player_id, card, zone_idx, source, by_effect)

	# One play's leave-play, <Enter> and "when played" entries share a pool.
	entries.append_array(h.collect_enter_entries(
			player_id, card, by_effect, source == Source.EVOLUTION))
	if _fires_played(card, source):
		entries.append_array(h.collect_battle_card_played_entries(
				player_id, card, zone_idx, source == Source.DECK or source == Source.EVOLUTION))
	check_timing.submit(entries)
	return true


func _take_from_area(player: PlayerState, card: Dictionary, source: Source) -> void:
	## Take the card out of the hand / discard pile if it is still there (the
	## Play action and a prompted discard play took it out already). Deck
	## cards are taken out by the caller (search / reveal); tokens and
	## Evolve's deck card have no area to leave here.
	var area: Array
	match source:
		Source.HAND:
			area = player.hand
		Source.DISCARD:
			area = player.discard_pile
		_:
			return
	var card_id: String = card.get("id", "")
	for i in range(area.size() - 1, -1, -1):
		if area[i].get("id", "") == card_id:
			area.remove_at(i)
			if source == Source.HAND:
				player.hand_changed.emit()
			else:
				player.discard_changed.emit()
			return


func _stacks_on_entry(player: PlayerState, card: Dictionary, zone_idx: int, source: Source,
		stack_on_top: bool) -> bool:
	## Whether the card goes on top of the zone's stack instead of
	## overloading it: Evolve always, "play it on top of" effects, and a
	## stack-on-play card (Godzilla Jr. on Little Godzilla), whether the Play
	## action or an effect plays it.
	if source == Source.EVOLUTION or stack_on_top:
		return true
	if player.zone_has_cards(zone_idx):
		return h.should_stack_on_play(player.player_id, card, zone_idx)
	return false


func _fires_played(card: Dictionary, source: Source) -> bool:
	## "Whenever … plays a battle card" (…が出現するたび) watchers: every
	## play — hand, deck, discard pile, Evolve, and battle tokens. Evolve
	## plays from the deck (Q176: "山札から…重ねて出現させる"), so it counts
	## as played from the deck for EBP04-028 / EBP04-072.
	match source:
		Source.HAND, Source.DECK, Source.DISCARD, Source.EVOLUTION:
			return true
		Source.TOKEN:
			return card.get("card_type") == CardEnums.CardType.BATTLE
	return false


func _announce_evolution(player: PlayerState, card: Dictionary, zone_idx: int) -> void:
	## Evolve's log line and card_evolved signal, before the new card lands
	## on top. The early through-evolution mark (re-stamped with the <Enter>
	## entry) keeps the flag on the dict for the zones_changed sync.
	var under := player.get_zone_top_card(zone_idx)
	h.log_message.emit(GameLog.evolution(player.player_id, zone_idx, under.get("evolution_rank", -1),
			under.get("id", ""), card.get("id", ""), h.has_trigger(card, "on_enter")))
	h.card_evolved.emit(player.player_id, card, zone_idx)
	card["played_through_evolution"] = true


func _log_entry(player_id: int, card: Dictionary, zone_idx: int, source: Source, by_effect: bool) -> void:
	## The play's log line, before its triggered abilities (causal order).
	if not by_effect:
		h.log_message.emit(GameLog.played_battle(player_id, card.get("id", ""), zone_idx,
				h.has_trigger(card, "on_enter")))
	elif source == Source.HAND:
		var active := check_timing.active_card
		var source_id: String = active.get("id", "") if not active.is_empty() else ""
		h.log_message.emit(GameLog.effect_played_card(player_id, source_id, card.get("id", ""), zone_idx))


func move_stack(player_id: int, from_zone: int, to_zone: int) -> bool:
	## A zone's whole stack moves to another zone of the same field,
	## overloading the stack there (11.5). The moved card stays in play, so
	## it fires the area-changing on_zone_changed (EBP04-067 link), not
	## <Enter> or "when played", and no legality applies. Never prompts.
	## Signals: the destroy module's on Overload, then zones_changed.
	## Returns false (nothing moves) for an empty source or to_zone == from_zone.
	var player := game_state.players[player_id]
	if from_zone == to_zone or not player.zone_has_cards(from_zone):
		return false
	var entries: Array = h.destroy(player, to_zone, DestructionEngine.Cause.OVERLOAD).entries
	var moved_top: Dictionary = player.get_zone_top_card(from_zone)
	var stack: Array = player.zones[from_zone]
	player.zones[from_zone] = []
	player.zones[to_zone] = stack
	player.zones_changed.emit()
	entries.append_array(h.collect_zone_changed_entries(player.player_id, moved_top, from_zone, to_zone))
	check_timing.submit(entries)
	return true
