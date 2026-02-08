extends Node
## Downloads primary card artwork from the Godzilla TCG API.
## Add as an autoload or call start_download() from any scene.

signal download_complete(downloaded: int, skipped: int, failed: int)
signal progress_updated(current: int, total: int, card_number: String)

const API_BASE := "http://api.godzillatcg.com"
const CARDS_JSON_PATH := "res://CardContent/CardInfo/all_cards.json"
const ARTWORK_BASE_PATH := "user://CardContent/Artwork"

var _cards: Array = []
var _current_index: int = 0
var _downloaded: int = 0
var _skipped: int = 0
var _failed: int = 0
var _http_images: HTTPRequest
var _http_media: HTTPRequest
var _current_card: Dictionary = {}
var _is_running: bool = false


func _ready() -> void:
	_http_images = HTTPRequest.new()
	_http_images.request_completed.connect(_on_images_request_completed)
	add_child(_http_images)

	_http_media = HTTPRequest.new()
	_http_media.request_completed.connect(_on_media_request_completed)
	add_child(_http_media)


func start_download() -> void:
	if _is_running:
		return
	_is_running = true
	_cards = _load_cards()
	_current_index = 0
	_downloaded = 0
	_skipped = 0
	_failed = 0
	print("[ArtworkDownloader] Starting download for %d cards..." % _cards.size())
	_process_next_card()


func _load_cards() -> Array:
	var file := FileAccess.open(CARDS_JSON_PATH, FileAccess.READ)
	if not file:
		push_error("[ArtworkDownloader] Could not open %s" % CARDS_JSON_PATH)
		return []
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("[ArtworkDownloader] JSON parse error: %s" % json.get_error_message())
		return []
	return json.data.get("cards", [])


func _get_set_number(card_number: String) -> String:
	return card_number.split("-")[0]


func _get_artwork_path(card_number: String) -> String:
	var set_number := _get_set_number(card_number)
	return ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number)


func _process_next_card() -> void:
	if _current_index >= _cards.size():
		_finish()
		return

	_current_card = _cards[_current_index]
	var card_number: String = _current_card.get("card_number", "")
	var artwork_path := _get_artwork_path(card_number)

	progress_updated.emit(_current_index + 1, _cards.size(), card_number)

	# Check if file already exists
	if FileAccess.file_exists(artwork_path):
		print("[ArtworkDownloader] [%d/%d] %s - already exists, skipping" % [
			_current_index + 1, _cards.size(), card_number
		])
		_skipped += 1
		_current_index += 1
		_process_next_card()
		return

	# Fetch image info from API
	var card_id: int = _current_card.get("id", 0)
	var url := "%s/cards/%d/images" % [API_BASE, card_id]
	print("[ArtworkDownloader] [%d/%d] %s - fetching image info..." % [
		_current_index + 1, _cards.size(), card_number
	])
	var err := _http_images.request(url)
	if err != OK:
		push_error("[ArtworkDownloader] HTTP request error for %s: %d" % [card_number, err])
		_failed += 1
		_current_index += 1
		_process_next_card()


func _on_images_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var card_number: String = _current_card.get("card_number", "")
	var card_id: int = _current_card.get("id", 0)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ArtworkDownloader] Failed to fetch images for %s (result=%d, code=%d)" % [
			card_number, result, response_code
		])
		_failed += 1
		_current_index += 1
		_process_next_card()
		return

	var json := JSON.new()
	var err := json.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("[ArtworkDownloader] JSON parse error for %s images" % card_number)
		_failed += 1
		_current_index += 1
		_process_next_card()
		return

	var images: Array = json.data if json.data is Array else []

	# Find primary image
	var image_id: int = -1
	for img in images:
		if img.get("is_primary", false):
			image_id = img.get("id", -1)
			break

	# Fallback to first image
	if image_id == -1 and images.size() > 0:
		image_id = images[0].get("id", -1)

	if image_id == -1:
		push_error("[ArtworkDownloader] No image found for %s" % card_number)
		_failed += 1
		_current_index += 1
		_process_next_card()
		return

	# Download the image
	var media_url := "%s/media/%d/%d" % [API_BASE, card_id, image_id]
	print("[ArtworkDownloader]   Downloading media/%d/%d..." % [card_id, image_id])
	err = _http_media.request(media_url)
	if err != OK:
		push_error("[ArtworkDownloader] HTTP request error downloading %s: %d" % [card_number, err])
		_failed += 1
		_current_index += 1
		_process_next_card()


func _on_media_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var card_number: String = _current_card.get("card_number", "")

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ArtworkDownloader] Failed to download image for %s (result=%d, code=%d)" % [
			card_number, result, response_code
		])
		_failed += 1
		_current_index += 1
		_process_next_card()
		return

	var artwork_path := _get_artwork_path(card_number)
	var set_number := _get_set_number(card_number)
	var set_dir := ARTWORK_BASE_PATH.path_join(set_number)

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(set_dir)

	# Save the image
	var file := FileAccess.open(artwork_path, FileAccess.WRITE)
	if not file:
		push_error("[ArtworkDownloader] Could not write to %s" % artwork_path)
		_failed += 1
		_current_index += 1
		_process_next_card()
		return

	file.store_buffer(body)
	file.close()
	_downloaded += 1
	print("[ArtworkDownloader]   Saved %s" % artwork_path)

	_current_index += 1
	_process_next_card()


func _finish() -> void:
	_is_running = false
	print("[ArtworkDownloader] Done! Downloaded: %d, Skipped: %d, Failed: %d" % [
		_downloaded, _skipped, _failed
	])
	download_complete.emit(_downloaded, _skipped, _failed)
