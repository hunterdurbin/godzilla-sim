#!/usr/bin/env python3
"""Print where seed-matched sim games split: per game, the last [SimTurn]
line base and head share (the state the split started from) and the first
one that differs, between a base and a head BotSimulationRunner log.

Usage: first_divergence.py <base.log> <head.log>
Exit 0 when every game's turn trace matches, 1 when any game split.
run_sim_diff.sh calls this per deck pair (see tests/sim/README.md).
"""
import re
import sys

TURN = re.compile(r"^\[SimTurn\] game=(\d+) ")


def traces(path):
    games = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = TURN.match(line)
            if m:
                games.setdefault(int(m.group(1)), []).append(line.rstrip("\n"))
    return games


def first_split(base, head):
    """(last shared line, base line, head line) at the first difference."""
    n = 0
    while n < len(base) and n < len(head) and base[n] == head[n]:
        n += 1
    if n == len(base) and n == len(head):
        return None
    return (base[n - 1] if n else "(game start)",
            base[n] if n < len(base) else "(game over)",
            head[n] if n < len(head) else "(game over)")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    base, head = traces(sys.argv[1]), traces(sys.argv[2])
    split = 0
    for game in sorted(set(base) | set(head)):
        found = first_split(base.get(game, []), head.get(game, []))
        if found:
            split += 1
            print("game=%d" % game)
            print("  from %s" % found[0])
            print("  base %s" % found[1])
            print("  head %s" % found[2])
    sys.exit(1 if split else 0)


if __name__ == "__main__":
    main()
