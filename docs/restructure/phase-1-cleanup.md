# Phase 1 — Cleanup (deletions only)

**Goal:** remove dead prototype scenes and stale generated reports. Nothing
moves; nothing behavioral changes.

## Deletions

Orphaned early-prototype scenes at `scenes/` root (verified unreferenced by
any `.gd`/`.tscn`/`.cfg`; main scene is `res://scenes/ui/LoadingScreen.tscn`):

- [ ] `scenes/CardTest.tscn`
- [ ] `scenes/DeckTest.tscn`
- [ ] `scenes/SlotTest.tscn`
- [ ] `scenes/deck_test_controller.gd` + `.uid`
- [ ] `scenes/Main.tscn` (4th orphan, found during planning — only
      instantiates Card/CardManager, nothing references it)
- [ ] `rm -rf reports/` (20 stale gdUnit4 HTML report dirs; git-ignored, so
      plain `rm`, not `git rm`; keep the `.gitignore` entry)

## Pre-delete safety grep (re-verify each before `git rm`)

```bash
grep -rn 'CardTest\|DeckTest\|SlotTest\|deck_test_controller\|scenes/Main.tscn' . \
  --include='*.gd' --include='*.tscn' --include='*.cfg' --include='*.godot' \
  --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git
```

Expected: hits only inside the files being deleted themselves (and
docs/restructure/). Any other hit → STOP, record in STATE.md, investigate.

## Gate (reduced)

- Unit tests pass at baseline count (nothing behavioral was touched).
- Load the main scene headlessly as a boot smoke:
  `Godot --headless --path . --quit-after 5` (exit 0, no SCRIPT ERROR).

## Commit

`restructure(phase-1): delete orphaned prototype scenes + stale reports`
