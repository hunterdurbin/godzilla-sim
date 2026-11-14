# Coding standards (review)

Judgement calls a reviewer checks on a diff. Anything a pattern can catch is
a check in `scripts/tools/` instead (see its README) and does not belong here.

## Card scripts and engine primitives

- **Behaviour changes are named in the PR.** A card migration or engine
  change that alters what a player sees or what fires lists it: a prompt
  that appears or disappears, a reveal shown differently, a trigger or
  signal that now fires (or stops firing). "Refactor, no behaviour change"
  is a claim the diff must support.
- **A primitive's docstring is its contract.** It says where the card must
  already be (removed from its source by the caller, or taken out by the
  primitive), which `PlayerState` signals it emits, which triggers it fires,
  and whether it prompts. A new primitive without that is incomplete.
- **A primitive serves the intent, not one card.** Its name and parameters
  read as card text ("place cards under your monster"), and the effects
  README primitives table gains a row for it.
- **Rule-number citations.** Engine code implementing a comprehensive-rules
  clause cites the number (`10.4.3`) so the next reader can look it up.
- **Rulings match.** A diff that changes a card's behaviour — its script, or
  an engine change whose tests or ticket name the card — is checked against
  that card's rulings (`grep -A2 '<card id>' comprehensive_rules/qa.txt`):
  the behaviour agrees with each one, and a test pinning an edge case cites
  its Q number. Where the English wording decides the outcome, the Japanese
  originals rule (`qa-ja.txt`, `rules-ja.txt`; ids drop the `E`).

## Evidence

- **Sim evidence covers the changed cards.** For card-script changes, the
  `run_sim_diff.sh` output shows each changed card resolving on the head
  side, or the PR says why it can't (passive-only modifier, no deck plays
  it and a unit test covers it).
- **Every seed-matched sim difference is explained.** A differing
  `[SimResult]` line needs a cause in the PR: a rule now applied, a trigger
  that now fires, or bot RNG drawn in a different order (adding or removing
  a prompt the bot answers with a shuffle or `randi()` shifts every later
  draw in that game).
- **Tests assert the behaviour the PR claims.** A newly firing trigger or
  emitted signal has an assertion, not just a passing suite.
