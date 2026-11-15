class_name ModifierBreakdown
extends RefCounted

## Per-source modifier attribution for the card zoom overlay. Entries are
## plain Dictionaries so they survive var_to_bytes and the state delta codec:
##   { "stat": "cp"|"cp_double"|"threat"|"play_rank"|"zone_play_rank"|"field_rank"
##             |"cp_var_base"|"threat_var_base",
##     "amount": int,          # signed contribution
##     "source": String,       # template id of the granting card ("" = none)
##     "source_name": String,  # display-name fallback when the tr key is missing
##     "zone": int,            # affected zone index for per-zone stats, -1 otherwise
##     "owner": int,           # player id controlling the source card, -1 unknown
##     "src_loc": String }     # source card's board location: "z<idx>", "monster",
##                             # "strategy", or "" (hand/self/unknown)
##
## "cp_var_base"/"threat_var_base" are variable printed BASE stats ("this
## card's counter power X is ..."): they count toward the same sums as
## modifiers (the card dict stores 0) but render unsigned as the base value,
## and are appended even when 0 (X = 0 is a real value, not "no modifier").
##
## Only nonzero entries are ever created (append() skips zeros; the
## *_var_base kinds via append_base() are the one exception), so
## sum(entries) always equals the corresponding EffectQueries aggregate.
##
## "cp_double" is order-dependent: its amount is base CP + the running total
## of the entries appended before it (mirrors the doubling-after-additive
## ordering in EffectQueries.get_zone_cp_breakdown). The sum stays exact, but
## the entry only reads as "doubled" while doubling resolves last.


static func template_id(card_data: Dictionary) -> String:
	## Extract the template card number from an instance id.
	## "EBP01-001_1_0" -> "EBP01-001"; monster ids are already bare.
	var id: String = card_data.get("id", "")
	var parts := id.split("_")
	return parts[0] if not parts.is_empty() else id


static func entry(stat: String, amount: int, source_card: Dictionary, zone: int = -1, owner: int = -1, src_loc: String = "") -> Dictionary:
	return {
		"stat": stat,
		"amount": amount,
		"source": template_id(source_card),
		"source_name": str(source_card.get("name", "")),
		"zone": zone,
		"owner": owner,
		"src_loc": src_loc,
	}


static func append(list: Array, stat: String, amount: int, source_card: Dictionary, zone: int = -1, owner: int = -1, src_loc: String = "") -> void:
	## Append an entry unless the contribution is zero.
	if amount == 0:
		return
	list.append(entry(stat, amount, source_card, zone, owner, src_loc))


static func append_base(list: Array, stat: String, amount: int, source_card: Dictionary, zone: int = -1, owner: int = -1, src_loc: String = "") -> void:
	## Like append() but keeps zero amounts — variable printed bases must stay
	## visible (X = 0 is a real value, not "no modifier").
	list.append(entry(stat, amount, source_card, zone, owner, src_loc))


static func variable_base(entries: Array, stat: String) -> int:
	## Amount of the first stat-matching entry; -1 = no variable base present.
	for e in entries:
		if e.get("stat", "") == stat:
			return int(e.get("amount", 0))
	return -1


static func variable_zone_bases(zone_breakdown: Array) -> Array:
	## Per-zone "cp_var_base" amounts (-1 for zones without a variable base).
	var out: Array = []
	for zone_entries in zone_breakdown:
		out.append(variable_base(zone_entries if zone_entries is Array else [], "cp_var_base"))
	return out


static func sum(entries: Array) -> int:
	var total: int = 0
	for e in entries:
		total += int(e.get("amount", 0))
	return total


static func hand_entries(eh: EffectHandler, player_id: int, card: Dictionary) -> Array:
	## All entries for a card held in hand: global play-rank sources, strategy
	## hand-rank sources (strategy cards only), per-zone stacking modifiers,
	## and the placement-independent counter-power preview. The play_rank +
	## strategy portion matches GameSession.compute_hand_rank_mods and the cp
	## entry matches compute_hand_power_mods, so the panel agrees with the
	## hand badges.
	var out: Array = eh.queries.get_play_rank_breakdown(player_id, card)
	if card.get("card_type") == CardEnums.CardType.STRATEGY:
		out.append_array(eh.queries.get_strategy_hand_rank_breakdown(player_id, card))
	out.append_array(eh.queries.get_zone_play_rank_breakdown(player_id, card))
	append(out, "cp", eh.queries.get_hand_cp_preview(player_id, card), card, -1, player_id)
	var var_base_cp: int = eh.queries.get_hand_variable_base_cp(player_id, card)
	if var_base_cp >= 0:
		append_base(out, "cp_var_base", var_base_cp, card, -1, player_id)
	return out


# --- Board views (every CP / threat number the board shows) ---
#
# The board shows each player's numbers as of a counter: their CP as of
# their own counter phase (the counter they will make), their threat as of
# the opponent's (the counter it will face) — RulesEngine.counter_numbers'
# view. Labels, badges and zoom breakdowns all read through these, so they
# agree in any phase or turn.


static func in_cp_view(q: EffectQueries, pid: int, query: Callable) -> Variant:
	## Run a CP query for `pid` in the board's CP view (pid's counter phase).
	return q.in_counter_view(pid, query)


static func in_threat_view(q: EffectQueries, pid: int, query: Callable) -> Variant:
	## Run a threat query for `pid` in the board's threat view (the opponent's counter phase).
	return q.in_counter_view(1 - pid, query)


