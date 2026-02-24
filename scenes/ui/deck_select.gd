extends VBoxContainer
## Deck selection dropdown: shows saved decklists in an OptionButton.
## Remembers the last selected deck across scenes.

signal deck_selected(deck_name: String)

@onready var header_label: Label = $Header
@onready var deck_dropdown: OptionButton = $DeckDropdown

var current_selection: String = ""

@export var persist_key: String = "last_selected_deck"


func _ready() -> void:
	deck_dropdown.item_selected.connect(_on_item_selected)
	refresh_list()


func refresh_list() -> void:
	deck_dropdown.clear()
	var names := DecklistManager.get_all_decklists()
	if names.is_empty():
		current_selection = ""
		return

	for deck_name in names:
		deck_dropdown.add_item(deck_name)

	# Default to last selected deck if available
	var last := _load_last_selected()
	var select_idx := 0
	if not last.is_empty():
		for i in range(deck_dropdown.item_count):
			if deck_dropdown.get_item_text(i) == last:
				select_idx = i
				break

	deck_dropdown.select(select_idx)
	_on_item_selected(select_idx)


func _on_item_selected(index: int) -> void:
	current_selection = deck_dropdown.get_item_text(index)
	_save_last_selected(current_selection)
	deck_selected.emit(current_selection)


func set_header(text: String) -> void:
	if header_label:
		header_label.text = text


func _save_last_selected(deck_name: String) -> void:
	var config := ConfigFile.new()
	var path := "user://deck_select.cfg"
	config.load(path)
	config.set_value("deck_select", persist_key, deck_name)
	config.save(path)


func _load_last_selected() -> String:
	var config := ConfigFile.new()
	if config.load("user://deck_select.cfg") != OK:
		return ""
	return config.get_value("deck_select", persist_key, "")
