# scripts/util/ — small dependency-light helpers

| File | Role |
|---|---|
| `bug_report.gd` | `BugReport.build_body(board)` — builds the markdown diagnostic body (mode, turn/phase, per-player board state, last 50 log lines) for the in-game bug-report button |
| `fuzzy_match.gd` | `FuzzyMatch.score(needle, haystack)` — VSCode-style subsequence fuzzy scorer (word-boundary/consecutive/case bonuses; -1 = no match); used by deck-builder search |
| `card_search.gd` | `CardSearch.parse(raw)` / `matches(card, criteria)` — the deck builder's card-search grammar (comma AND, `!` negate, `cp>2000`-style compares, plain-substring fuzzy) as statics; used by the F4 board editor pool (the deck builder keeps its own printing-aware copy) |

Rule of thumb: something belongs here only if it has no domain home and at
most trivial dependencies.
