class_name EnterZone
extends EffectModule

## The one "card enters a zone" operation (GLOSSARY: Play, Appear, Evolve).
## Every engine path that puts a battle card or token into a zone runs
## `enter(...)`: the main-phase Play action, the effect plays from hand /
## deck / discard, tokens and Evolution. All of them are one act in the
## Japanese rules, 出現 (5.11 "play", 5.11.4 "play a token", 5.17.1 Evolve
## "重ねて出現させます"); the English text's play / appear split is a
## translation artifact (comprehensive_rules/rules-ja.txt). (A card moving between zones
## stays in play, so it is a Move — `move_stack` / `move_under` — not an
## entry; a card leaving the zones is LeaveZone's.) `enter` owns, in
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
## The invading monster and the strategy zones have their own plays:
## `play_monster` (the Play action, an effect play from the monster deck,
## the counter rank-up) and `play_strategy` (the Activate action, effect
## plays). They own placement, the signal, the log line and the standby
## entries the same way; their legality is RulesEngine's or the effect's.
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

## Where a monster card played as the new invading monster comes from.
enum MonsterSource {
	HAND,          ## the Play Monster action (normal, Burst or alternate cost)
	MONSTER_DECK,  ## an effect play (EBP03-074) or the counter rank-up (5.15.1.2)
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


static func rule_legal_zones(q: EffectQueries, player: PlayerState, opponent: PlayerState,
		card: Dictionary, by_effect: bool = true) -> Array[int]:
	## The zones (0-7) `card` may enter by rule. An empty `card` asks for
	## "any card": the card's required zones are not applied.
	var blocked: Array[int] = q.get_opponent_blocked_zones(opponent.player_id)
	var required: Array[int] = []
	if not by_effect and not card.is_empty():
		required = q.get_card_required_play_zones(player.player_id, card)
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


static func is_rule_legal(q: EffectQueries, player: PlayerState, opponent: PlayerState,
		card: Dictionary, zone_idx: int, by_effect: bool = true) -> bool:
	## Whether `card` may enter `zone_idx` by rule (cost legality is
	## RulesEngine's). Pure: reads state through `q`.
	return zone_idx in rule_legal_zones(q, player, opponent, card, by_effect)


func can_enter(player_id: int, card: Dictionary, zone_idx: int, by_effect: bool = true) -> bool:
	## `is_rule_legal` for `player_id` on the live state.
	return is_rule_legal(queries, game_state.players[player_id], game_state.players[1 - player_id],
			card, zone_idx, by_effect)


func legal_zones(player_id: int, card: Dictionary, by_effect: bool = true) -> Array[int]:
	## `rule_legal_zones` for `player_id` on the live state.
	return rule_legal_zones(queries, game_state.players[player_id], game_state.players[1 - player_id],
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
	## Signals: the destroy module's own on Overload; card_evolved (Evolve);
	## GameEvents.battle_card_played (the Play action); one log_message
	## (Play action, effect hand play, Evolve).
	## Returns false when the zone is rule-illegal for the source: nothing
	## enters, the card stays in its area (a deck or Evolve card goes back
	## on the deck bottom).
	var player := game_state.players[player_id]
	if by_effect and not can_enter(player_id, card, zone_idx):
		if (source == Source.DECK or source == Source.EVOLUTION) and not player.main_deck.has(card):
			player.put_on_deck_bottom(card)
		return false

	_take_from_area(player, card, source)

	if not _stacks_on_entry(player, card, zone_idx, source, stack_on_top):
		destruction.destroy(player, zone_idx, DestructionEngine.Cause.OVERLOAD)

	if source == Source.EVOLUTION:
		_announce_evolution(player, card, zone_idx)
	player.push_zone_card(zone_idx, card)
	if not by_effect and events != null:
		events.battle_card_played.emit(player_id, card, zone_idx)
	_log_entry(player_id, card, zone_idx, source, by_effect)

	# One play's leave-play, <Enter> and "when played" abilities share a pool.
	dispatcher.trigger_enter(player_id, card, by_effect, source == Source.EVOLUTION)
	if _fires_played(card, source):
		dispatcher.trigger_battle_card_played(
				player_id, card, zone_idx, source == Source.DECK or source == Source.EVOLUTION)
	return true


func play_monster(player_id: int, card: Dictionary, source: MonsterSource) -> void:
	## `card` becomes `player_id`'s new invading monster (5.11.2): every
	## monster play — the Play action, an effect play from the monster deck
	## and the counter rank-up (Q288: "You can no longer play a monster
	## card, so your opponent wins by Counter Victory.") — runs this, so each
	## fires the card's <Enter> and the "when your monster card is played"
	## watchers (hunterdurbin/godzilla-sim-issue-tracker#35 rows 14, 16).
	## Owns taking the card out of its area, pushing the old monster under
	## it, setting the current monster, GameEvents.monster_played, the Play
	## action's log line and the standby entries. The caller owns the rest
	## of the Play action — the once-per-turn flag, the +1 Rage (raised
	## before this call, so the log line shows it), Burst detection (set
	## before this call, so the log line names the Burst rank) and the
	## alternate cost. A monster play never clears Burst state: the Burst
	## card is discarded at the end phase wherever it is (12.5.2.1). Never
	## prompts.
	var player := game_state.players[player_id]
	var old_monster: Dictionary = player.current_monster
	if source == MonsterSource.MONSTER_DECK:
		player.remove_from_monster_deck(card)
	else:
		_take_from_area(player, card, Source.HAND)
	if not old_monster.is_empty():
		player.push_under_monster(old_monster)
	player.set_current_monster(card)
	if events != null:
		events.monster_played.emit(player_id, old_monster, card)
	if source == MonsterSource.HAND:
		_log_monster_play(player, card)
	# Snapshot the discard pile before <Enter> runs, so cards milled during
	# it don't retroactively qualify for can_play_from_discard_on_monster_played
	# (e.g. EBP02-048 milling EBP03-063 into the discard pile).
	var discard_snapshot: Array = player.discard_pile.duplicate()
	dispatcher.trigger_enter(player_id, card, source == MonsterSource.MONSTER_DECK)
	dispatcher.trigger_monster_played(player_id, old_monster, card, discard_snapshot)


func _log_monster_play(player: PlayerState, card: Dictionary) -> void:
	## The Play action's log line: a Burst play names its Burst rank.
	if player.burst_monster == card:
		var burst_effect := get_effect(card)
		var burst_rank: int = burst_effect.get_burst_rank() if burst_effect else -1
		h.log_message.emit(GameLog.burst_played(player.player_id, card.get("id", ""), burst_rank, player.rage))
	else:
		h.log_message.emit(GameLog.played_monster(player.player_id, card.get("id", ""), player.rage))


func play_strategy(player_id: int, card: Dictionary, source: Source, by_effect: bool = true,
		zone_idx: int = -1) -> int:
	## `card` is played into `player_id`'s strategy zone `zone_idx` (the
	## first empty one when -1), from `source` (HAND / DECK / DISCARD) —
	## the Activate action (by_effect = false) or an effect playing it,
	## regardless of rank (8.3.1 restricts only the Activate action)
	## (hunterdurbin/godzilla-sim-issue-tracker#35 row 17).
	## Owns taking the card out of the hand / discard pile if it is still
	## there (deck cards: the caller), placing it with this turn's stamp (so
	## the 7.2.3 start-phase discard treats it as placed this turn),
	## GameEvents.strategy_card_played, the log line and its <Enter> entry.
	## Never prompts. Returns the strategy zone index, or -1 (nothing moves)
	## when that zone is taken or there is no empty one.
	var player := game_state.players[player_id]
	var idx: int = zone_idx if zone_idx >= 0 else player.get_first_empty_strategy_zone_index()
	if idx < 0 or idx >= player.strategy_zones.size() or not player.strategy_zones[idx].is_empty():
		return -1
	_take_from_area(player, card, source)
	player.place_strategy(idx, card, game_state.turn_number)
	if events != null:
		events.strategy_card_played.emit(player_id, card, idx)
	h.log_message.emit(GameLog.played_strategy(player_id, card.get("id", ""), card.get("is_base", false)))
	dispatcher.trigger_enter(player_id, card, by_effect)
	return idx


func _take_from_area(player: PlayerState, card: Dictionary, source: Source) -> void:
	## Take the card out of the hand / discard pile if it is still there (the
	## Play action and a prompted discard play took it out already). Deck
	## cards are taken out by the caller (search / reveal); tokens and
	## Evolve's deck card have no area to leave here.
	if source != Source.HAND and source != Source.DISCARD:
		return
	var area: Array = player.hand if source == Source.HAND else player.discard_pile
	var card_id: String = card.get("id", "")
	for i in range(area.size() - 1, -1, -1):
		if area[i].get("id", "") == card_id:
			if source == Source.HAND:
				player.remove_hand_card_at(i)
			else:
				player.remove_discard_card_at(i)
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
		return queries.should_stack_on_play(player.player_id, card, zone_idx)
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
	## entry) keeps the flag on the dict for the board's zone sync.
	var under := player.get_zone_top_card(zone_idx)
	h.log_message.emit(GameLog.evolution(player.player_id, zone_idx, under.get("evolution_rank", -1),
			under.get("id", ""), card.get("id", ""), has_trigger(card, "on_enter")))
	h.card_evolved.emit(player.player_id, card, zone_idx)
	card["played_through_evolution"] = true


func _log_entry(player_id: int, card: Dictionary, zone_idx: int, source: Source, by_effect: bool) -> void:
	## The play's log line, before its triggered abilities (causal order).
	if not by_effect:
		h.log_message.emit(GameLog.played_battle(player_id, card.get("id", ""), zone_idx,
				has_trigger(card, "on_enter")))
	elif source == Source.HAND:
		var active := check_timing.active_card
		var source_id: String = active.get("id", "") if not active.is_empty() else ""
		h.log_message.emit(GameLog.effect_played_card(player_id, source_id, card.get("id", ""), zone_idx))


func move_stack(player_id: int, from_zone: int, to_zone: int) -> bool:
	## A zone's whole stack moves to another zone of the same field,
	## overloading the stack there (11.5). The moved card stays in play, so
	## it fires the area-changing on_zone_changed (EBP04-067 link), not
	## <Enter> or "when played", and no legality applies. Never prompts.
	## Signals: the destroy module's on Overload.
	## Returns false (nothing moves) for an empty source or to_zone == from_zone.
	var player := game_state.players[player_id]
	if from_zone == to_zone or not player.zone_has_cards(from_zone):
		return false
	destruction.destroy(player, to_zone, DestructionEngine.Cause.OVERLOAD)
	var moved_top: Dictionary = player.get_zone_top_card(from_zone)
	player.move_zone_stack(from_zone, to_zone)
	dispatcher.trigger_zone_changed(player.player_id, moved_top, from_zone, to_zone)
	return true


func move_under(player_id: int, from_zone: int, to_zone: int) -> bool:
	## "Put this card under <card> in your zones" (EBP03-042 / 043): from_zone's
	## top card goes to the bottom of to_zone's stack. It stays in a zone, so
	## it is a Move (hunterdurbin/godzilla-sim-issue-tracker#35 row 9): it fires the area-changing
	## on_zone_changed, not on_leave_play. The cards that were under it go to
	## the discard pile (tokens banished) — not destroyed (5.12.1.1). Never
	## prompts.
	## Returns false (nothing moves) for the same zone, a zone outside 0-7, or
	## when either zone is empty.
	var player := game_state.players[player_id]
	if from_zone == to_zone or from_zone not in range(8) or to_zone not in range(8):
		return false
	if not player.zone_has_cards(from_zone) or not player.zone_has_cards(to_zone):
		return false
	var stack: Array = player.clear_zone(from_zone)
	CardMover.banish_or_discard(player, stack.slice(1))
	player.add_card_under_zone(to_zone, stack[0])
	dispatcher.trigger_zone_changed(player_id, stack[0], from_zone, to_zone)
	return true
