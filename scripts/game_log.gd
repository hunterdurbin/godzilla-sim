class_name GameLog

## Centralized log message formatting for the game log panel.
## All methods are static and return formatted BBCode strings.

static var player_names: Array[String] = ["Player 1", "Player 2"]


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
	## Build a BBCode URL link for a card ID. Displays the card name if found.
	var card_number := _strip_card_id(raw_id)
	if card_number.is_empty():
		return ""
	var card_data: Node = Engine.get_main_loop().root.get_node_or_null("CardData")
	var label := card_number
	if card_data:
		var template: Dictionary = card_data.get_card_by_id(card_number)
		if not template.is_empty():
			label = template.get("name", card_number)
	if label.length() > 18:
		label = label.left(15) + "..."
	return "[url=%s]❰%s❱[/url]" % [card_number, label]


# --- Turn structure ---

static func turn_start(turn_number: int, player_id: int) -> String:
	return "--- Turn %d: %s ---" % [turn_number, player_name(player_id)]


static func start_phase_draw(count: int) -> String:
	return "Start Phase: Drawing %d card(s)" % count


static func hand_size(count: int) -> String:
	return "Hand size: %d" % count


static func main_phase() -> String:
	return "Main Phase: Choose your actions"


static func player_pass(player_id: int) -> String:
	return "%s passes." % _bold(player_name(player_id))


# --- Player actions ---

static func played_battle(player_name: String, card_id: String, zone: int, has_enter: bool = false) -> String:
	var name := _bold(player_name)
	if has_enter:
		var enter_icon := "[img=20]res://CardContent/Assets/effectIcons/others/Enter.png[/img]"
		return "%s: %s %s to Zone %d" % [name, enter_icon, card_link(card_id), zone + 1]
	return "%s: Played %s to Zone %d" % [name, card_link(card_id), zone + 1]


static func played_strategy(player_name: String, card_id: String, is_base: bool = false) -> String:
	var name := _bold(player_name)
	if is_base:
		var base_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Base.png[/img]"
		return "%s: %s Played %s to Strategy Zone" % [name, base_icon, card_link(card_id)]
	return "%s: Played %s to Strategy Zone" % [name, card_link(card_id)]


static func gained_rage(player_name: String, rage: int, card_id: String) -> String:
	var rage_icon := "[img=30]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s: %s x%d (discarded: %s)" % [_bold(player_name), rage_icon, rage, card_link(card_id)]


static func played_monster(player_name: String, card_id: String, rage: int) -> String:
	var rage_icon := "[img=30]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s: Played %s as Monster (%s x%d)" % [_bold(player_name), card_link(card_id), rage_icon, rage]


static func invaded(player_name: String, zone: int, card_id: String, is_step2: bool = false) -> String:
	var name := _bold(player_name)
	if is_step2:
		var step2_icon := "[img=20]res://CardContent/Assets/effectIcons/others/Step2.png[/img]"
		return "%s: %s Monster now at zone %d (discarded %s)" % [name, step2_icon, zone, card_link(card_id)]
	return "%s: Invaded! Monster now at zone %d (discarded %s)" % [name, zone, card_link(card_id)]


# --- Counter & end phase ---

static func counter_phase(player_name: String, cp: int, threat: int) -> String:
	return "%s: Counter Phase: CP %d vs Threat %d" % [_bold(player_name), cp, threat]


static func end_phase(player_name: String, zone: int) -> String:
	return "%s: End Phase: Monster at zone %d" % [_bold(player_name), zone]


static func hand_refilled(player_name: String, count: int) -> String:
	return "%s: Hand refilled to %d cards" % [_bold(player_name), count]


static func game_over(winner_id: int, reason: String) -> String:
	return "GAME OVER! %s wins: %s" % [player_name(winner_id), reason]


# --- Effects ---

