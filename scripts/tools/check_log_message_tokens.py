#!/usr/bin/env python3
"""log_message carries GameLog tokens only.

`TurnManager.log_message` and `EffectHandler.log_message` are declared
`(token: Dictionary)`: every listener (ReplayRecorder, the board log, the
headless server's broadcast buffer, the bot sim's [SimEvents]) takes a GameLog
token, and each viewer renders it in their own locale (`GameLog.render`). A
String emitted there -- `tr("STR_...")`, already translated on the host --
misses the typed replay listener and shows the host's language to a client
(hunterdurbin/godzilla-sim-issue-tracker#45).

Flags every `log_message.emit(` under scripts/ and scenes/ whose argument
does not start with a `GameLog.` call (the argument may sit on the next
line). A new kind of log line gets a GameLog builder + `render` case. No
allow-list -- the tree is clean.

Usage: python3 scripts/tools/check_log_message_tokens.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIRS = ("scripts", "scenes")
EMIT_RE = re.compile(r"\blog_message\s*\.\s*emit\s*\(\s*")
TOKEN_RE = re.compile(r"GameLog\s*\.\s*\w+\s*\(")


def gd_files():
    for scan in SCAN_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, scan)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def violations(path, lines):
    text = "\n".join(lines)
    for m in EMIT_RE.finditer(text):
        if TOKEN_RE.match(text, m.end()):
            continue
        line_no = text.count("\n", 0, m.start()) + 1
        yield "%s:%d  %s" % (path, line_no, lines[line_no - 1].strip())


def self_test():
    cases = {
        '\tlog_message.emit(GameLog.turn_start(1, 0))': False,
        '\th.log_message.emit(GameLog.invaded(pid, cid))': False,
        '\teffect_handler.log_message.emit(\n\t\tGameLog.gained_rage(pid, 1, cid))': False,
        '\tctx.effect_handler.log_message .emit( GameLog .invade1_blocked())': False,
        '\teffect_handler.log_message.emit(tr("STR_AH_INVADE1_BLOCKED"))': True,
        '\tctx.effect_handler.log_message.emit(\n\t\ttr("STR_X_FMT") % [a, b])': True,
        '\tlog_message.emit("raw text")': True,
        '\tlog_message.emit(token)': True,
        '\tlog_message.connect(_on_log_message)': False,
        strip_comment('\tx()  # log_message.emit(tr("STR_X"))'): False,
    }
    bad = [src for src, expect in cases.items()
           if bool(list(violations("x.gd", src.split("\n")))) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    for path in gd_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            lines = [strip_comment(l.rstrip("\n")) for l in fh]
        found.extend(violations(path, lines))
    for v in found:
        print("LOG_MESSAGE without a GameLog token  " + v)
    if found:
        print("\nEmit a GameLog token: add a builder + render case to"
              " scripts/replay/game_log.gd (reuse the STR key; a FMT key's"
              " args become token fields).")
        return 1
    print("log_message emits: OK (all GameLog tokens)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
