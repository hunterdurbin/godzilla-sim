extends DeckListView
## Deck picker used by lobbies / main menu.
##
## Thin DeckListView subclass: compact mode (no Move…), keeps last selection
## via persist_key. Existing call sites (`current_selection`, `set_header`,
## `deck_selected`) continue to work unchanged via the parent class.


func _ready() -> void:
	compact = true
	if header_text.is_empty():
		header_text = "STR_DS_SELECT_DECK"
	if persist_key.is_empty():
		persist_key = "last_selected_deck"
	super._ready()
