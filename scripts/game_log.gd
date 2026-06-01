class_name GameLog

## Centralized log message constructors and renderer.
##
## Event methods return structured token Dictionaries. Each client renders
## them via `render()` at display time using its own locale, so hosts and
## clients in different locales see the log in their own language.
## `chat_message()` and the `_bold`/`card_link` helpers produce BBCode
## directly (used inside `render()` and by chat).

static var player_names: Array[String] = ["Player 1", "Player 2"]


static func _icon_locale_dir() -> String:
	## Returns the effect-icon subfolder matching the current locale.
	## Filenames mirror between en/ and ja/ so swapping the directory is enough.
	return "ja" if TranslationServer.get_locale().begins_with("ja") else "en"


static func _icon(size: int, category: String, filename: String) -> String:
	return "[img=%d]res://assets/effectIcons/%s/%s/%s[/img]" % [size, _icon_locale_dir(), category, filename]


static func disambiguate(names: Array[String], local_id: int) -> Array[String]:
	if names.size() == 2 and names[0] == names[1]:
		var result: Array[String] = names.duplicate()
		var opponent_id := 1 - local_id
		result[opponent_id] = "%s (2)" % result[opponent_id]
		return result
	return names


static func player_name(player_id: int) -> String:
	if player_id >= 0 and player_id < player_names.size():
		return player_names[player_id]
	return "Player %d" % (player_id + 1)


static func short_name(player_id: int) -> String:
	var full := player_name(player_id)
	if full.length() > 6:
		return full.left(6)
	return full


static func _bold(text: String) -> String:
	return "[b]%s[/b]" % text


static func _strip_card_id(raw_id: String) -> String:
	## Strip deck/copy suffix: "EBP01-001_0_1" -> "EBP01-001"
	var underscore_pos := raw_id.find("_")
	return raw_id.substr(0, underscore_pos) if underscore_pos != -1 else raw_id


static func card_link(raw_id: String) -> String:
	## Build a BBCode URL link for a card ID. The displayed label is translated
	## to the current locale via `CARD_<id>_NAME` with a fallback to the
	## English name from `CardData.CARD_TEMPLATES` and finally to the raw ID.
	var card_number := _strip_card_id(raw_id)
	if card_number.is_empty():
		return ""
	var label := card_number
	var card_data: Node = Engine.get_main_loop().root.get_node_or_null("CardData")
	var raw_name := ""
	if card_data:
		var template: Dictionary = card_data.get_card_by_id(card_number)
		if not template.is_empty():
			raw_name = template.get("name", "")
	var key := "CARD_%s_NAME" % card_number
	var translated: String = TranslationServer.translate(key)
	if translated != key:
		label = translated
	elif not raw_name.is_empty():
		label = raw_name
	if label.length() > 18:
		label = label.left(15) + "..."
	return "[url=%s]❰%s❱[/url]" % [card_number, label]


# --- Token constructors ---------------------------------------------------

static func turn_start(turn_number: int, player_id: int) -> Dictionary:
	return {"type": "turn_start", "turn": turn_number, "player_id": player_id}


static func start_phase_draw(count: int) -> Dictionary:
	return {"type": "start_phase_draw", "count": count}


static func player_pass(player_id: int) -> Dictionary:
	return {"type": "player_pass", "player_id": player_id}


static func played_battle(player_id: int, card_id: String, zone: int, has_enter: bool = false) -> Dictionary:
	return {"type": "played_battle", "player_id": player_id, "card_id": card_id, "zone": zone, "has_enter": has_enter}


static func played_strategy(player_id: int, card_id: String, is_base: bool = false) -> Dictionary:
	return {"type": "played_strategy", "player_id": player_id, "card_id": card_id, "is_base": is_base}


static func gained_rage(player_id: int, rage: int, card_id: String) -> Dictionary:
	return {"type": "gained_rage", "player_id": player_id, "rage": rage, "card_id": card_id}


static func rage_gained(player_id: int, amount: int, total: int, source_card_id: String = "") -> Dictionary:
	## Generic rage gain log emitted by EffectHandler.gain_rage. When source_card_id
	## is non-empty the log shows the source attribution; otherwise it falls back
	## to the player-only format.
	return {"type": "rage_gained", "player_id": player_id, "amount": amount, "total": total, "source_id": source_card_id}


