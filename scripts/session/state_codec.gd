class_name StateCodec
extends RefCounted

## Pure functions for the multiplayer state wire format: card<->id mapping,
## PlayerState serialization, delta encoding, payload compression, and state
## hashing. No node or session dependencies — everything is static and
## testable headless.
##
## The wire format is load-bearing: host and client must agree byte-for-byte.
## Do not change encodings here without bumping the protocol expectations on
## both sides.

const STATE_COMPRESS_THRESHOLD: int = 1024
const STATE_FLAG_RAW: int = 0x00
const STATE_FLAG_GZIP: int = 0x01


# --- Card <-> instance-id mapping ---

static func card_to_id(card: Dictionary) -> String:
	return card.get("id", "")


static func cards_to_ids(cards: Array) -> Array:
	var ids: Array = []
	for c in cards:
		ids.append(c.get("id", "") if c is Dictionary else "")
	return ids


static func id_to_card(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var base_id := instance_id
	var underscore_pos := instance_id.find("_")
	if underscore_pos != -1:
		base_id = instance_id.substr(0, underscore_pos)
	var template := CardData.get_card_by_id(base_id)
	if template.is_empty():
		return {}
	var card := template.duplicate()
	card["id"] = instance_id
	return card


static func ids_to_cards(ids: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id in ids:
		var card := id_to_card(str(id))
		if not card.is_empty():
			cards.append(card)
	return cards


# --- Payload compression ---
# Wire format: [flag: u8][payload...]  where flag is STATE_FLAG_RAW or
# STATE_FLAG_GZIP.

static func wrap_state_payload(raw_bytes: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if raw_bytes.size() >= STATE_COMPRESS_THRESHOLD:
		var compressed := raw_bytes.compress(FileAccess.COMPRESSION_GZIP)
		out.append(STATE_FLAG_GZIP)
		out.append_array(compressed)
	else:
		out.append(STATE_FLAG_RAW)
		out.append_array(raw_bytes)
	return out


## Inverse of wrap_state_payload. Returns empty PackedByteArray on failure.
static func unwrap_state_payload(wire_bytes: PackedByteArray) -> PackedByteArray:
	if wire_bytes.is_empty():
		return PackedByteArray()
	var flag := wire_bytes[0]
	var payload := wire_bytes.slice(1)
	match flag:
		STATE_FLAG_RAW:
			return payload
		STATE_FLAG_GZIP:
			return payload.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		_:
			push_warning("[STATE] Unknown compression flag: %d" % flag)
			return PackedByteArray()


# --- Delta state encoding ---

static func deep_equals(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not deep_equals(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not deep_equals(a[key], b[key]):
				return false
		return true
	return a == b


static func compute_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary:
	var delta := {}
	# Compare top-level fields (excluding "players" which is handled separately)
	for key in new_state:
		if key == "players":
			continue
		if not old_state.has(key) or not deep_equals(old_state[key], new_state[key]):
			delta[key] = new_state[key]
	# Compare per-player state
	var old_players: Array = old_state.get("players", [])
	var new_players: Array = new_state.get("players", [])
	for i in range(new_players.size()):
		var new_pd: Dictionary = new_players[i]
		if i >= old_players.size():
			delta["p%d" % i] = new_pd
			continue
		var player_delta := compute_player_delta(old_players[i], new_pd)
		if not player_delta.is_empty():
			delta["p%d" % i] = player_delta
	return delta


static func compute_player_delta(old_pd: Dictionary, new_pd: Dictionary) -> Dictionary:
	var delta := {}
	for key in new_pd:
		if key == "zones":
			# Compare each zone stack individually for sparse encoding
			var old_zones: Array = old_pd.get("zones", [])
			var new_zones: Array = new_pd.get("zones", [])
			var zones_delta := {}
			for z in range(maxi(old_zones.size(), new_zones.size())):
				var old_z: Array = old_zones[z] if z < old_zones.size() else []
				var new_z: Array = new_zones[z] if z < new_zones.size() else []
				if not deep_equals(old_z, new_z):
					zones_delta[z] = new_z
			if not zones_delta.is_empty():
				delta["zones"] = zones_delta
		else:
			if not old_pd.has(key) or not deep_equals(old_pd[key], new_pd[key]):
				delta[key] = new_pd[key]
	return delta


static func apply_delta(full_state: Dictionary, delta: Dictionary) -> Dictionary:
	var result := full_state.duplicate(true)
	# Apply top-level fields
	for key in delta:
		if key == "p0" or key == "p1":
			continue
		result[key] = delta[key]
	# Apply per-player deltas
	var players: Array = result.get("players", [ {}, {}])
	for i in range(2):
		var pkey := "p%d" % i
		if not delta.has(pkey):
			continue
		var pd: Dictionary = delta[pkey]
		if i >= players.size():
			players.append(pd)
			continue
		var existing: Dictionary = players[i]
		for field in pd:
			if field == "zones" and pd[field] is Dictionary:
				# Sparse zone update: merge individual zone indices
				var zone_delta: Dictionary = pd[field]
				var zones: Array = existing.get("zones", [])
				for z_key in zone_delta:
					var z_idx: int = int(z_key)
					if z_idx < zones.size():
						zones[z_idx] = zone_delta[z_key]
				existing["zones"] = zones
			else:
				existing[field] = pd[field]
	result["players"] = players
	return result


# --- PlayerState serialization ---

static func serialize_player_state(ps: PlayerState) -> Dictionary:
	var zone_ids: Array = []
	for zone_stack in ps.zones:
		zone_ids.append(cards_to_ids(zone_stack))
	var strat_ids: Array = []
	for s in ps.strategy_zones:
		strat_ids.append(card_to_id(s) if s is Dictionary else "")
	# Cards stacked under each strategy (e.g. EBP04-089 RAGE markers). Public info —
	# the count must reach the client so the player who placed it can see their tally.
	var strat_stack_ids: Array = []
	for stack in ps.strategy_zone_stacks:
		strat_stack_ids.append(cards_to_ids(stack) if stack is Array else [])
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": card_to_id(ps.current_monster),
		"zones": zone_ids,
		"strategy_zones": strat_ids,
		"strategy_zone_stacks": strat_stack_ids,
		"hand": cards_to_ids(ps.hand),
		"hand_count": ps.hand.size(),
		"main_deck_count": ps.main_deck.size(),
		"discard_pile": cards_to_ids(ps.discard_pile),
		"discard_pile_count": ps.discard_pile.size(),
		"has_invaded_this_turn": ps.has_invaded_this_turn,
		"has_played_monster_this_turn": ps.has_played_monster_this_turn,
		"monster_stack": cards_to_ids(ps.monster_stack),
		"burst_monster": card_to_id(ps.burst_monster),
		"pre_burst_monster": card_to_id(ps.pre_burst_monster),
		"monster_deck": cards_to_ids(ps.monster_deck),
	}


static func dict_to_player_state(data: Dictionary, is_local: bool) -> PlayerState:
	var ps := PlayerState.new(int(data["player_id"]))
	ps.monster_zone = int(data["monster_zone"])
	ps.rage = int(data["rage"])
	ps.current_monster = id_to_card(str(data.get("current_monster", "")))
	ps.has_invaded_this_turn = data.get("has_invaded_this_turn", false)
	ps.has_played_monster_this_turn = data.get("has_played_monster_this_turn", false)
	for m in data.get("monster_stack", []):
		var card := id_to_card(str(m))
		if not card.is_empty():
			ps.monster_stack.append(card)
	ps.burst_monster = id_to_card(str(data.get("burst_monster", "")))
	ps.pre_burst_monster = id_to_card(str(data.get("pre_burst_monster", "")))

	# Zones: each zone is an array of card IDs
	var zones_data: Array = data.get("zones", [])
	for i in range(mini(zones_data.size(), 8)):
		var zone_stack: Array[Dictionary] = []
		for card_id in zones_data[i]:
			var card := id_to_card(str(card_id))
			if not card.is_empty():
				zone_stack.append(card)
		ps.zones[i] = zone_stack

	# Strategy zones (may be 2 or 3): each is a card ID string
	var sz_data: Array = data.get("strategy_zones", [])
	if sz_data.size() > ps.strategy_zones.size():
		ps.strategy_zones.resize(sz_data.size())
		ps.strategy_zone_turn_placed.resize(sz_data.size())
	for i in range(sz_data.size()):
		ps.strategy_zones[i] = id_to_card(str(sz_data[i]))

	# Cards stacked under each strategy (EBP04-089 RAGE markers) — needed so the
	# client can show the under-count when inspecting the strategy zone.
	var szs_data: Array = data.get("strategy_zone_stacks", [])
	if szs_data.size() > ps.strategy_zone_stacks.size():
		ps.strategy_zone_stacks.resize(szs_data.size())
	for i in range(ps.strategy_zone_stacks.size()):
		var under: Array = []
		if i < szs_data.size():
			for card_id in szs_data[i]:
				var c := id_to_card(str(card_id))
				if not c.is_empty():
					under.append(c)
		ps.strategy_zone_stacks[i] = under

	# Hand: IDs for local player, face-down placeholders for opponent
	if is_local and data.has("hand"):
		ps.hand.assign(ids_to_cards(data["hand"]))
	else:
		var count: int = int(data.get("hand_count", 0))
		ps.hand.clear()
		for j in range(count):
			ps.hand.append({"face_down": true, "id": "opponent_%d" % j})

	# Monster deck: IDs for local player, placeholder count for opponent
	if is_local and data.has("monster_deck"):
		ps.monster_deck.assign(ids_to_cards(data["monster_deck"]))
	else:
		var md_count: int = int(data.get("monster_deck_count", 0))
		ps.monster_deck.resize(md_count)
		for j in range(md_count):
			ps.monster_deck[j] = {}

	# Deck: only counts needed for display labels
	var deck_count: int = int(data.get("main_deck_count", 0))
	ps.main_deck.resize(deck_count)
	for j in range(deck_count):
		ps.main_deck[j] = {}

	# Discard pile: card IDs
	if data.has("discard_pile"):
		ps.discard_pile.assign(ids_to_cards(data["discard_pile"]))
	else:
		var discard_count: int = int(data.get("discard_pile_count", 0))
		ps.discard_pile.resize(discard_count)
		for j in range(discard_count):
			ps.discard_pile[j] = {}

	return ps


# --- State hashing for desync detection ---

## Hash shared (visible to both players) game state for desync detection.
static func compute_state_hash(gs: GameState) -> int:
	return _hash_players(gs.players, gs.turn_number, gs.current_player_id, int(gs.current_phase))


## Client-side hash using reconstructed client PlayerState objects.
static func compute_client_state_hash(players: Array, turn_number: int, current_player_id: int, phase: int) -> int:
	return _hash_players(players, turn_number, current_player_id, phase)


static func _hash_players(players: Array, turn_number: int, current_player_id: int, phase: int) -> int:
	var parts: PackedStringArray = []
	parts.append("t%d" % turn_number)
	parts.append("p%d" % current_player_id)
	parts.append("ph%d" % phase)
	for i in range(2):
		var ps: PlayerState = players[i]
		parts.append("m%d:%d" % [i, ps.monster_zone])
		parts.append("r%d:%d" % [i, ps.rage])
		parts.append("d%d:%d" % [i, ps.main_deck.size()])
		parts.append("h%d:%d" % [i, ps.hand.size()])
		parts.append("dp%d:%d" % [i, ps.discard_pile.size()])
		# Hash zone top card IDs
		for z in range(8):
			var top := ps.get_zone_top_card(z)
			if not top.is_empty():
				parts.append("z%d_%d:%s" % [i, z, top.get("id", "")])
		# Hash strategy zones
		for s in range(ps.strategy_zones.size()):
			if not ps.strategy_zones[s].is_empty():
				parts.append("s%d_%d:%s" % [i, s, ps.strategy_zones[s].get("id", "")])
	return "".join(parts).hash()
