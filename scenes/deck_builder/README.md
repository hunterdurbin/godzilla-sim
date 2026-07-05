# scenes/deck_builder/ — deck building & selection

| File | Role |
|---|---|
| `DeckBuilder.tscn` / `deck_builder.gd` | The full deck editor: card pool browsing/filtering (fuzzy search via `FuzzyMatch`), deck stats, validation (`DeckValidator` / `GameModeValidator`), Deck Log import (`DecklogImporter`), save to `DecklistManager` |
| `DeckSelect.tscn` / `deck_select.gd` | Reusable deck picker — embedded by MainMenu and every lobby scene |
| `deck_list_view.gd` | Deck/folder listing widget (uses `folder_picker_dialog.gd` for moves) |
| `deck_row.gd` | One row in the deck list |
| `folder_picker_dialog.gd` | Folder-choice dialog for organizing decks |
| `bot_pool_view.gd` | Bot deck-pool weighting view (feeds `GameSettings.pick_weighted_random_deck()`) |

Flow: `MainMenu → DeckBuilder` (edit) and back; `DeckSelect` is embedded,
not navigated to. Deck files live in `user://decklists/` as `.deck`
(subfolders = folders) — all persistence goes through the `DecklistManager`
autoload (`scripts/cards/README.md`).
