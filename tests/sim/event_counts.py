#!/usr/bin/env python3
"""Compare the [SimEvents] rule-event counts of a base and a head sim log,
plus the [SimEffects] ability counts.

Usage: event_counts.py <base.log> <head.log> <table_out>

Writes every event to <table_out> as `name  base -> head` (sorted; "-" for
a name that side's tree does not have), then prints to stdout:
  `name base -> head`          a count that moved (both trees have the name)
  `(added) name head`          only head's tree has it (a new signal / token)
  `(removed) name base`        only base's tree has it
Exit status: 0 = no count moved (added / removed names are informational);
1 = some count moved; 2 = no comparison: a log without a [SimEvents] line
(a run that died early, or a harness that predates it) or one that does not
parse.

An event is a GameEvents signal emission (`monster_countered`) or a log
token type (`log:burst_played`); each tree seeds every name it can emit at
0 (tests/sim/bot_simulation_runner.gd `_event_counts`). Use the table to
show a path ran: identical [SimResult] lines with `log:burst_played` at 0
say nothing about a Burst change.

Each card's [SimEffects] count (how many times its abilities started
resolving) joins as `ability:<card_id>`, a missing card counting 0. An
engine rule change that alters how often abilities trigger (Q381 per-point
Rage triggers) moves these counts even when no card script changed; when
they stay put, the run never reached the rule. A side whose [SimEffects]
line is missing or `unavailable` contributes no ability counts.
"""
import sys


def counts(path):
    events, abilities = None, {}
    with open(path, encoding="utf-8", errors="replace") as log:
        for line in log:
            if line.startswith("[SimEvents]"):
                events = {k: int(v) for k, v in (p.rsplit("=", 1) for p in line.split()[1:])}
            elif line.startswith("[SimEffects]"):
                parts = line.split()[1:]
                if parts != ["unavailable"]:
                    abilities = {"ability:" + k: int(v) for k, v in (p.rsplit("=", 1) for p in parts)}
    return events, abilities


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        (base, base_ab), (head, head_ab) = counts(sys.argv[1]), counts(sys.argv[2])
    except (OSError, ValueError) as err:
        print("event_counts.py: %s" % err, file=sys.stderr)
        return 2
    missing = [side for side, c in (("base", base), ("head", head)) if c is None]
    if missing:
        print("event_counts.py: no [SimEvents] line in %s log" % " and ".join(missing), file=sys.stderr)
        return 2

    # Abilities have no seeded names: a card absent on one side resolved 0
    # times there. Compared only when both sides report them.
    if base_ab and head_ab:
        for name in set(base_ab) | set(head_ab):
            base[name] = base_ab.get(name, 0)
            head[name] = head_ab.get(name, 0)

    def fmt(side, name):
        return str(side[name]) if name in side else "-"

    names = sorted(set(base) | set(head))
    with open(sys.argv[3], "w", encoding="utf-8") as table:
        for name in names:
            table.write("%-40s %6s -> %s\n" % (name, fmt(base, name), fmt(head, name)))
    moved = False
    for name in names:
        if name not in base:
            print("(added) %s %d" % (name, head[name]))
        elif name not in head:
            print("(removed) %s %d" % (name, base[name]))
        elif base[name] != head[name]:
            print("%s %d -> %d" % (name, base[name], head[name]))
            moved = True
    return 1 if moved else 0


if __name__ == "__main__":
    sys.exit(main())
