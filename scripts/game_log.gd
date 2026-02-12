class_name GameLog

## Centralized log message formatting for the game log panel.
## All methods are static and return formatted BBCode strings.


static func _strip_card_id(raw_id: String) -> String:
	## Strip deck/copy suffix: "EBP01-001_0_1" -> "EBP01-001"
	var underscore_pos := raw_id.find("_")
	return raw_id.substr(0, underscore_pos) if underscore_pos != -1 else raw_id


static func card_link(raw_id: String) -> String:
	## Build a BBCode URL link for a card ID.
	var card_number := _strip_card_id(raw_id)
	if card_number.is_empty():
		return ""
	return "[url=%s][%s][/url]" % [card_number, card_number]


# --- Turn structure ---

static func turn_start(turn_number: int, player_id: int) -> String:
	return "--- Turn %d: Player %d ---" % [turn_number, player_id + 1]


static func start_phase_draw(count: int) -> String:
	return "Start Phase: Drawing %d card(s)" % count


static func hand_size(count: int) -> String:
	return "Hand size: %d" % count


static func main_phase() -> String:
	return "Main Phase: Choose your actions"


static func player_pass(player_id: int) -> String:
	return "Player %d passes." % (player_id + 1)


# --- Player actions ---

static func played_battle(player_name: String, card_id: String, zone: int) -> String:
	return "%s: Played %s to Zone %d" % [player_name, card_link(card_id), zone + 1]


static func played_strategy(player_name: String, card_id: String) -> String:
	return "%s: Played %s to Strategy Zone" % [player_name, card_link(card_id)]


static func gained_rage(player_name: String, rage: int, card_id: String) -> String:
	var rage_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s: %s x%d (discarded: %s)" % [player_name, rage_icon, rage, card_link(card_id)]


static func played_monster(player_name: String, card_id: String, rage: int) -> String:
	return "%s: Played %s as Monster (rage now %d)" % [player_name, card_link(card_id), rage]


static func invaded(player_name: String, zone: int, card_id: String) -> String:
	return "%s: Invaded! Monster now at zone %d (discarded %s)" % [player_name, zone, card_link(card_id)]


# --- Counter & end phase ---

static func counter_phase(cp: int, threat: int) -> String:
	return "Counter Phase: CP %d vs Threat %d" % [cp, threat]


static func end_phase(zone: int) -> String:
	return "End Phase: Monster at zone %d" % zone


static func hand_refilled(count: int) -> String:
	return "Hand refilled to %d cards" % count


static func game_over(winner_id: int, reason: String) -> String:
	return "GAME OVER! Player %d wins: %s" % [winner_id + 1, reason]


# --- Effects ---

static func burst_played(player_name: String, card_id: String, burst_rank: int, rage: int) -> String:
	var burst_icon_path := "res://CardContent/Assets/effectIcons/bursts/Burst%d.png" % burst_rank
	var burst_prefix: String
	if ResourceLoader.exists(burst_icon_path):
		burst_prefix = "[img=40]%s[/img]" % burst_icon_path
	else:
		burst_prefix = "Burst %d:" % burst_rank
	var rage_icon := "[img=40]res://CardContent/Assets/effectIcons/others/Rage.png[/img]"
	return "%s: %s %s %s x%d" % [player_name, burst_prefix, card_link(card_id), rage_icon, rage]


static func evolution(player_id: int, zone_idx: int, evo_rank: int, from_id: String, to_id: String) -> String:
	var evo_icon_path := "res://CardContent/Assets/effectIcons/evolutions/Evolution%d.png" % evo_rank
	var evo_prefix: String
	if ResourceLoader.exists(evo_icon_path):
		evo_prefix = "[img=40]%s[/img]" % evo_icon_path
	else:
		evo_prefix = "Evolution %d:" % evo_rank
	return "Player %d Zone %d: %s %s => %s" % [player_id + 1, zone_idx + 1, evo_prefix, card_link(from_id), card_link(to_id)]


# --- Board events ---

static func battle_card_crushed(card_name: String, player_id: int, zone_index: int) -> String:
	return "Battle card '%s' crushed in P%d Zone %d!" % [card_name, player_id + 1, zone_index + 1]


static func counter_succeeded(player_id: int, total_cp: int, threat: int) -> String:
	return "Counter SUCCESS! P%d CP %d >= Threat %d" % [player_id + 1, total_cp, threat]


static func counter_failed(player_id: int, total_cp: int, threat: int) -> String:
	return "Counter failed. P%d CP %d < Threat %d" % [player_id + 1, total_cp, threat]


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
	# Replace rage icon with text: [img=40]...Rage.png[/img] -> Rage
	regex.compile("\\[img=\\d+\\][^\\[]*Rage\\.png\\[/img\\]")
	text = regex.sub(text, "Rage", true)
	# Strip any remaining [img] tags
	regex.compile("\\[img[^\\]]*\\][^\\[]*\\[/img\\]")
	text = regex.sub(text, "", true)
	# Strip [url=...]...[/url] keeping inner text
	regex.compile("\\[url=[^\\]]*\\](.*?)\\[/url\\]")
	text = regex.sub(text, "$1", true)
	return text
