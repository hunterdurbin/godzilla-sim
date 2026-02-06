extends PanelContainer
## Deck selection panel: shows saved decklists and a preview of the selected one.

signal deck_selected(deck_name: String)

@onready var deck_list: ItemList = $MarginContainer/VBoxContainer/Content/DeckList
@onready var deck_preview: RichTextLabel = $MarginContainer/VBoxContainer/Content/DeckPreview
@onready var import_button: Button = $MarginContainer/VBoxContainer/ButtonBar/ImportButton
@onready var delete_button: Button = $MarginContainer/VBoxContainer/ButtonBar/DeleteButton
@onready var import_dialog: ConfirmationDialog = $ImportDialog
@onready var delete_dialog: ConfirmationDialog = $DeleteDialog
@onready var name_edit: LineEdit = $ImportDialog/VBoxContainer/NameEdit

var current_selection: String = ""


func _ready() -> void:
	_setup_style()
	deck_list.item_selected.connect(_on_deck_item_selected)
	import_button.pressed.connect(_on_import_pressed)
	import_dialog.confirmed.connect(_on_import_confirmed)
	delete_button.pressed.connect(_on_delete_pressed)
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	refresh_list()


func refresh_list() -> void:
	deck_list.clear()
	var names := DecklistManager.get_all_decklists()
	for deck_name in names:
		deck_list.add_item(deck_name)
	if deck_list.item_count > 0:
		deck_list.select(0)
		_on_deck_item_selected(0)


func _on_deck_item_selected(index: int) -> void:
	current_selection = deck_list.get_item_text(index)
	deck_preview.clear()
	deck_preview.append_text(DecklistManager.get_decklist_preview(current_selection))
	deck_selected.emit(current_selection)


func _on_delete_pressed() -> void:
	if current_selection.is_empty():
		return
	delete_dialog.dialog_text = "Delete \"%s\"?" % current_selection
	delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	DecklistManager.delete_decklist(current_selection)
	current_selection = ""
	deck_preview.clear()
	refresh_list()
	if deck_list.item_count == 0:
		deck_selected.emit("")


func _on_import_pressed() -> void:
	var clipboard := DisplayServer.clipboard_get()
	if clipboard.strip_edges().is_empty():
		deck_preview.clear()
		deck_preview.append_text("[color=red]Clipboard is empty.[/color]")
		return
	name_edit.text = ""
	import_dialog.popup_centered()
	name_edit.grab_focus()


func _on_import_confirmed() -> void:
	var deck_name := name_edit.text.strip_edges()
	if deck_name.is_empty():
		deck_name = "Imported Deck"

	var clipboard := DisplayServer.clipboard_get()
	var data := DecklistManager._parse_decklist(clipboard)
	if data["monster"].is_empty() and data["main"].is_empty():
		deck_preview.clear()
		deck_preview.append_text("[color=red]Could not parse decklist from clipboard.[/color]")
		return

	DecklistManager.save_decklist(deck_name, data["monster"], data["main"])
	refresh_list()

	# Select the newly imported deck
	for i in range(deck_list.item_count):
		if deck_list.get_item_text(i) == deck_name:
			deck_list.select(i)
			_on_deck_item_selected(i)
			break


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.06, 0.9)
	style.border_color = Color(0.9, 0.3, 0.1, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
