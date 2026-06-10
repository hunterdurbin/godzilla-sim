extends Control

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var skip_button: Button = $CenterContainer/VBoxContainer/SkipButton


func _ready() -> void:
	# Dedicated server entry: the server export (dedicated_server feature tag)
	# or `--headless -- --server` skips the whole client boot path.
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/server/ServerMain.tscn")
		return

	skip_button.pressed.connect(_go_to_main_menu)
	ArtworkDownloader.progress_updated.connect(_on_progress_updated)
	ArtworkDownloader.download_complete.connect(_on_download_complete)
	ArtworkDownloader.download_bytes_updated.connect(_on_download_bytes_updated)
	# First launch: prompt for language before starting downloads. The button
	# handler kicks off the download once a locale is chosen.
	if GameSettings.has_chosen_locale():
		ArtworkDownloader.start_download.call_deferred()
	else:
		_prompt_language()


func _prompt_language() -> void:
	# Control-based modal instead of PopupPanel. PopupPanel is a Window
	# subclass and on Windows users have reported it never rendering visibly
	# — leaving them staring at "Preparing..." with the popup capturing input
	# but invisible. A plain ColorRect overlay sidesteps the subwindow path.
	var overlay := ColorRect.new()
	overlay.name = "LanguagePromptOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	# Bilingual title — locale isn't set yet, so don't tr() this.
	title.text = "Choose Language / 言語を選択"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)

	for entry in [["en", "English"], ["ja", "日本語"]]:
		var btn := Button.new()
		btn.text = entry[1]
		btn.custom_minimum_size = Vector2(220, 50)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 22)
		var locale_id: String = entry[0]
		btn.pressed.connect(func():
			SfxManager.play("ui_click")
			GameSettings.set_locale(locale_id)
			# Align card art locale with UI choice on first launch.
			# start_download() only fetches cards not already cached for this
			# locale, so existing on-disk art (e.g. from a prior install) is
			# reused, not re-downloaded.
			GameSettings.card_art_locale = locale_id
			GameSettings.save()
			overlay.queue_free()
			ArtworkDownloader.start_download.call_deferred())
		vbox.add_child(btn)

	add_child(overlay)


func _on_download_bytes_updated(downloaded_bytes: int, total_bytes: int) -> void:
	var dl_mb := downloaded_bytes / 1048576.0
	if total_bytes > 0:
		progress_bar.max_value = total_bytes
		progress_bar.value = downloaded_bytes
		var total_mb := total_bytes / 1048576.0
		status_label.text = tr("STR_LS_DOWNLOADING_FMT") % [dl_mb, total_mb]
	else:
		progress_bar.max_value = 100
		progress_bar.value = 0
		status_label.text = tr("STR_LS_DOWNLOADING_INDETERMINATE_FMT") % dl_mb


func _on_progress_updated(current: int, total: int, card_number: String) -> void:
	progress_bar.max_value = total
	progress_bar.value = current
	status_label.text = tr("STR_LS_EXTRACTING_FMT") % [card_number, current, total]


func _on_download_complete(downloaded: int, skipped: int, failed: int) -> void:
	if downloaded == 0 and failed == 0:
		status_label.text = tr("STR_LS_UP_TO_DATE")
	else:
		status_label.text = tr("STR_LS_DONE_FMT") % [downloaded, skipped, failed]
	# Brief pause so the user sees the final status
	await get_tree().create_timer(0.5).timeout
	_go_to_main_menu()


func _go_to_main_menu() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")
