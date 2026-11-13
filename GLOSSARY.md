# Godzilla TCG Sim

The game-rules language of the simulator: how card abilities, effects, and
their timing are named. Rule numbers refer to the official Comprehensive Rules
in `comprehensive_rules/`.

## Abilities and effects

**Effect**:
The actions an ability performs when it resolves, from start to finish, as one
uninterrupted unit.
_Avoid_: Action (for the whole effect), resolution step

**Automatic ability**:
An ability that triggers when its condition is fulfilled ("when destroyed",
"<Enter>", "<Revenge>", "if this card leaves its zone…"). It never interrupts
the effect that triggered it; it enters standby (10.6.2).
_Avoid_: Trigger effect, triggered effect, on-destroy effect

**Replacement effect**:
An effect worded "when (A) would happen, do (B) instead". It interrupts the
effect in progress at the moment (A) would happen, so (A) never happens
(10.2.1.3).
_Avoid_: Instead-trigger, prevention trigger

**Area-changing trigger**:
The condition of an automatic ability that triggers when a card moves to,
from, or between areas, such as leaving its zone or moving to another zone
(10.6.4).
_Avoid_: Leave-play effect, link trigger

## Timing

**Standby**:
The state of an automatic ability whose condition has been fulfilled but which
has not resolved yet. It still resolves even if its card has since changed
areas (10.6.7).
_Avoid_: Pending trigger, deferred effect, queue

**Check timing**:
The point after the current effect finishes when rule actions resolve first,
then abilities in standby resolve: the turn player's first, then the
non-turn player's, each player choosing their own order (10.4.3).
_Avoid_: After the effect, resolution window