static func played_monster(player_id: int, card_id: String, rage: int) -> Dictionary:
	return {"type": "played_monster", "player_id": player_id, "card_id": card_id, "rage": rage}


static func invaded(player_id: int, card_id: String, is_step2: bool = false) -> Dictionary:
	return {"type": "invaded", "player_id": player_id, "card_id": card_id, "is_step2": is_step2}


static func game_over(winner_id: int, reason_key: String) -> Dictionary:
	return {"type": "game_over", "winner_id": winner_id, "reason_key": reason_key}


static func burst_played(player_id: int, card_id: String, burst_rank: int, rage: int) -> Dictionary:
	return {"type": "burst_played", "player_id": player_id, "card_id": card_id, "burst_rank": burst_rank, "rage": rage}


static func revenge_triggered(player_id: int, card_id: String) -> Dictionary:
	return {"type": "revenge_triggered", "player_id": player_id, "card_id": card_id}


static func awakening_triggered(player_id: int, card_id: String, awakening_level: int) -> Dictionary:
	return {"type": "awakening_triggered", "player_id": player_id, "card_id": card_id, "awakening_level": awakening_level}


static func evolution(player_id: int, zone_idx: int, evo_rank: int, from_id: String, to_id: String) -> Dictionary:
	return {"type": "evolution", "player_id": player_id, "zone_idx": zone_idx, "evo_rank": evo_rank, "from_id": from_id, "to_id": to_id}


static func effect_milled_card(player_id: int, effect_source_id: String, milled_id: String) -> Dictionary:
	return {"type": "effect_milled_card", "player_id": player_id, "source_id": effect_source_id, "milled_id": milled_id}


static func effect_milled_cards(player_id: int, effect_source_id: String, milled: Array[Dictionary]) -> Dictionary:
	var milled_ids: Array[String] = []
	for card in milled:
		milled_ids.append(card.get("id", ""))
	return {"type": "effect_milled_cards", "player_id": player_id, "source_id": effect_source_id, "milled_ids": milled_ids}


static func effect_gained_rage_from_mill(player_id: int, effect_source_id: String, rage: int, milled_id: String) -> Dictionary:
	return {"type": "effect_gained_rage_from_mill", "player_id": player_id, "source_id": effect_source_id, "rage": rage, "milled_id": milled_id}


static func effect_gained_rage(player_id: int, effect_source_id: String, rage: int, amount: int) -> Dictionary:
	return {"type": "effect_gained_rage", "player_id": player_id, "source_id": effect_source_id, "rage": rage, "amount": amount}


static func effect_destroyed_card(source_player_id: int, effect_source_id: String, target_player_id: int, zone_index: int, destroyed_id: String) -> Dictionary:
	return {"type": "effect_destroyed_card", "source_player_id": source_player_id, "source_id": effect_source_id, "target_player_id": target_player_id, "zone_index": zone_index, "destroyed_id": destroyed_id}


static func effect_returned_card_to_hand(player_id: int, effect_source_id: String, returned_id: String) -> Dictionary:
	return {"type": "effect_returned_card_to_hand", "player_id": player_id, "source_id": effect_source_id, "returned_id": returned_id}


static func battle_card_crushed(card_id: String, player_id: int, zone_index: int) -> Dictionary:
	return {"type": "battle_card_crushed", "card_id": card_id, "player_id": player_id, "zone_index": zone_index}


static func counter_succeeded(player_id: int, total_cp: int, threat: int, rage_threat: int = 0, effect_threat: int = 0) -> Dictionary:
	return {"type": "counter_succeeded", "player_id": player_id, "total_cp": total_cp, "threat": threat, "threat_rage": rage_threat, "threat_effects": effect_threat}


static func counter_failed(player_id: int, total_cp: int, threat: int, rage_threat: int = 0, effect_threat: int = 0) -> Dictionary:
	return {"type": "counter_failed", "player_id": player_id, "total_cp": total_cp, "threat": threat, "threat_rage": rage_threat, "threat_effects": effect_threat}


