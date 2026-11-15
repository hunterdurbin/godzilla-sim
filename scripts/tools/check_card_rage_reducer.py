#!/usr/bin/env python3
"""A card script's Rage reduction names its own controller as the reducer.

`EffectHandler.reduce_rage(player_id, amount, reducer_id)` hands `reducer_id`
to the prevention effects: EBP03-004 stops only the opponent's effects
(hunterdurbin/godzilla-sim-issue-tracker#35 row 20). The reducer is the
controller of the reducing effect, never whoever's ability happens to be
resolving (hunterdurbin/godzilla-sim-issue-tracker#48). In a card script that
controller is `ctx.owner`, so every call passes `ctx.owner.player_id` as its
third argument. Any other value (`-1`, `ctx.opponent.player_id`, a loop
variable) misattributes the reduction and lets it slip past, or be wrongly
stopped by, a prevention effect.

Flags, in the per-card scripts (scripts/effects/<set>/*.gd), every
`reduce_rage(` call whose third argument is not `ctx.owner.player_id`,
including a call spread over several lines.

Usage: python3 scripts/tools/check_card_rage_reducer.py
"""
import re
import sys

from gd_ratchet import card_scripts, read_lines

CALL_RE = re.compile(r"\breduce_rage\s*\(")
REDUCER = "ctx.owner.player_id"


def _args(text, start):
    """The top-level arguments of the call whose `(` ends at `start`, or None
    when the parentheses never close."""
    depth, args, cur = 1, [], ""
    for ch in text[start:]:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                args.append(cur.strip())
                return args
        if ch == "," and depth == 1:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return None


def violations(path, lines):
    text = "\n".join(lines)
    for m in CALL_RE.finditer(text):
        if text[:m.start()].rstrip().endswith("func"):
            continue
        args = _args(text, m.end())
        if args is None or len(args) != 3 or args[2] != REDUCER:
            line_no = text.count("\n", 0, m.start()) + 1
            yield "%s:%d  %s" % (path, line_no, lines[line_no - 1].strip())


def self_test():
    p = "scripts/effects/ebp01/ebp01_024.gd"
    cases = {
        "\tctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1, ctx.owner.player_id)": False,
        "\tctx.effect_handler.reduce_rage(pid, 2, ctx.owner.player_id)": False,
        "\tctx.effect_handler.reduce_rage(ctx.opponent.player_id, mini(2, f(a, b)), ctx.owner.player_id)": False,
        "\tctx.effect_handler.reduce_rage(\n\t\tctx.opponent.player_id, 1,\n\t\tctx.owner.player_id)": False,
        "\tctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1, -1)": True,
        "\tctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1, ctx.opponent.player_id)": True,
        "\tctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)": True,
        "\tctx.effect_handler.reduce_rage(\n\t\tctx.opponent.player_id, 1,\n\t\tpid)": True,
        "\tvar can_reduce_rage := ctx.opponent_has_rage()": False,
    }
    bad = [src for src, expect in cases.items()
           if bool(list(violations(p, src.split("\n")))) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    calls = 0
    for path in card_scripts():
        lines = read_lines(path)
        calls += sum(len(CALL_RE.findall(l)) for l in lines)
        found.extend(violations(path, lines))
    for v in found:
        print("reduce_rage reducer is not ctx.owner.player_id  " + v)
    if found:
        print("\nA card script's Rage reduction is its controller's effect:"
              " pass ctx.owner.player_id as reduce_rage's reducer_id"
              " (EBP03-004 judges it; hunterdurbin/godzilla-sim-issue-tracker#48).")
        return 1
    print("card rage reducers: OK (%d reduce_rage calls name ctx.owner)" % calls)
    return 0


if __name__ == "__main__":
    sys.exit(main())
