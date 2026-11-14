#!/usr/bin/env python3
"""Compare the [SimEvents] rule-event counts of a base and a head sim log.

Usage: event_counts.py <base.log> <head.log> <table_out>

Writes every event to <table_out> as `name  base -> head` (sorted by name),
and prints to stdout only the events whose counts differ, one per line.
Exit 0 always; a log without a [SimEvents] line (a run that died early)
reads as "?" on that side.

An event is a GameEvents signal emission (`monster_countered`) or an
EffectHandler log token type (`log:burst_played`); see
tests/sim/bot_simulation_runner.gd `_event_counts`. Use the table to show a
path ran: identical [SimResult] lines with `log:burst_played` at 0 say
nothing about a Burst change.
"""
import sys


def counts(path):
    with open(path, encoding="utf-8", errors="replace") as log:
        for line in log:
            if line.startswith("[SimEvents]"):
                return {k: int(v) for k, v in (p.rsplit("=", 1) for p in line.split()[1:])}
    return None


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    base, head = counts(sys.argv[1]), counts(sys.argv[2])
    names = sorted(set(base or {}) | set(head or {}))

    def fmt(side, name):
        return "?" if side is None else str(side.get(name, 0))

    with open(sys.argv[3], "w", encoding="utf-8") as table:
        for name in names:
            table.write("%-40s %6s -> %s\n" % (name, fmt(base, name), fmt(head, name)))
    for name in names:
        if fmt(base, name) != fmt(head, name):
            print("%s %s -> %s" % (name, fmt(base, name), fmt(head, name)))


if __name__ == "__main__":
    main()