static func counter_labels(q: EffectQueries, players: Array[PlayerState]) -> Dictionary:
	## The board's counter numbers per player, [p0, p1] each:
	##   "cp"     — CP label modifier over the printed total (engagement
	##              restriction subtracted);
	##   "threat" — threat label modifier;
	##   "zone_cp", "strategy_cp", "monster_cp" — the CP badges.
	## The badges sum to the label except for a restricted card's printed CP,
	## which counter_numbers subtracts on top. Immunity and prevention stay
	## out. Zeros for a null `q`.
	var out := {"cp": [0, 0], "threat": [0, 0], "zone_cp": [[], []],
		"strategy_cp": [[], []], "monster_cp": [0, 0]}
	if not q:
		return out
	for pid in 2:
		var me := players[pid]
		var our_counter := RulesEngine.counter_numbers(q, me, players[1 - pid])
		out["cp"][pid] = int(our_counter["total_cp"]) - me.get_total_counter_power()
		out["threat"][1 - pid] = int(our_counter["effect_threat"])
		var badges: Dictionary = in_cp_view(q, pid, func() -> Dictionary: return {
			"zone_cp": q.get_zone_cp_modifiers(pid),
			"strategy_cp": q.get_strategy_cp_modifiers(pid),
			"monster_cp": q.get_monster_cp_modifier(pid),
		})
		for key in badges:
			out[key][pid] = badges[key]
	return out


static func threat_label_mod(q: EffectQueries, players: Array[PlayerState], pid: int) -> int:
	## `pid`'s threat label modifier alone (counter_labels' "threat").
	if not q:
		return 0
	return RulesEngine.counter_numbers(q, players[1 - pid], players[pid])["effect_threat"]


static func build_all(eh: EffectHandler, gs: GameState, viewer_id: int) -> Dictionary:
	## Pack every breakdown for the multiplayer state broadcast. Hand entries
	## are viewer-only ([] for the opponent) — hands are stripped from the
	## state message for the same privacy reason.
	var zone_cp: Array = []
	var field_rank: Array = []
	var threat: Array = []
	var monster_cp: Array = []
	var strategy_cp: Array = []
	var hand: Array = []
	for pid in range(2):
		var player := gs.players[pid]
		var q: EffectQueries = eh.queries
		field_rank.append(q.get_field_rank_breakdown(pid))
		threat.append(in_threat_view(q, pid, func() -> Array: return q.get_threat_level_breakdown(pid)))
		zone_cp.append(in_cp_view(q, pid, func() -> Array: return q.get_zone_cp_breakdown(pid)))

		var monster_entries: Array = []
		var monster_mod: int = in_cp_view(q, pid, func() -> int: return q.get_monster_cp_modifier(pid))
		append(monster_entries, "cp", monster_mod, player.current_monster, -1, pid, "monster")
		monster_cp.append(monster_entries)

		var strategy_slots: Array = []
		var strategy_mods: Array = in_cp_view(q, pid, func() -> Array: return q.get_strategy_cp_modifiers(pid))
		for si in range(strategy_mods.size()):
			var slot_entries: Array = []
			if si < player.strategy_zones.size():
				append(slot_entries, "cp", int(strategy_mods[si]), player.strategy_zones[si], -1, pid, "strategy")
			strategy_slots.append(slot_entries)
		strategy_cp.append(strategy_slots)

		var hand_cards: Array = []
		if pid == viewer_id:
			for card in player.hand:
				hand_cards.append(hand_entries(eh, pid, card))
		hand.append(hand_cards)
	return {
		"zone_cp": zone_cp,
		"field_rank": field_rank,
		"threat": threat,
		"monster_cp": monster_cp,
		"strategy_cp": strategy_cp,
		"hand": hand,
	}


static func collect(breakdowns: Dictionary, player_id: int, location: String, index: int) -> Array:
	## Select the entries relevant to one zoomed card from a packed
	## breakdown dict (client path; the host builds entries directly).
	var out: Array = []
	match location:
		"zone":
			out.append_array(_indexed(breakdowns, "zone_cp", player_id, index))
			out.append_array(_indexed(breakdowns, "field_rank", player_id, index))
		"monster":
			out.append_array(_per_player(breakdowns, "monster_cp", player_id))
			out.append_array(_per_player(breakdowns, "threat", player_id))
		"strategy":
			out.append_array(_indexed(breakdowns, "strategy_cp", player_id, index))
		"hand":
			out.append_array(_indexed(breakdowns, "hand", player_id, index))
	return out


static func normalize(breakdowns: Dictionary) -> Dictionary:
	## Cast every entry's amount/zone back to int. Binary sync preserves ints,
	## but JSON-based paths (tooling, replays) coerce them to floats — same
	## armor the rest of the client state receive applies.
	for key in breakdowns:
		_normalize_value(breakdowns[key])
	return breakdowns


static func _normalize_value(value: Variant) -> void:
	if value is Array:
		for item in value:
			_normalize_value(item)
	elif value is Dictionary and value.has("amount"):
		value["amount"] = int(value.get("amount", 0))
		value["zone"] = int(value.get("zone", -1))
		value["owner"] = int(value.get("owner", -1))


static func _per_player(breakdowns: Dictionary, key: String, player_id: int) -> Array:
	var per_player: Array = breakdowns.get(key, [])
	if player_id < 0 or player_id >= per_player.size():
		return []
	var entries: Variant = per_player[player_id]
	return entries if entries is Array else []


static func _indexed(breakdowns: Dictionary, key: String, player_id: int, index: int) -> Array:
	var per_player := _per_player(breakdowns, key, player_id)
	if index < 0 or index >= per_player.size():
		return []
	var entries: Variant = per_player[index]
	return entries if entries is Array else []
