class_name RpcLogger
extends Object
## Debug instrumentation: per-RPC send/receive byte tallies.
## Static utility — call `RpcLogger.log_send/log_receive` from anywhere and
## `RpcLogger.print_summary()` at game end. (Demoted from an autoload in the
## 2026-07 restructure: it uses no Node features, so a class suffices.)

static var enabled: bool = true

static var _send_stats: Dictionary = {}
static var _recv_stats: Dictionary = {}


static func log_send(rpc_name: String, payload_bytes: int) -> void:
	if not enabled:
		return
	_record(_send_stats, rpc_name, payload_bytes)


static func log_receive(rpc_name: String, payload_bytes: int) -> void:
	if not enabled:
		return
	_record(_recv_stats, rpc_name, payload_bytes)


static func reset() -> void:
	_send_stats.clear()
	_recv_stats.clear()


static func print_summary() -> void:
	print("\n=== RPC Stats Summary ===")
	print("%-35s | %-4s | %5s | %9s | %7s | %7s" % ["Name", "Dir", "Count", "Total KB", "Avg B", "Max B"])
	print("-".repeat(85))
	_print_group(_send_stats, "send")
	_print_group(_recv_stats, "recv")
	print("=".repeat(85))
	print("")


static func _record(stats: Dictionary, rpc_name: String, payload_bytes: int) -> void:
	if not stats.has(rpc_name):
		stats[rpc_name] = {"count": 0, "total": 0, "min": payload_bytes, "max": 0}
	var s: Dictionary = stats[rpc_name]
	s["count"] += 1
	s["total"] += payload_bytes
	if payload_bytes < s["min"]:
		s["min"] = payload_bytes
	if payload_bytes > s["max"]:
		s["max"] = payload_bytes


static func _print_group(stats: Dictionary, direction: String) -> void:
	var names := stats.keys()
	names.sort_custom(func(a, b): return stats[b]["total"] < stats[a]["total"])
	for rpc_name in names:
		var s: Dictionary = stats[rpc_name]
		var avg: int = s["total"] / s["count"] if s["count"] > 0 else 0
		var total_kb := "%.1f" % (s["total"] / 1024.0)
		print("%-35s | %-4s | %5d | %9s | %7d | %7d" % [rpc_name, direction, s["count"], total_kb, avg, s["max"]])
