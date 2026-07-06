class_name FolderPickerDialog
extends ConfirmationDialog
## Modal dialog that lets the user pick (or create) a folder for a deck.

signal folder_chosen(target_folder: String)

const ROOT_LABEL := "STR_DLV_ROOT"
const NEW_LABEL := "STR_DLV_NEW_FOLDER"

var _deck_name: String = ""
var _current_folder: String = ""
var _info_label: Label
var _list: VBoxContainer
var _new_folder_edit: LineEdit
var _new_folder_row: HBoxContainer
var _selected_folder: String = ""
var _creating_new: bool = false


func _init() -> void:
	min_size = Vector2i(360, 240)
	max_size = Vector2i(480, 480)
	exclusive = true


func _ready() -> void:
	title = tr("STR_DLV_MOVE_TITLE")
	ok_button_text = tr("STR_COMMON_OK")
	size = Vector2i(360, 280)
	GamepadHelper.register_modal(self)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_info_label = Label.new()
	_info_label.text = tr("STR_DLV_MOVE_INFO") % _deck_name
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 120
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_new_folder_row = HBoxContainer.new()
	_new_folder_row.add_theme_constant_override("separation", 4)
	_new_folder_row.visible = false
	vbox.add_child(_new_folder_row)

	var new_label := Label.new()
	new_label.text = tr("STR_DLV_NEW_FOLDER_PROMPT")
	_new_folder_row.add_child(new_label)

	_new_folder_edit = LineEdit.new()
	_new_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_folder_row.add_child(_new_folder_edit)

	_populate()
	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)


func show_for(deck_name: String, current_folder: String) -> void:
	_deck_name = deck_name
	_current_folder = current_folder
	_selected_folder = current_folder
	_creating_new = false
	if _info_label != null:
		_info_label.text = tr("STR_DLV_MOVE_INFO") % deck_name
	if _list != null:
		_populate()
	if _new_folder_row != null:
		_new_folder_row.visible = false
	popup_centered(Vector2i(360, 280))


func _populate() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var choices: Array[Dictionary] = []
	choices.append({"id": "", "label": tr(ROOT_LABEL)})
	for folder in DecklistManager.get_all_folders():
		choices.append({"id": folder, "label": folder})
	choices.append({"id": "__new__", "label": tr(NEW_LABEL)})

	var group := ButtonGroup.new()
	for c in choices:
		var btn := CheckBox.new()
		btn.button_group = group
		btn.text = c["label"]
		btn.set_meta("folder_id", c["id"])
		if c["id"] == _current_folder and not _creating_new:
			btn.button_pressed = true
		btn.pressed.connect(_on_choice_pressed.bind(c["id"]))
		_list.add_child(btn)


func _on_choice_pressed(folder_id: String) -> void:
	if folder_id == "__new__":
		_creating_new = true
		_new_folder_row.visible = true
		_new_folder_edit.grab_focus()
		_selected_folder = ""
	else:
		_creating_new = false
		_new_folder_row.visible = false
		_selected_folder = folder_id


func _on_confirmed() -> void:
	var target := _selected_folder
	if _creating_new:
		target = _new_folder_edit.text.strip_edges()
		if target.is_empty():
			# Empty new-folder name — treat as cancellation; queue_free via close_requested.
			return
	folder_chosen.emit(target)
	queue_free()