static func counter_immunity(player_id: int, total_cp: int, threshold: int) -> Dictionary:
	return {"type": "counter_immunity", "player_id": player_id, "total_cp": total_cp, "threshold": threshold}


static func counter_prevented(player_id: int) -> Dictionary:
	return {"type": "counter_prevented", "player_id": player_id}


static func _threat_breakdown_suffix(token: Dictionary) -> String:
	## Append a "(base X + rage Y + effects Z)" breakdown to counter logs, but only
	## when rage or effects contribute — so the common case (printed threat only)
	## stays uncluttered. int() coercion guards against JSON float round-trip on MP
	## clients. base is derived so it always reconciles with the displayed threat.
	var rage: int = int(token.get("threat_rage", 0))
	var effects: int = int(token.get("threat_effects", 0))
	if rage == 0 and effects == 0:
		return ""
	var base: int = int(token.get("threat", 0)) - rage - effects
	return TranslationServer.translate("STR_LOG_THREAT_BREAKDOWN_FMT") \
		.replace("{BASE}", str(base)) \
		.replace("{RAGE}", str(rage)) \
		.replace("{EFFECTS}", str(effects))


static func coin_flip_won(player_id: int) -> Dictionary:
	return {"type": "coin_flip_won", "player_id": player_id}


static func first_player_chose(player_id: int, went_first: bool) -> Dictionary:
	return {"type": "first_player_chose", "player_id": player_id, "went_first": went_first}


static func seed_announce(seed_value: int) -> Dictionary:
	return {"type": "seed", "seed": seed_value}


static func opponent_wants_rematch(new_deck: bool = false) -> Dictionary:
	return {"type": "opponent_wants_rematch", "new_deck": new_deck}


static func opponent_disconnected_waiting() -> Dictionary:
	return {"type": "opponent_disconnected_waiting"}


static func connection_lost_reconnecting() -> Dictionary:
	return {"type": "connection_lost_reconnecting"}


static func reconnected() -> Dictionary:
	return {"type": "reconnected"}


static func opponent_reconnected() -> Dictionary:
	return {"type": "opponent_reconnected"}


static func claimed_win_disconnect() -> Dictionary:
	return {"type": "claimed_win_disconnect"}


static func concede_reason_key(loser_id: int) -> String:
	## Build a reason key with player-id parameter for concede game-over.
	## Rendered by `render_reason` via the `|player=N` suffix.
	return "STR_LOG_REASON_CONCEDED_FMT|player=%d" % loser_id


static func render_reason(reason_key: String) -> String:
	## Translate a game-over reason key, supporting pipe-separated params
	## (e.g. "STR_LOG_REASON_CONCEDED_FMT|player=0"). `player=N` is substituted
	## as `{PLAYER}` using the local player_names table.
	if reason_key.is_empty():
		return ""
	var parts := reason_key.split("|")
	var key: String = parts[0]
	var text := TranslationServer.translate(key)
	for i in range(1, parts.size()):
		var kv := parts[i].split("=", true, 1)
		if kv.size() == 2:
			var name: String = kv[0]
			var val: String = kv[1]
			if name == "player":
				text = text.replace("{PLAYER}", player_name(int(val)))
			else:
				text = text.replace("{%s}" % name.to_upper(), val)
	return text


# --- Rendering ------------------------------------------------------------

static func _icon_or_fallback(icon_path: String, fallback_key: String, rank: int) -> String:
	if ResourceLoader.exists(icon_path):
		return "[img=40]%s[/img]" % icon_path
	return TranslationServer.translate(fallback_key).replace("{N}", str(rank))


