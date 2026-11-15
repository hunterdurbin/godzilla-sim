#!/usr/bin/env python3
"""Print where one seed-matched game's [SimTrace] lines split, base vs head.

Input: two BotSimulationRunner logs of the same game run with
`--only-game=N --trace` (run_sim_diff.sh does this for each split game).
Trace lines are pile snapshots at each turn start, log tokens and ability
resolutions, in order. Log token types that only one log has (a token the
change added or removed) are dropped before comparing, so the first
difference is a behaviour change, not the new line itself.

Prints the shared lines just before the split, then each side's next lines.

Usage: trace_divergence.py <base.log> <head.log> [context=4]
Exit 0 when the traces match, 1 when they split, 2 on a usage or read error.
"""
import re
import sys

TRACE_RE = re.compile(r"^\[SimTrace\] game=\d+ (t=\d+ .*)$")
LOG_TYPE_RE = re.compile(r"^t=\d+ (log:\w+) ")


def traces(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [m.group(1) for m in map(TRACE_RE.match, (l.rstrip("\n") for l in fh)) if m]


def log_types(lines):
    return {m.group(1) for m in map(LOG_TYPE_RE.match, lines) if m}


def drop_types(lines, types):
    out = []
    for line in lines:
        m = LOG_TYPE_RE.match(line)
        if not (m and m.group(1) in types):
            out.append(line)
    return out


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    context = int(sys.argv[3]) if len(sys.argv) == 4 else 4
    try:
        base, head = traces(sys.argv[1]), traces(sys.argv[2])
    except OSError as e:
        print("trace_divergence.py: %s" % e, file=sys.stderr)
        sys.exit(2)
    if not base or not head:
        print("trace_divergence.py: no [SimTrace] lines (run the game with --trace)", file=sys.stderr)
        sys.exit(2)
    one_sided = log_types(base) ^ log_types(head)
    base, head = drop_types(base, one_sided), drop_types(head, one_sided)
    n = 0
    while n < len(base) and n < len(head) and base[n] == head[n]:
        n += 1
    if n == len(base) == len(head):
        sys.exit(0)
    if one_sided:
        print("ignored (one tree only): %s" % ", ".join(sorted(one_sided)))
    for line in base[max(0, n - context):n]:
        print("  same %s" % line)
    for line in base[n:n + context] or ["(trace ends)"]:
        print("  base %s" % line)
    for line in head[n:n + context] or ["(trace ends)"]:
        print("  head %s" % line)
    sys.exit(1)


if __name__ == "__main__":
    main()
