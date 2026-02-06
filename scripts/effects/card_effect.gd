class_name CardEffect
extends RefCounted

## Base class for card effect scripts. Override trigger methods to define card abilities.
## Effect scripts are stateless — all state comes from the EffectContext passed to each call.


# --- Trigger methods (override in subclasses) ---

func on_enter(_ctx: EffectContext) -> void:
	## Called when this card enters play (battle card placed in zone, strategy played, monster played).
	pass


func on_when_invading(_ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	## Called on the monster card when it invades (once per zone advanced).
	pass


func on_revenge(_ctx: EffectContext) -> void:
	## Called when this card is destroyed by an effect (<Revenge> / <Destroy>).
	pass


func on_crush(_ctx: EffectContext) -> void:
	## Called when this card is destroyed by the crush rule (monster advancing into its zone).
	pass


func on_discard_from_hand(_ctx: EffectContext) -> void:
	## Called when this card is discarded from hand (e.g., by gain rage or opponent effect).
	pass


func on_rage_changed(_ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	## Called on active cards when the owner's rage changes.
	## Covers "Whenever this card's <Rage> is increased" and similar triggers.
	pass


func on_monster_advance(_ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	## Called on active cards when the owner's monster advances zones.
	## Covers "When this card advances" and "When this card reaches zone X" triggers.
	pass


func on_phase_start(_ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	## Called at the beginning of each phase on all active cards.
	## Covers "At the beginning of your counter/main/end phase" triggers.
	pass


func on_phase_end(_ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	## Called at the end of each phase on all active cards.
	pass


func on_monster_played(_ctx: EffectContext, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	## Called on active cards when the owner plays a monster card.
	## Covers "<Your Turn> When you play a monster card" triggers.
	pass


# --- Modifier methods (override to alter stats) ---

func get_counter_power_modifier(_ctx: EffectContext) -> int:
	## Return additional counter power for this card (e.g., Awakening bonuses).
	## Called during counter phase calculation.
	return 0


func get_threat_level_modifier(_ctx: EffectContext) -> int:
	## Return additional threat level for this monster card (e.g., conditional TL boosts).
	return 0


func can_engage(_ctx: EffectContext) -> bool:
	## Return false if this card "cannot engage" with the monster.
	## Its counter power won't be included in the total.
	return true


# --- Property methods (override to declare card mechanics) ---

func get_burst_rank() -> int:
	## Return the burst rank (1-4) if this card has Burst. Return -1 for no burst.
	## Burst lets a monster card be played from an earlier rank but auto-discards next end phase.
	return -1


func is_base_strategy() -> bool:
	## Return true if this is a <Base> strategy card (not discarded at start phase;
	## destroyed when any monster invades into zones 6-8).
	return false