static func render(token: Dictionary) -> String:
	## Render a log token as BBCode in the current locale.
	var t: String = token.get("type", "")
	match t:
		"turn_start":
			return TranslationServer.translate("STR_LOG_TURN_START_FMT") \
				.replace("{N}", str(token.get("turn", 0))) \
				.replace("{PLAYER}", player_name(token.get("player_id", 0)))
		"start_phase_draw":
			return TranslationServer.translate("STR_LOG_START_PHASE_DRAW_FMT") \
				.replace("{N}", str(token.get("count", 0)))
		"player_pass":
			return TranslationServer.translate("STR_LOG_PLAYER_PASS_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0)))
		"played_battle":
			var key := "STR_LOG_PLAYED_BATTLE_ENTER_FMT" if token.get("has_enter", false) else "STR_LOG_PLAYED_BATTLE_FMT"
			return TranslationServer.translate(key) \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{ENTER_ICON}", _icon(20, "others", "Enter.png")) \
				.replace("{CARD}", card_link(token.get("card_id", ""))) \
				.replace("{ZONE}", str(int(token.get("zone", 0)) + 1))
		"played_strategy":
			var key := "STR_LOG_PLAYED_STRATEGY_BASE_FMT" if token.get("is_base", false) else "STR_LOG_PLAYED_STRATEGY_FMT"
			return TranslationServer.translate(key) \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{BASE_ICON}", _icon(40, "others", "Base.png")) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"gained_rage":
			return TranslationServer.translate("STR_LOG_GAINED_RAGE_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{N}", str(token.get("rage", 0))) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"rage_gained":
			var source_id: String = String(token.get("source_id", ""))
			if source_id != "":
				return TranslationServer.translate("STR_LOG_EFFECT_RAGE_FMT") \
					.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
					.replace("{SOURCE_CARD}", card_link(source_id)) \
					.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
					.replace("{AMOUNT}", str(token.get("amount", 0))) \
					.replace("{N}", str(token.get("total", 0)))
			return TranslationServer.translate("STR_LOG_RAGE_GAINED_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{AMOUNT}", str(token.get("amount", 0))) \
				.replace("{N}", str(token.get("total", 0)))
		"played_monster":
			return TranslationServer.translate("STR_LOG_PLAYED_MONSTER_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{CARD}", card_link(token.get("card_id", ""))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{N}", str(token.get("rage", 0)))
		"invaded":
			var key := "STR_LOG_INVADED_STEP2_FMT" if token.get("is_step2", false) else "STR_LOG_INVADED_FMT"
			return TranslationServer.translate(key) \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{STEP2_ICON}", _icon(20, "others", "Step2.png")) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"game_over":
			var reason_key: String = token.get("reason_key", "")
			var reason: String = String(TranslationServer.translate(reason_key)) if not reason_key.is_empty() else ""
			return TranslationServer.translate("STR_LOG_GAME_OVER_FMT") \
				.replace("{PLAYER}", player_name(token.get("winner_id", 0))) \
				.replace("{REASON}", reason)
		"burst_played":
			var rank: int = int(token.get("burst_rank", 0))
			var prefix := _icon_or_fallback("res://assets/effectIcons/%s/bursts/Burst%d.png" % [_icon_locale_dir(), rank], "STR_LOG_BURST_FALLBACK_PREFIX_FMT", rank)
			return TranslationServer.translate("STR_LOG_BURST_PLAYED_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{BURST_PREFIX}", prefix) \
				.replace("{CARD}", card_link(token.get("card_id", ""))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{N}", str(token.get("rage", 0)))
		"revenge_triggered":
			return TranslationServer.translate("STR_LOG_REVENGE_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{REVENGE_ICON}", _icon(40, "others", "Revenge.png")) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"awakening_triggered":
			var level: int = int(token.get("awakening_level", 0))
			var awk_prefix := _icon_or_fallback("res://assets/effectIcons/%s/awakenings/Awakening%d.png" % [_icon_locale_dir(), level], "STR_LOG_AWAKENING_FALLBACK_PREFIX_FMT", level)
			return TranslationServer.translate("STR_LOG_AWAKENING_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{AWK_PREFIX}", awk_prefix) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"evolution":
			var evo_rank: int = int(token.get("evo_rank", 0))
			var evo_prefix := _icon_or_fallback("res://assets/effectIcons/%s/evolutions/Evolution%d.png" % [_icon_locale_dir(), evo_rank], "STR_LOG_EVOLUTION_FALLBACK_PREFIX_FMT", evo_rank)
			return TranslationServer.translate("STR_LOG_EVOLUTION_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0))) \
				.replace("{ZONE}", str(int(token.get("zone_idx", 0)) + 1)) \
				.replace("{EVO_PREFIX}", evo_prefix) \
				.replace("{FROM_CARD}", card_link(token.get("from_id", ""))) \
				.replace("{TO_CARD}", card_link(token.get("to_id", "")))
		"effect_milled_card":
			return TranslationServer.translate("STR_LOG_MILLED_CARD_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{MILLED_CARD}", card_link(token.get("milled_id", "")))
		"effect_milled_cards":
			var milled_ids: Array = token.get("milled_ids", [])
			var links: Array[String] = []
			for mid in milled_ids:
				links.append(card_link(str(mid)))
			return TranslationServer.translate("STR_LOG_MILLED_CARDS_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{MILLED_CARDS}", ", ".join(links))
		"effect_gained_rage_from_mill":
			return TranslationServer.translate("STR_LOG_EFFECT_RAGE_FROM_MILL_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{N}", str(token.get("rage", 0))) \
				.replace("{MILLED_CARD}", card_link(token.get("milled_id", "")))
		"effect_gained_rage":
			return TranslationServer.translate("STR_LOG_EFFECT_RAGE_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{RAGE_ICON}", _icon(30, "others", "Rage.png")) \
				.replace("{AMOUNT}", str(token.get("amount", 0))) \
				.replace("{N}", str(token.get("rage", 0)))
		"effect_destroyed_card":
			return TranslationServer.translate("STR_LOG_EFFECT_DESTROYED_FMT") \
				.replace("{DESTROY_ICON}", _icon(40, "others", "Destroy.png")) \
				.replace("{SOURCE_PLAYER}", short_name(token.get("source_player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{TARGET_PLAYER}", short_name(token.get("target_player_id", 0))) \
				.replace("{ZONE}", str(int(token.get("zone_index", 0)) + 1)) \
				.replace("{DESTROYED_CARD}", card_link(token.get("destroyed_id", "")))
		"effect_returned_card_to_hand":
			return TranslationServer.translate("STR_LOG_EFFECT_RETURNED_TO_HAND_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{SOURCE_CARD}", card_link(token.get("source_id", ""))) \
				.replace("{RETURNED_CARD}", card_link(token.get("returned_id", "")))
		"battle_card_crushed":
			return TranslationServer.translate("STR_LOG_CARD_CRUSHED_FMT") \
				.replace("{DESTROY_ICON}", _icon(40, "others", "Destroy.png")) \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{ZONE}", str(int(token.get("zone_index", 0)) + 1)) \
				.replace("{CARD}", card_link(token.get("card_id", "")))
		"counter_succeeded":
			return TranslationServer.translate("STR_LOG_COUNTER_SUCCESS_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{CP}", str(token.get("total_cp", 0))) \
				.replace("{THREAT}", str(token.get("threat", 0))) \
				+ _threat_breakdown_suffix(token)
		"counter_failed":
			return TranslationServer.translate("STR_LOG_COUNTER_FAIL_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{CP}", str(token.get("total_cp", 0))) \
				.replace("{THREAT}", str(token.get("threat", 0))) \
				+ _threat_breakdown_suffix(token)
		"counter_immunity":
			return TranslationServer.translate("STR_LOG_COUNTER_IMMUNE_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0))) \
				.replace("{CP}", str(token.get("total_cp", 0))) \
				.replace("{THRESHOLD}", str(token.get("threshold", 0)))
		"counter_prevented":
			return TranslationServer.translate("STR_LOG_COUNTER_PREVENTED_FMT") \
				.replace("{PLAYER}", short_name(token.get("player_id", 0)))
		"chat":
			var sender_id: int = int(token.get("sender_id", -1))
			var pname := player_name(sender_id) if sender_id >= 0 else String(token.get("sender_name", ""))
			return chat_message(pname, String(token.get("text", "")))
		"coin_flip_won":
			return TranslationServer.translate("STR_LOG_COIN_FLIP_WON_FMT") \
				.replace("{PLAYER}", player_name(token.get("player_id", 0)))
		"first_player_chose":
			var key := "STR_LOG_CHOSE_TO_GO_FIRST_FMT" if token.get("went_first", true) else "STR_LOG_CHOSE_TO_GO_SECOND_FMT"
			return TranslationServer.translate(key) \
				.replace("{PLAYER}", player_name(token.get("player_id", 0)))
		"seed":
			return TranslationServer.translate("STR_LOG_SEED_FMT") \
				.replace("{N}", str(token.get("seed", 0)))
		"opponent_wants_rematch":
			var key := "STR_LOG_OPPONENT_WANTS_REMATCH_NEW_DECK" if token.get("new_deck", false) else "STR_LOG_OPPONENT_WANTS_REMATCH"
			return TranslationServer.translate(key)
		"opponent_disconnected_waiting":
			return TranslationServer.translate("STR_LOG_OPPONENT_DISCONNECTED_WAITING")
		"connection_lost_reconnecting":
			return TranslationServer.translate("STR_LOG_CONNECTION_LOST_RECONNECTING")
		"reconnected":
			return TranslationServer.translate("STR_LOG_RECONNECTED")
		"opponent_reconnected":
			return TranslationServer.translate("STR_LOG_OPPONENT_RECONNECTED")
		"claimed_win_disconnect":
			return TranslationServer.translate("STR_LOG_CLAIMED_WIN_DISCONNECT")
		_:
			return ""


static func render_plain(token: Dictionary) -> String:
	return to_plain_text(render(token))


# --- Utilities ------------------------------------------------------------

static func to_plain_text(bbcode: String) -> String:
	## Convert BBCode log text to plain text for bug reports.
	## Replaces [img] tags with text equivalents and strips remaining BBCode.
	var text := bbcode
	var regex := RegEx.new()
	# Replace evolution icon images with text: [img=40]...Evolution7.png[/img] -> Evolution 7:
	regex.compile("\\[img=\\d+\\][^\\[]*Evolution(\\d+)\\.png\\[/img\\]")
	text = regex.sub(text, "Evolution $1:", true)
	# Replace burst icon images with text: [img=40]...Burst3.png[/img] -> Burst 3:
	regex.compile("\\[img=\\d+\\][^\\[]*Burst(\\d+)\\.png\\[/img\\]")
	text = regex.sub(text, "Burst $1:", true)
	# Replace awakening icon images with text: [img=40]...Awakening6.png[/img] -> Awakening 6:
	regex.compile("\\[img=\\d+\\][^\\[]*Awakening(\\d+)\\.png\\[/img\\]")
	text = regex.sub(text, "Awakening $1:", true)
	# Replace named icons with text equivalents
	regex.compile("\\[img=\\d+\\][^\\[]*Enter\\.png\\[/img\\]")
	text = regex.sub(text, "Enter:", true)
	regex.compile("\\[img=\\d+\\][^\\[]*Destroy\\.png\\[/img\\]")
	text = regex.sub(text, "Destroy:", true)
	regex.compile("\\[img=\\d+\\][^\\[]*Revenge\\.png\\[/img\\]")
	text = regex.sub(text, "Revenge:", true)
	regex.compile("\\[img=\\d+\\][^\\[]*Step2\\.png\\[/img\\]")
	text = regex.sub(text, "Step2:", true)
	regex.compile("\\[img=\\d+\\][^\\[]*Base\\.png\\[/img\\]")
	text = regex.sub(text, "Base", true)
	regex.compile("\\[img=\\d+\\][^\\[]*Rage\\.png\\[/img\\]")
	text = regex.sub(text, "Rage", true)
	# Strip any remaining [img] tags
	regex.compile("\\[img[^\\]]*\\][^\\[]*\\[/img\\]")
	text = regex.sub(text, "", true)
	# Strip [url=...]...[/url] keeping inner text
	regex.compile("\\[url=[^\\]]*\\](.*?)\\[/url\\]")
	text = regex.sub(text, "$1", true)
	# Strip [b]...[/b] keeping inner text
	regex.compile("\\[b\\](.*?)\\[/b\\]")
	text = regex.sub(text, "$1", true)
	# Strip [i]...[/i] keeping inner text
	regex.compile("\\[i\\](.*?)\\[/i\\]")
	text = regex.sub(text, "$1", true)
	# Strip [color=...]...[/color] keeping inner text
	regex.compile("\\[color=[^\\]]*\\](.*?)\\[/color\\]")
	text = regex.sub(text, "$1", true)
	return text


# --- Chat -----------------------------------------------------------------

static func chat_message(pname: String, text: String) -> String:
	return "[color=#e6d279]%s: %s[/color]" % [_bold(pname), text]
