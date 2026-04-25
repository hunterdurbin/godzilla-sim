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


func on_opponent_rage_changed(_ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	## Called on active cards when the opponent's rage changes.
	## Covers "When your opponent's <Rage> is increased" triggers.
	pass


func on_monster_advance(_ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	## Called on active cards when the owner's monster advances zones.
	## Covers "When this card advances" and "When this card reaches zone X" triggers.
	pass


func get_phase_start_filter() -> Dictionary:
	## Override to declare when on_phase_start should enter standby.
	## Supported keys:
	##   "phase": CardEnums.GamePhase — only enters standby for this phase
	##   "own_turn": bool — true = own turn only, false = opponent's turn only
	## Return {} to always enter standby (default, backward compatible).
	return {}


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


func on_battle_card_played(_ctx: EffectContext, _zone_index: int, _played_from_deck: bool = false) -> void:
	## Called on active cards (both players) when a battle card is played.
	## zone_index: 0-indexed zone where the card landed.
	## played_from_deck: true when the card was played directly from the deck (not from hand or discard).
	pass


func on_hand_card_discarded(_ctx: EffectContext, _discarded_card: Dictionary) -> void:
	## Called on ALL active cards when ANY card is discarded from the owner's hand.
	## Covers "Whenever you discard a battle card from hand" triggers.
	pass


func on_counter_success(_ctx: EffectContext) -> void:
	## Called on active cards when the defender successfully counters (CP >= threat).
	## Covers "When you counter the opponent's monster" triggers.
	pass


func on_strategy_discarded(_ctx: EffectContext, _strategy_card: Dictionary) -> void:
	## Called on active cards when a strategy card is sent from a strategy zone to discard.
	## Covers "When a strategy card is sent to discard" triggers.
	pass


func get_invasion_observed_filter() -> Dictionary:
	## Override to declare when on_invasion_observed should enter standby.
	## Supported keys:
	##   "own_turn": bool — true = own turn only, false = opponent's turn only
	## Return {} to always enter standby (default, backward compatible).
	return {}


func on_invasion_observed(_ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	## Called on ALL active cards for BOTH players when a monster invades.
	## Covers battle card reactions to invasion events (not the monster's own on_when_invading).
	pass


func on_discarded_for_invasion(_ctx: EffectContext) -> bool:
	## Called on a card after it is discarded for invasion cost.
	## Return true if this card plays itself from the discard pile.
	return false


# --- Replacement/prevention methods ---

func on_would_be_destroyed(_ctx: EffectContext) -> bool:
	## Called when this card would be destroyed. Return true to replace the destruction
	## (e.g., move to deck bottom instead). Returning true skips the normal destroy + revenge.
	return false


func can_be_destroyed(_ctx: EffectContext) -> bool:
	## Return false if this card cannot be destroyed by effects (conditional protection).
	return true


func prevents_rage_reduction(_ctx: EffectContext) -> bool:
	## Return true if this card prevents the owner's rage from being reduced by effects.
	return false


func on_rage_reset(_ctx: EffectContext) -> int:
	## Called during start phase rage reset. Return the new rage value to override (0 = no override).
	## Used by EBP04-010: may discard 2 cards to set rage to 2 instead of 0.
	return 0


func protects_card_from_destruction(_ctx: EffectContext, _card_data: Dictionary, _zone_idx: int) -> bool:
	## Return true if this strategy card protects the given battle card from destruction.
	## Called on active strategy cards when checking if a zone card can be destroyed.
	return false


# --- Play restriction methods ---

func on_destroy(_ctx: EffectContext, _zone_idx: int) -> void:
	## Called when this card is destroyed and removed from a zone (before revenge/banish).
	pass


func on_zone_changed(_ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	## Called when this card is moved between zones while remaining in play.
	pass


func can_be_played(_ctx: EffectContext) -> bool:
	## Return false if this card has a play restriction that prevents it from being played.
	## Checked before rank/zone validation in the rules engine.
	return true


func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
	## Return a non-empty Array of allowed zone indices to restrict which zones this card
	## can be placed in. Empty array = no restriction (any valid zone allowed).
	return []


func apply_play_cost(_ctx: EffectContext, _zone_index: int) -> bool:
	## Called after a battle card is popped from hand but before placement.
	## Also called for monster cards with alternate play costs (zone_index = -1).
	## Override to prompt the player for an optional cost (e.g., discard a card).
	## Return true if the card should be played, false to cancel (restore to hand).
	## zone_index is the target zone (0-indexed), or -1 for monsters.
	return true


func can_play_as_monster(_ctx: EffectContext) -> bool:
	## Return true if this monster card can be played via an alternate play cost.
	## Checked in addition to normal rank/trait matching in get_playable_monsters.
	## Used by EBP04-012: playable when rank 2 Biollante is current monster.
	return false


# --- Modifier methods (override to alter stats) ---

func get_counter_power_modifier(_ctx: EffectContext) -> int:
	## Return additional counter power for this card (e.g., Awakening bonuses).
	## Called during counter phase calculation on battle cards in zones.
	return 0


func get_total_cp_modifier(_ctx: EffectContext) -> int:
	## Return a flat bonus to the player's total counter power (e.g., strategy effects).
	## Called during counter phase calculation on strategy cards.
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


func get_engagement_restriction(_ctx: EffectContext) -> int:
	## Return the max rank of opponent battle cards that cannot engage with this monster.
	## -1 means no restriction. E.g., 5 means opponent's rank 5 and lower cannot engage.
	## Queried on the attacker's monster during counter phase.
	return -1


func get_play_rank_modifier_for_card(_ctx: EffectContext, _target_card: Dictionary) -> int:
	## Return rank reduction (negative) for target_card when being played from hand.
	## Called on the card itself (self-modifier) and on active strategy cards.
	return 0


func stacks_on_play(_ctx: EffectContext, _zone_index: int) -> bool:
	## Return true if this card should stack on top of the existing card in the zone
	## instead of destroying it (overload). Used for cards like Godzilla Jr.
	return false


func get_zone_play_rank_modifier(_ctx: EffectContext, _zone_index: int) -> int:
	## Return additional rank reduction (negative) when playing this card in a specific zone.
	## Unlike get_play_rank_modifier_for_card which applies globally, this is zone-specific.
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


func get_opponent_field_rank_modifier(_ctx: EffectContext) -> int:
	## Return rank reduction (negative) for battle cards already in opponent's zones.
	## Different from get_play_rank_modifier_for_card which only affects cards being played.
	return 0


func can_play_from_discard_on_monster_played(_ctx: EffectContext) -> bool:
	## Return true if this card (in the discard pile) can play itself when a monster is played.
	return false


func is_discard_play_optional() -> bool:
	## Return true if playing from discard on monster played is a "may" ability.
	## When true, the player is prompted and can decline.
	return false


func prevents_own_invasion(_ctx: EffectContext) -> bool:
	## Return true if this card prevents its own controller from invading.
	return false


func can_replace_invasion_cost(_ctx: EffectContext) -> bool:
	## Return true if this monster can replace the invasion cost (hand discard)
	## with an alternative (e.g. milling from deck).
	return false


func get_invasion_advance_bonus(_ctx: EffectContext, _invasion_icon: int) -> int:
	## Return extra zones to advance during invasion, on top of the card's invasion_icon amount.
	## Called on the invading monster. Used by EBP04-007 (Godzilla 1962): +1 on Invade 1.
	return 0


func blocks_opponent_end_phase_draw(_ctx: EffectContext) -> bool:
	## Return true if this card prevents the opponent from drawing during end phase.
	## Used by EBP04-028 (Gigan R2), EBP04-030 (Modified Gigan).
	return false


func blocks_invade1_invasion_cost(_ctx: EffectContext) -> bool:
	## Return true if this card prevents the opponent from using invade1 cards as invasion cost.
	## Used by EBP04-029 (Gigan R3).
	return false


func prevents_opponent_monster_move(_ctx: EffectContext) -> bool:
	## Return true if this card prevents the opponent from moving this player's monster via effects.
	## Used by EBP04-076 (Dormancy base strategy).
	return false


func get_strategy_hand_rank_modifier(_ctx: EffectContext, _card: Dictionary, _target_player_id: int) -> int:
	## Return rank adjustment applied to a strategy card while it is in target_player_id's hand.
	## ctx.owner is the card applying the modifier. Use target_player_id to decide who is affected:
	##   target == ctx.owner.player_id → affects own strategies
	##   target != ctx.owner.player_id → affects opponent strategies
	##   always return a value → affects both
	return 0


func on_ally_zone_card_destroyed(_ctx: EffectContext, _destroyed_card: Dictionary, _zone_idx: int) -> void:
	## Called when one of this card's controller's battle cards is destroyed.
	## Used by EBP04-039 (Zilla): moves self to zone adjacent to own monster.
	pass


func on_opponent_zone_card_destroyed(_ctx: EffectContext, _destroyed_card: Dictionary, _zone_idx: int) -> void:
	## Called on the opponent of the player whose battle card was destroyed.
	## Used by EBP04-002 (Godzilla 2004): triggers when opponent's card in same column is destroyed.
	pass


func on_card_returned_from_discard(_ctx: EffectContext, _card: Dictionary) -> void:
	## Called when the opponent returns a card from their discard pile to their hand.
	## Used by EBP04-073 (Gaira): if this is in zone 1, return own card from discard to hand.
	pass


# --- Property methods (override to declare card mechanics) ---

func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	## Return the categories of effects on this card (10.2).
	## Cards may have multiple effects spanning different categories.
	return []


func get_bot_tags() -> Array[String]:
	## Return strategic tags for bot AI decision-making.
	## Override in card scripts to declare what the effect does at a high level.
	## Supported tags:
	##   "destroys_zone"    — can destroy/remove opponent's battle card(s) from zones
	##   "draws_cards"      — draws cards into hand
	##   "boosts_cp"        — increases counter power (CP modifiers, buffs)
	##   "boosts_threat"    — increases threat level
	##   "disrupts_hand"    — forces opponent to discard from hand
	##   "blocks_zone"      — blocks opponent from playing in certain zones
	##   "blocks_invade"    — prevents opponent from invading
	##   "heals_deck"       — returns cards from discard to deck
	##   "searches_deck"    — searches deck for a specific card
	##   "advances_self"    — advances own monster (extra advance, etc.)
	##   "advances_opponent" — advances opponent's monster
	##   "weakens_opponent" — reduces opponent's CP, rank, or field presence
	##   "zone_dependent"   — effect requires being in a specific zone to activate
	##                        (override get_bot_preferred_zones to specify which zones)
	##   "mill_self"            — sends cards from own deck to own discard
	##   "mill_opponent"        — sends cards from opponent's deck to their discard
	##   "evolves"             — evolves a battle card (searches deck and stacks)
	##   "plays_from_discard"  — plays cards from the discard pile to the field
	##   "evolution"            — this card has Evolution and can be evolved into a stronger form
	##   "column_dependent_battle" — effect is stronger in the same column as opponent's battle card
	##   "column_dependent_monster" — effect depends on opponent's monster being in the same column
	##   "column_dependent_monster_self" — effect depends on own monster being in the same column as opponent's battle card(s)
	##   "column_avoid_battle_cards" — effect is harmful when opponent's battle cards are in the same column
	##   "avoid_own_adjacent" — effect is harmful to own adjacent battle cards (place away from own cards)
	##   "retreats_opponent" — retreats/moves opponent's monster backward
	##   "plays_other_cards" — plays/creates additional cards (tokens, from hand, etc.) onto the field
	return []


func get_bot_preferred_zones() -> Array[int]:
	## Return 0-indexed zone indices where this card's effect works best.
	## Used with "zone_dependent" tag so the bot knows where to place the card.
	## E.g., a card that only activates in zones 6-8 returns [5, 6, 7].
	return []


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	## Return the maximum rank of cards this effect can destroy.
	## -1 means no rank restriction (can destroy any rank).
	## Override in effect scripts with rank-limited destroy effects.
	return -1


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	## Return the maximum zone this effect would advance a monster to.
	## -1 means no cap (advances relative to current position).
	## Used by bot to evaluate whether the advance has value at current game state.
	return -1


func get_bot_advance_reliability(_owner: PlayerState, _opponent: PlayerState) -> int:
	## Return how reliably this card advances the monster (0-100).
	## 100 = guaranteed, 50 = conditional/RNG, 0 = very unlikely.
	## May factor in current zone — e.g. a card that only works from zone 4+
	## is less reliable when the monster could be pushed back to zone 3.
	## Used by combo system to prefer reliable pieces.
	return 50


func get_bot_effect_costs() -> Array[Dictionary]:
	## Return the hand discard costs required for this card's effect to fire.
	## Each entry: {"card_type": CardEnums.CardType, "count": int}
	## Empty array = no discard cost. Used by combo system to verify effect
	## costs don't consume other combo pieces.
	return []


## Bot fulfill methods — per-trigger activation checks.
## Override in effect scripts to declare when a specific trigger can't fire.
## The bot checks these to skip tag scoring when no trigger can fulfill.
## All return true by default (assume can fulfill).


func bot_can_fulfill_on_enter(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_when_invading(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_revenge(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_crush(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_discard_from_hand(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_burst_discard(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_rage_changed(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_opponent_rage_changed(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_monster_advance(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_on_phase_start(_owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	return true


func bot_can_fulfill_on_monster_played(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_counter_power(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_field_cp(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_total_cp(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_threat_level(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func bot_can_fulfill_counter_success(_owner: PlayerState, _opponent: PlayerState) -> bool:
	return true


func get_burst_rank() -> int:
	## Return the burst rank (1-4) if this card has Burst. Return -1 for no burst.
	## Burst lets a monster card be played from an earlier rank but auto-discards next end phase.
	return -1


func is_base_strategy() -> bool:
	## Return true if this is a <Base> strategy card (12.9).
	## Base strategies are exempt from the Start Phase discard rule (7.2.3),
	## and are destroyed when any monster invades into zones 6-8 (12.9.2).
	return false


func prevents_self_start_phase_discard(_ctx: EffectContext) -> bool:
	## Return true to exempt this strategy from the Start Phase discard rule (7.2.3)
	## without making it a <Base> card. Unlike Base, such cards are NOT destroyed by
	## invasion to zones 6-8 (12.9.2). Use for cards with custom anti-discard rule
	## text rather than the <Base> keyword.
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


# --- Play zone utilities (rule 5.11.1.2) ---

static func get_effect_play_zones(player: PlayerState) -> Array[int]:
	## Get valid zones for playing a battle card from an effect (rule 5.11.1.2).
	## Must avoid the monster zone if possible.
	var monster_idx := player.monster_zone - 1
	var zones: Array[int] = []
	for i in range(8):
		if i != monster_idx:
			zones.append(i)
	return zones


static func get_effect_play_adjacent_zones(player: PlayerState, zone_idx: int) -> Array[int]:
	## Get adjacent zones valid for playing a battle card from an effect (rule 5.11.1.2).
	## Must avoid the monster zone if possible.
	var monster_idx := player.monster_zone - 1
	var adjacent := get_adjacent_zones(zone_idx)
	var zones: Array[int] = []
	for zi in adjacent:
		if zi != monster_idx:
			zones.append(zi)
	return zones


# --- Monster stack utilities ---

static func monster_has_trait(player: PlayerState, trait_id: int) -> bool:
	## True if the player's current monster OR any card under it in the monster stack has the trait.
	if trait_id in player.current_monster.get("traits", []):
		return true
	for card in player.monster_stack:
		if trait_id in card.get("traits", []):
			return true
	return false


static func monster_stack_has_trait(player: PlayerState, trait_id: int) -> bool:
	## True if any card under the current monster (not the current monster itself) has the trait.
	## Use this for "If there is a card with <X> under this card" wording.
	for card in player.monster_stack:
		if trait_id in card.get("traits", []):
			return true
	return false


static func count_monster_stack_matching(player: PlayerState, filter: Callable) -> int:
	## Count cards in the monster stack (under the current monster) that match the filter predicate.
	var n: int = 0
	for card in player.monster_stack:
		if filter.call(card):
			n += 1
	return n


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