static func burst_played(player_name: String, card_id: String, burst_rank: int, rage: int) -> String:
	var burst_icon_path := "res://CardContent/Assets/effectIcons/bursts/Burst%d.png" % burst_rank
	var burst_prefix: String
	if ResourceLoader.exists(burst_icon_path):
		burst_prefix = "[img=40]%s[/img]" % burst_icon_path
	else:
		burst_prefix = "Burst %d:" % burst_rank
	var rage_icon := "[img=30]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s: %s %s %s x%d" % [_bold(player_name), burst_prefix, card_link(card_id), rage_icon, rage]


static func revenge_triggered(player_id: int, card_id: String) -> String:
	var revenge_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Revenge.png[/img]"
	return "%s: %s %s" % [_bold(short_name(player_id)), revenge_icon, card_link(card_id)]


static func awakening_triggered(player_id: int, card_id: String, awakening_level: int) -> String:
	var awk_icon_path := "res://CardContent/Assets/effectIcons/awakenings/Awakening%d.png" % awakening_level
	var awk_prefix: String
	if ResourceLoader.exists(awk_icon_path):
		awk_prefix = "[img=40]%s[/img]" % awk_icon_path
	else:
		awk_prefix = "Awakening %d:" % awakening_level
	return "%s: %s %s" % [_bold(player_name(player_id)), awk_prefix, card_link(card_id)]


static func evolution(player_id: int, zone_idx: int, evo_rank: int, from_id: String, to_id: String) -> String:
	var evo_icon_path := "res://CardContent/Assets/effectIcons/evolutions/Evolution%d.png" % evo_rank
	var evo_prefix: String
	if ResourceLoader.exists(evo_icon_path):
		evo_prefix = "[img=40]%s[/img]" % evo_icon_path
	else:
		evo_prefix = "Evolution %d:" % evo_rank
	return "%s Zone %d: %s %s => %s" % [_bold(player_name(player_id)), zone_idx + 1, evo_prefix, card_link(from_id), card_link(to_id)]


# --- Specific card effects ---

static func effect_milled_card(player_id: int, effect_source_id: String, milled_id: String) -> String:
	return "%s %s: Sent %s to discard pile" % [_bold(short_name(player_id)), card_link(effect_source_id), card_link(milled_id)]


static func effect_milled_cards(player_id: int, effect_source_id: String, milled: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for card in milled:
		names.append(card_link(card.get("id", "")))
	return "%s %s: Sent %s to discard pile" % [_bold(short_name(player_id)), card_link(effect_source_id), ", ".join(names)]


static func effect_gained_rage_from_mill(player_id: int, effect_source_id: String, rage: int, milled_id: String) -> String:
	var rage_icon := "[img=30]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s %s: %s x%d (milled monster: %s)" % [_bold(short_name(player_id)), card_link(effect_source_id), rage_icon, rage, card_link(milled_id)]


# --- Board events ---

static func effect_destroyed_card(source_player_id: int, effect_source_id: String, target_player_id: int, zone_index: int, destroyed_id: String) -> String:
	var destroy_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Destroy.png[/img]"
	return "%s %s %s: %s Zone %d %s" % [destroy_icon, _bold(short_name(source_player_id)), card_link(effect_source_id), _bold(short_name(target_player_id)), zone_index + 1, card_link(destroyed_id)]


static func battle_card_crushed(card_id: String, player_id: int, zone_index: int) -> String:
	var destroy_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Destroy.png[/img]"
	return "%s %s Zone %d: %s crushed!" % [destroy_icon, _bold(short_name(player_id)), zone_index + 1, card_link(card_id)]


static func counter_succeeded(player_id: int, total_cp: int, threat: int) -> String:
	return "Counter SUCCESS! %s CP %d >= Threat %d" % [_bold(short_name(player_id)), total_cp, threat]


static func counter_failed(player_id: int, total_cp: int, threat: int) -> String:
	return "Counter failed. %s CP %d < Threat %d" % [_bold(short_name(player_id)), total_cp, threat]


# --- Utilities ---

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
	return text
