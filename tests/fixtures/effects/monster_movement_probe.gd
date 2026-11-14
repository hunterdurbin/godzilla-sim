extends CardEffect

## Test-only effect that records monster-movement traffic into `seen`, so
## the MonsterMover suite can check which advance / <When invading> /
## Crush entries a move collected. Register one instance under PATH and
## use `card()` for the monster and the battle cards.

const PATH := "test://monster_movement_probe"
const HOOKS := ["on_when_invading", "on_monster_advance", "on_leave_play"]

var seen: Array = []


static func register(handler: EffectHandler) -> CardEffect:
	var probe: CardEffect = load("res://tests/fixtures/effects/monster_movement_probe.gd").new()
	handler.registry.register_for_test(PATH, probe, HOOKS)
	return probe


static func card(id: String) -> Dictionary:
	return {"id": id, "name": id, "card_type": CardEnums.CardType.BATTLE, "rank": 1,
			"counter_power": 5000, "traits": [], "invasion_icon": 1, "effect_script": PATH}


static func monster(id: String = "MON") -> Dictionary:
	return {"id": id, "name": id, "card_type": CardEnums.CardType.MONSTER, "rank": 1,
			"threat_level": 10000, "traits": [], "effect_script": PATH}


func on_when_invading(ctx: EffectContext, from_zone: int, to_zone: int) -> void:
	seen.append("invading:%s:%d>%d" % [ctx.card_data.get("id"), from_zone, to_zone])


func on_monster_advance(ctx: EffectContext, from_zone: int, to_zone: int) -> void:
	seen.append("advance:%s:%d>%d" % [ctx.card_data.get("id"), from_zone, to_zone])


func on_leave_play(ctx: EffectContext, zone_index: int) -> void:
	seen.append("leave:%s:%d" % [ctx.card_data.get("id"), zone_index])
