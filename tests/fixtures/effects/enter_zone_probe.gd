extends CardEffect

## Test-only effect that records enter-zone traffic into `seen`, so the
## EnterZone suites can check which entries one entry submitted. Register
## one instance under PATH for every card in a test; each line names the
## card the hook ran for.

const PATH := "test://enter_zone_probe"
const HOOKS := ["on_enter", "on_battle_card_played", "on_leave_play", "on_zone_changed"]

var seen: Array = []


static func register(handler: EffectHandler) -> CardEffect:
	var probe: CardEffect = load("res://tests/fixtures/effects/enter_zone_probe.gd").new()
	handler.registry.register_for_test(PATH, probe, HOOKS)
	return probe


static func card(id: String, rank: int = 1) -> Dictionary:
	return {"id": id, "name": id, "card_type": CardEnums.CardType.BATTLE, "rank": rank,
			"counter_power": 5000, "traits": [], "invasion_icon": 1, "effect_script": PATH}


func on_enter(ctx: EffectContext) -> void:
	seen.append("enter:%s:effect=%s:evo=%s" % [ctx.card_data.get("id"),
			ctx.card_data.get("played_from_effect", false),
			ctx.card_data.get("played_through_evolution", false)])


func on_battle_card_played(ctx: EffectContext, zone_index: int, from_deck: bool = false) -> void:
	seen.append("played@%s:%d:deck=%s" % [ctx.card_data.get("id"), zone_index, from_deck])


func on_leave_play(ctx: EffectContext, zone_index: int) -> void:
	seen.append("leave:%s:%d" % [ctx.card_data.get("id"), zone_index])


func on_zone_changed(ctx: EffectContext, from_zone: int, to_zone: int) -> void:
	seen.append("moved:%s:%d>%d" % [ctx.card_data.get("id"), from_zone, to_zone])
