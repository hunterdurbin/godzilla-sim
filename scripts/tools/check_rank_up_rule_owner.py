#!/usr/bin/env python3
"""Only RulesEngine decides which monsters a player may rank up to.

Rank-up eligibility (5.15.1.2: next rank + a shared trait, or an alternate
cost such as EBP04-033/034's can_play_as_monster bridge) is
RulesEngine.get_rank_up_candidates; can_opponent_rank_up is its predicate.
CounterResolver applies it. A hand-written copy elsewhere drifts from it:
the bot's copies ignored the bridge and misjudged counter wins
(hunterdurbin/godzilla-sim-issue-tracker#22). Ask RulesEngine instead.

Flags "next rank" arithmetic: `+ 1` on an identifier ending in `rank` or
on a `get("rank"…)` / `["rank"]` read (e.g. `cur_rank + 1`,
`current_monster.get("rank", 1) + 1`). A single-line pattern grep, so
other spellings (`1 + rank`, a nested call inside get) slip through under scripts/ and
scenes/ outside rules_engine.gd. EXEMPT lists sites that compute the next
rank for another reason, each with that reason. Copies still waiting on a
fix are grandfathered in rank_up_rule_allowlist.txt (a ratchet: it only
shrinks). Tests (tests/) are not scanned.

Usage: python3 scripts/tools/check_rank_up_rule_owner.py [--update]
"""
import os
import re
import sys

from gd_ratchet import ROOT, Hits, read_lines, run

SCAN_DIRS = ("scripts", "scenes")
OWNER = "scripts/core/rules_engine.gd"
ALLOWLIST = os.path.join(ROOT, "scripts", "tools", "rank_up_rule_allowlist.txt")
# `<file>: <code>` -> why this site computes a next rank without being a
# rank-up eligibility check.
EXEMPT = {
    "scripts/core/actions/counter_resolver.gd: var next_rank: int = opponent.current_monster.get(\"rank\", 1) + 1":
        "prompt text only; the candidates come from get_rank_up_candidates",
    "scripts/effects/ebp03/ebp03_074.gd: var next_rank: int = cur_rank + 1":
        "the card's own text (shares a trait, rank 1 higher), not a rank-up",
}
NEXT_RANK_RE = re.compile(
    r"(\b\w*rank\b|get\(\s*\"rank\"[^)]*\)|\[\s*\"rank\"\s*\])\s*\+\s*1\b")


def gd_files():
    for d in SCAN_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def next_rank_sites(path, lines):
    """(key, line number) for each next-rank computation outside the owner,
    EXEMPT sites included."""
    if path == OWNER:
        return
    for i, line in enumerate(lines, 1):
        if NEXT_RANK_RE.search(line):
            yield "%s: %s" % (path, line.strip()), i


def self_test():
    cases = {
        ("scripts/bot/x.gd", "\tvar next_rank: int = p.current_monster.get(\"rank\", 1) + 1"): True,
        ("scripts/bot/x.gd", "\tif m_rank != cur_rank + 1:"): True,
        ("scripts/bot/x.gd", "\tvar r := monster.get(\"rank\") + 1"): True,
        (OWNER, "\tvar next_rank: int = player.current_monster.get(\"rank\", 1) + 1"): False,
        ("scripts/bot/x.gd", "\tvar r: int = m[\"rank\"] + 1"): True,
        ("scripts/bot/x.gd", "\tvar n := rank_ups + 10"): False,
        ("scripts/bot/x.gd", "\tvar n := rank_ups + 1"): False,
        ("scripts/bot/x.gd", "\tvar n := rank1_strat_count + 1"): False,
        ("scripts/bot/x.gd", "\trank_count += 1"): False,
        ("scripts/bot/x.gd", "\tvar n := count + 1"): False,
        ("scripts/bot/x.gd", "\tif m.get(\"rank\") == next_rank:"): False,
        ("scripts/core/actions/counter_resolver.gd",
         "\tvar next_rank: int = opponent.current_monster.get(\"rank\", 1) + 1"): False,
    }
    bad = [src for (path, src), expect in cases.items()
           if any(k not in EXEMPT for k, _ in next_rank_sites(path, [src])) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main(argv):
    if not self_test():
        return 1
    hits = Hits()
    seen = set()
    for path in gd_files():
        for key, line in next_rank_sites(path, read_lines(path)):
            if key in EXEMPT:
                seen.add(key)
            else:
                hits.add(key, "%s:%d" % (path, line))
    stale = sorted(set(EXEMPT) - seen)
    for k in stale:
        print("EXEMPT entry no longer matches: " + k)
    status = run(argv, hits, ALLOWLIST,
                 "Hand-written rank-up eligibility checks still waiting to call RulesEngine.",
                 "check_rank_up_rule_owner.py", "NEW rank-up rule copy",
                 "Ask RulesEngine: get_rank_up_candidates(player) for the candidates,"
                 " can_opponent_rank_up(player) for the yes/no."
                 " A site that needs the next rank for another reason goes in EXEMPT"
                 " (scripts/tools/check_rank_up_rule_owner.py) with its reason.")
    return 1 if stale else status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
