class_name EffectExecutionState
extends RefCounted

## Cross-cutting mutable state for effect execution, shared by reference
## between the EffectHandler facade and its modules. Which ability is
## resolving and the standby pool belong to CheckTiming.

## Max destroyable rank for the in-flight zone-target prompt (bot filtering).
var pending_destroy_max_rank: int = -1
