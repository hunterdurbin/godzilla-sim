extends Control

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var skip_button: Button = $CenterContainer/VBoxContainer/SkipButton


func _ready() -> void:
	skip_button.pressed.connect(_go_to_main_menu)
	ArtworkDownloader.progress_updated.connect(_on_progress_updated)
	ArtworkDownloader.download_complete.connect(_on_download_complete)
	ArtworkDownloader.download_bytes_updated.connect(_on_download_bytes_updated)
	# Deferred so signals are connected before download starts
	ArtworkDownloader.start_download.call_deferred()


func _on_download_bytes_updated(downloaded_bytes: int, total_bytes: int) -> void:
	var dl_mb := downloaded_bytes / 1048576.0
	if total_bytes > 0:
		progress_bar.max_value = total_bytes
		progress_bar.value = downloaded_bytes
		var total_mb := total_bytes / 1048576.0
		status_label.text = "Downloading... %.1f MB / %.1f MB" % [dl_mb, total_mb]
	else:
		progress_bar.max_value = 100
		progress_bar.value = 0
		status_label.text = "Downloading... %.1f MB" % dl_mb


func _on_progress_updated(current: int, total: int, card_number: String) -> void:
	progress_bar.max_value = total
	progress_bar.value = current
	status_label.text = "Extracting %s... (%d/%d)" % [card_number, current, total]


func _on_download_complete(downloaded: int, skipped: int, failed: int) -> void:
	if downloaded == 0 and failed == 0:
		status_label.text = "All artwork up to date!"
	else:
		status_label.text = "Done! Downloaded: %d, Skipped: %d, Failed: %d" % [downloaded, skipped, failed]
	# Brief pause so the user sees the final status
	await get_tree().create_timer(0.5).timeout
	_go_to_main_menu()


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
