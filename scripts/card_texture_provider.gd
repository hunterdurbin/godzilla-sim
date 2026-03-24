class_name CardTextureProvider

## Shared card texture loading for both 2D and 3D card representations.
## Wraps the same artwork paths and caching used by card.gd.
## Call get_card_texture() with card_data dict to get a Texture2D.

const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const CARD_BACK_PATH := "res://assets/cardBacks/default.jpeg"

# Non-rotated texture cache (for 3D cards that handle rotation via mesh orientation)
static var _raw_texture_cache: Dictionary = {}  # card_number -> ImageTexture
static var _raw_custom_cache: Dictionary = {}   # card_number -> ImageTexture
static var _card_back_texture: Texture2D = null


## Get the card front texture for a card data dict (non-rotated, suitable for 3D).
static func get_card_texture(card_data: Dictionary) -> Texture2D:
	var card_number := _resolve_card_number(card_data)
	if card_number.is_empty():
		return null

	# Try custom art first
	if GameSettings.custom_card_art_enabled:
		if _raw_custom_cache.has(card_number):
			return _raw_custom_cache[card_number]
		var custom_dir := _get_custom_art_base().path_join(card_number.split("-")[0])
		var custom_path := _find_custom_file(custom_dir, card_number)
		if not custom_path.is_empty():
			var image := Image.load_from_file(custom_path)
			if image:
				var tex := ImageTexture.create_from_image(image)
				_raw_custom_cache[card_number] = tex
				return tex

	# Standard artwork
	if _raw_texture_cache.has(card_number):
		return _raw_texture_cache[card_number]
	var set_number := card_number.split("-")[0]
	var image_path := ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number)
	var abs_path := ProjectSettings.globalize_path(image_path)
	if FileAccess.file_exists(image_path):
		var image := Image.load_from_file(abs_path)
		if image:
			var tex := ImageTexture.create_from_image(image)
			_raw_texture_cache[card_number] = tex
			return tex
	return null


## Get the card back texture.
static func get_card_back_texture() -> Texture2D:
	if _card_back_texture == null:
		_card_back_texture = load(CARD_BACK_PATH)
	return _card_back_texture


static func _resolve_card_number(card_data: Dictionary) -> String:
	var card_number: String = card_data.get("card_number", "")
	if not card_number.is_empty():
		return card_number
	var id: String = card_data.get("id", "")
	if id.is_empty():
		return ""
	var underscore_pos := id.find("_")
	if underscore_pos != -1:
		id = id.substr(0, underscore_pos)
	return id


static var _custom_art_base: String = ""

static func _get_custom_art_base() -> String:
	if _custom_art_base.is_empty():
		_custom_art_base = GameSettings.get_custom_base_path().path_join("cardArt")
	return _custom_art_base


static func _find_custom_file(dir_path: String, card_number: String) -> String:
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	var prefix := card_number.to_lower() + "."
	da.list_dir_begin()
	var file_name := da.get_next()
	while not file_name.is_empty():
		if not da.current_is_dir() and file_name.to_lower().begins_with(prefix):
			return dir_path.path_join(file_name)
		file_name = da.get_next()
	return ""
