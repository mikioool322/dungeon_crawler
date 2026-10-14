class_name HitRegistry
extends RefCounted

## Per-swing bookkeeping that guarantees at most one damage application per target
## per swing (AC-04, ADR-004).
##
## Pure and stateless regarding the scene: callers key it by
## `Node.get_instance_id()`, so it never stores Node references itself.
## One instance is created per swing by `AttackController`.


var _registered: Dictionary = {}


## Returns true the first time `instance_id` is seen, false afterwards.
func register_once(instance_id: int) -> bool:
	if _registered.has(instance_id):
		return false
	_registered[instance_id] = true
	return true


func has_registered(instance_id: int) -> bool:
	return _registered.has(instance_id)


func count() -> int:
	return _registered.size()


func clear() -> void:
	_registered.clear()
