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
then abilities in standby resolve one at a time: the turn player picks one of
theirs while they have any, otherwise the non-turn player picks one of theirs;
rule actions are performed again after each ability (10.4.3).
_Avoid_: After the effect, resolution window

## Rule actions

**Rule action**:
A process the game rules perform on their own, with no player choosing it,
when its condition is met. Rule actions resolve at a check timing, before any
ability in standby (11.1, 10.4.3.1).
_Avoid_: State-based action, cleanup

**Interrupt rule action**:
A rule action performed the moment its condition is met, even in the middle
of an effect; the effect then continues. The turn player's are performed first
(11.1.2.1). Abilities it triggers still enter standby.
_Avoid_: Immediate rule, instant rule action

**Crush**:
The interrupt rule action that destroys a battle card in the same zone as its
master's monster (11.3).
_Avoid_: Trample, squash

**Overload**:
The non-interrupt rule action that, when a zone holds more than one card not
in a stack, keeps the card placed last and destroys the rest. It is performed
only at a check timing and never triggers <Revenge> (11.5, 12.7.2).
_Avoid_: Replace, overwrite

**Destroy**:
Putting a card from a zone or strategy zone into its owner's discard pile. Effect destroys, Crush and Overload are all destroys (5.12.1.1); only an effect destroy is something "your opponent's effects" protection can stop.
_Avoid_: Kill, remove

## Zones and movement

**Play**:
Placing a battle card on a zone from outside the field, or putting a token into existence in a zone (5.11.1, 5.11.4). Japanese 出現. Evolve is a play from the deck. "Whenever … plays a battle card" abilities watch every play, and EBP02-055's "cannot play" refuses every play (Q270).
_Avoid_: Summon, deploy, enter (for the act itself)

**Appear**:
The English rules' word for a play in 5.17.1 (Evolve) and 9.1.2 (tokens). The Japanese rules use one verb, 出現, for all of these, so an appear is a play, not a separate act. Check `comprehensive_rules/rules-ja.txt` when the English wording seems to split them.
_Avoid_: Spawn

**Evolve**:
Playing a new battle card from the deck on top of a battle card on the field, forming a stack (5.17; Q176 "山札から…重ねて出現させる").
_Avoid_: Upgrade, transform

**Advance**:
Moving an invading monster one zone forward; an advance "to" a zone repeats single advances (5.13). An advance is either from an invasion or not, and only an advance from an invasion can trigger <When invading> or win the game.
_Avoid_: Step, push

**Victory through invasion**:
Winning because your invading monster advanced from an invasion out of zone 8 while your opponent's zone 8 held no battle card (5.13.1.1.2).
_Avoid_: Invasion win, breakthrough
