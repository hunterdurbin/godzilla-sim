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


func on_burst_discard(_ctx: EffectContext) -> void:
	## Called when this card is discarded by the Burst mechanic at end of turn.
	## The card is already in the discard pile when this triggers.
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


func on_battle_card_played(_ctx: EffectContext, _zone_index: int) -> void:
	## Called on active strategy/zone cards when the owner plays a battle card.
	## zone_index is the zone (0-indexed) where the battle card was placed.
	pass


# --- Modifier methods (override to alter stats) ---

func get_counter_power_modifier(_ctx: EffectContext) -> int:
	## Return additional counter power for this card (e.g., Awakening bonuses).
	## Called during counter phase calculation.
	return 0


func get_field_cp_modifiers(_ctx: EffectContext) -> Dictionary:
	## Return {zone_index: cp_bonus} for bonuses this card grants to OTHER zones.
	## Called on all active battle cards during counter power calculation.
	return {}


func get_threat_level_modifier(_ctx: EffectContext) -> int:
	## Return additional threat level for this monster card (e.g., conditional TL boosts).
	return 0


func can_engage(_ctx: EffectContext) -> bool:
	## Return false if this card "cannot engage" with the monster.
	## Its counter power won't be included in the total.
	return true


func get_play_rank_modifier_for_card(_ctx: EffectContext, _target_card: Dictionary) -> int:
	## Return rank reduction (negative) for target_card when being played from hand.
	## Called on the card itself (self-modifier) and on active strategy cards.
	return 0


func prevents_opponent_invasion(_ctx: EffectContext) -> bool:
	## Return true if this card's presence prevents the opponent from invading.
	return false


func can_monster_advance(_ctx: EffectContext) -> bool:
	## Return false if this monster cannot advance during end phase.
	## Used by cards like Biollante Rose Form (EBP02-024, 025).
	return true


func can_monster_invade(_ctx: EffectContext) -> bool:
	## Return false if this monster's owner cannot invade.
	## Used by cards like Biollante Rose Form (EBP02-024, 025).
	return true


func get_counter_immunity_threshold(_ctx: EffectContext) -> int:
	## Return a CP threshold below which this monster cannot be countered.
	## If defender's total CP <= threshold, monster retreats but does NOT rank up.
	## Return 0 for no immunity. Used by EBP02-027.
	return 0


func get_opponent_zone_cp_modifiers(_ctx: EffectContext) -> Dictionary:
	## Return {zone_index: cp_bonus} for bonuses this card grants to the OPPONENT's zones.
	## Used by EBP02-029 to double opponent's CP in the same column.
	return {}


func blocks_opponent_strategy_plays(_ctx: EffectContext) -> bool:
	## Return true if this card prevents the opponent from playing strategy cards.
	## Used by EBP02-070.
	return false


func can_intercept_strategy_discard(_ctx: EffectContext) -> bool:
	## Return true if this card can intercept strategy discards during start phase.
	## Intercepted strategies are placed under this card instead of going to discard.
	## Used by EBP02-012.
	return false


func get_blocked_opponent_zones(_ctx: EffectContext) -> Array[int]:
	## Return opponent zone indices where the opponent cannot play battle cards.
	## Used by cards like SpaceGodzilla R3 (EBP02-055) for column blocking.
	return []


func get_extra_end_phase_advance(_ctx: EffectContext) -> int:
	## Return extra zones to advance during end phase advance.
	## Used by SpaceGodzilla R4 (EBP02-056) for Crystal-based extra advance.
	return 0


# --- Property methods (override to declare card mechanics) ---

func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	## Return the categories of effects on this card (10.2).
	## Cards may have multiple effects spanning different categories.
	return []

func get_burst_rank() -> int:
	## Return the burst rank (1-4) if this card has Burst. Return -1 for no burst.
	## Burst lets a monster card be played from an earlier rank but auto-discards next end phase.
	return -1


func is_base_strategy() -> bool:
	## Return true if this is a <Base> strategy card (not discarded at start phase;
	## destroyed when any monster invades into zones 6-8).
	return false


# --- Zone utilities ---

func find_zone_of_card(ctx: EffectContext) -> int:
	## Find which zone (0-indexed) this card occupies on the owner's board.
	## Returns -1 if not found in any zone.
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1


# --- Column utilities ---

static func get_adjacent_zones(zone_idx: int) -> Array[int]:
	## Get zones adjacent to the given zone index (0-indexed).
	## Back row: [1][2][3][4][5], Front row: [6][7][8]
	## Columns: 3+8, 4+7, 5+6
	match zone_idx:
		0: return [1]           # zone 1 → zone 2
		1: return [0, 2]        # zone 2 → zones 1, 3
		2: return [1, 3, 7]     # zone 3 → zones 2, 4, 8
		3: return [2, 4, 6]     # zone 4 → zones 3, 5, 7
		4: return [3, 5]        # zone 5 → zones 4, 6
		5: return [4, 6]        # zone 6 → zones 5, 7
		6: return [3, 5, 7]     # zone 7 → zones 4, 6, 8
		7: return [2, 6]        # zone 8 → zones 3, 7
	return []


static func get_opponent_column_zones(zone_idx: int) -> Array[int]:
	## Get the opponent's zone indices in the same column as the given zone.
	## Accounts for 180° board mirroring between players.
	## Columns: 1=[1], 2=[2], 3=[3,8], 4=[4,7], 5=[5,6]
	## Cross-board: your column 1 faces opponent's column 5, etc.
	match zone_idx:
		0: return [4, 5]   # zone 1 → opponent zones 5, 6
		1: return [3, 6]   # zone 2 → opponent zones 4, 7
		2: return [2, 7]   # zone 3 → opponent zones 3, 8
		3: return [1]      # zone 4 → opponent zone 2
		4: return [0]      # zone 5 → opponent zone 1
		5: return [0]      # zone 6 → opponent zone 1
		6: return [1]      # zone 7 → opponent zone 2
		7: return [2, 7]   # zone 8 → opponent zones 3, 8
	return []
