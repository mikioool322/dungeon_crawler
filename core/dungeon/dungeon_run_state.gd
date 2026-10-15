class_name DungeonRunState
extends RefCounted

## Transient state of exactly one dungeon run (ADR-012). Never serialised: a run lives
## from entering a dungeon until the player completes or leaves it, and the next run
## starts from a fresh instance.
##
## Invariants:
## - One active run at a time; the id is issued by the owner (`DungeonService`) and every
##   mutation is refused once the run is no longer ACTIVE (a stale run cannot mutate).
## - No Node references: only stable ids and counters, so a run cannot keep a scene alive.
## - Collections are read-only from outside: callers use the explicit mark/query API.

enum Status { NOT_STARTED, ACTIVE, COMPLETED, ABORTED }

var run_id: int = 0
var dungeon_id: StringName = &""
var status: Status = Status.NOT_STARTED
var abort_reason: StringName = &""

var _defeated_enemy_ids: Dictionary = {}
var _opened_chest_ids: Dictionary = {}
var _completed_objectives: Dictionary = {}


## Starts the run. False when it was already started (a run is started exactly once).
func begin(p_run_id: int, p_dungeon_id: StringName) -> bool:
	if status != Status.NOT_STARTED or p_run_id <= 0 or p_dungeon_id == &"":
		return false
	run_id = p_run_id
	dungeon_id = p_dungeon_id
	status = Status.ACTIVE
	return true


func is_active() -> bool:
	return status == Status.ACTIVE


func is_completed() -> bool:
	return status == Status.COMPLETED


## Records a defeated enemy; true when this source was not recorded before.
func mark_enemy_defeated(source_id: StringName) -> bool:
	if not is_active() or source_id == &"":
		return false
	return _mark_once(_defeated_enemy_ids, source_id)


## Records an opened chest; true when this source was not recorded before.
func mark_chest_opened(source_id: StringName) -> bool:
	if not is_active() or source_id == &"":
		return false
	return _mark_once(_opened_chest_ids, source_id)


## Records a satisfied objective; true when it was not recorded before.
func note_objective(objective_id: StringName) -> bool:
	if not is_active() or objective_id == &"":
		return false
	return _mark_once(_completed_objectives, objective_id)


func is_objective_completed(objective_id: StringName) -> bool:
	return _completed_objectives.has(objective_id)


func defeated_enemy_ids() -> Array[StringName]:
	return _sorted_ids(_defeated_enemy_ids)


func opened_chest_ids() -> Array[StringName]:
	return _sorted_ids(_opened_chest_ids)


func completed_objectives() -> Array[StringName]:
	return _sorted_ids(_completed_objectives)


## ACTIVE -> COMPLETED. False when the run is not active (idempotent by construction).
func complete() -> bool:
	if not is_active():
		return false
	status = Status.COMPLETED
	return true


## ACTIVE -> ABORTED with a diagnostic reason. False when the run is not active.
func abort(reason: StringName = &"") -> bool:
	if not is_active():
		return false
	status = Status.ABORTED
	abort_reason = reason
	return true


func status_name() -> StringName:
	match status:
		Status.NOT_STARTED:
			return &"not_started"
		Status.ACTIVE:
			return &"active"
		Status.COMPLETED:
			return &"completed"
		Status.ABORTED:
			return &"aborted"
	return &"unknown"


func _mark_once(target: Dictionary, id: StringName) -> bool:
	if target.has(id):
		return false
	target[id] = true
	return true


func _sorted_ids(source: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in source.keys():
		ids.append(id)
	ids.sort()
	return ids


func _to_string() -> String:
	return "DungeonRunState(run=%d, %s, %s)" % [run_id, dungeon_id, status_name()]
