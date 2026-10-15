class_name DungeonService
extends RefCounted

## Owns the dungeon *policy*: which dungeons may be entered, the lifecycle of the one
## active run, completion objectives and the two reward scopes (ADR-012, ADR-013).
##
## Invariants:
## - Exactly one active run at a time; every run mutation goes through this service, so
##   UI and portals never touch `DungeonProgress` or `DungeonRunState` collections.
## - A run-scoped reward is granted once per run; a story reward is granted once per
##   save. Completion is idempotent: repeating it never grants or unlocks twice.
## - Completion is driven by the *definition's* objective id, never by "some enemy
##   died": an ordinary enemy death cannot complete a dungeon.
## - The service holds no Node reference and never serialises the run state.

signal run_started(run_id: int, dungeon_id: StringName)
signal run_aborted(run_id: int, dungeon_id: StringName, reason: StringName)
signal dungeon_completed(dungeon_id: StringName, first_clear: bool, run_id: int)
signal reward_granted(dungeon_id: StringName, scope: StringName, code: StringName)

const CODE_OK := &"ok"
const CODE_UNKNOWN_DUNGEON := &"unknown_dungeon"
const CODE_LOCKED := &"locked"
const CODE_ALREADY_COMPLETED := &"already_completed"
const CODE_NO_ACTIVE_RUN := &"no_active_run"
const CODE_OBJECTIVE_NOT_MET := &"objective_not_met"
const CODE_NO_REWARD := &"no_reward"
const CODE_UNKNOWN_REWARD := &"unknown_reward"

## Loot keys of the two dungeon-level rewards: `"<dungeon_id>/<reward_id>"` (ADR-013).
## The ledger, not the key, decides the scope: story rewards are persisted, regular
## rewards live in the transient run ledger.
const FIRST_CLEAR_SOURCE := &"first_clear"
const COMPLETION_SOURCE := &"completion"

var _registry: ContentRegistry = null
var _progress: DungeonProgress = null
var _loot: LootService = null
var _run: DungeonRunState = null
var _next_run_id: int = 0


func setup(registry: ContentRegistry, progress: DungeonProgress, loot: LootService) -> void:
	_registry = registry
	_progress = progress
	_loot = loot


func progress() -> DungeonProgress:
	return _progress


func current_run() -> DungeonRunState:
	return _run


## The run that is accepting mutations, or null when none is active.
func active_run() -> DungeonRunState:
	if _run != null and _run.is_active():
		return _run
	return null


func is_run_active() -> bool:
	return active_run() != null


## `DungeonDefinition` that owns `world_id`, or null when the world is not a dungeon.
func dungeon_for_world(world_id: StringName) -> DungeonDefinition:
	if _registry == null or world_id == &"":
		return null
	return _registry.find_dungeon_for_world(world_id)


## May a run in this dungeon start right now? Returns `CODE_OK` or a refusal code.
func can_enter(dungeon_id: StringName) -> StringName:
	if _registry == null or _progress == null:
		return CODE_UNKNOWN_DUNGEON
	var definition := _registry.find_dungeon(dungeon_id)
	if definition == null:
		return CODE_UNKNOWN_DUNGEON
	if not _progress.is_unlocked(dungeon_id):
		return CODE_LOCKED
	if not definition.repeatable and _progress.is_completed(dungeon_id):
		return CODE_ALREADY_COMPLETED
	return CODE_OK


## Starts a run. Returns the new state, or null when the dungeon may not be entered.
## A previous active run is aborted first (one active run at a time).
func start_run(dungeon_id: StringName) -> DungeonRunState:
	var code := can_enter(dungeon_id)
	if code != CODE_OK:
		push_warning("DungeonService: cannot start '%s' (%s)" % [dungeon_id, code])
		return null
	if is_run_active():
		abort_run(&"superseded")

	_next_run_id += 1
	var run := DungeonRunState.new()
	if not run.begin(_next_run_id, dungeon_id):
		return null
	_run = run
	if _loot != null:
		_loot.begin_run(run.run_id)
	run_started.emit(run.run_id, dungeon_id)
	return run


## Leaves the current world: an unfinished run is aborted, a completed run stays as a
## record until the next run starts.
func leave_world() -> void:
	if is_run_active():
		abort_run(&"left_world")


func abort_run(reason: StringName = &"") -> bool:
	var run := active_run()
	if run == null:
		return false
	var dungeon_id := run.dungeon_id
	var run_id := run.run_id
	if not run.abort(reason):
		return false
	if _loot != null:
		_loot.end_run()
	run_aborted.emit(run_id, dungeon_id, reason)
	return true


## Reports a satisfied objective. Completes the dungeon only when the objective is the
## one its definition requires and a run is active.
func note_objective(objective_id: StringName) -> bool:
	var run := active_run()
	if run == null:
		push_warning("DungeonService: objective '%s' reported without an active run" % objective_id)
		return false
	var definition := _definition_for(run)
	if definition == null:
		return false
	run.note_objective(objective_id)
	if objective_id != definition.completion_objective:
		return false
	return complete_run()


## Completes the active run when its objective is satisfied. Idempotent: a second call
## for the same run does nothing.
func complete_run() -> bool:
	var run := active_run()
	if run == null:
		return false
	var definition := _definition_for(run)
	if definition == null:
		return false
	if not run.is_objective_completed(definition.completion_objective):
		return false

	var dungeon_id := run.dungeon_id
	var first_clear := _progress.mark_completed(dungeon_id)
	if first_clear:
		_progress.unlock_all(definition.first_clear_unlocks)

	_grant_regular_completion(definition, run)
	if first_clear:
		_grant_first_clear(definition)

	if not run.complete():
		return false
	dungeon_completed.emit(dungeon_id, first_clear, run.run_id)
	return true


## Retries story rewards whose dungeon is completed but whose claim is missing (for
## example because the reward content was broken on the first attempt). Returns how
## many rewards were granted. The boot path calls it; a completion grants directly.
func claim_pending_first_clear_rewards() -> int:
	if _registry == null or _progress == null:
		return 0
	var granted := 0
	for dungeon_id in _progress.completed_ids():
		if _progress.was_first_clear_claimed(dungeon_id):
			continue
		var definition := _registry.find_dungeon(dungeon_id)
		if definition == null or definition.first_clear_reward_id == &"":
			continue
		if _grant_first_clear(definition):
			granted += 1
	return granted


## Story reward of a first clear; true when it was granted (or already claimed).
func _grant_first_clear(definition: DungeonDefinition) -> bool:
	var code := _grant(
		definition.first_clear_reward_id, LootGrant.SCOPE_STORY, definition, 0
	)
	reward_granted.emit(definition.dungeon_id, LootGrant.SCOPE_STORY, code)
	if code == LootService.CODE_GRANTED or code == LootService.CODE_DUPLICATE:
		_progress.mark_first_clear_claimed(definition.dungeon_id)
		return true
	return false


## Repeatable reward of every completion; granted once per run.
func _grant_regular_completion(definition: DungeonDefinition, run: DungeonRunState) -> void:
	var code := _grant(
		definition.regular_reward_id, LootGrant.SCOPE_RUN, definition, run.run_id
	)
	reward_granted.emit(definition.dungeon_id, LootGrant.SCOPE_RUN, code)


func _grant(
	reward_id: StringName, scope: StringName, definition: DungeonDefinition, run_id: int
) -> StringName:
	if reward_id == &"":
		return CODE_NO_REWARD
	if _loot == null:
		return CODE_UNKNOWN_REWARD
	var reward: RewardDefinition = null
	if _registry != null:
		reward = _registry.find_reward(reward_id)
	if reward == null:
		push_warning("DungeonService: unknown reward id '%s'" % reward_id)
		return CODE_UNKNOWN_REWARD
	# Key shape `<dungeon_id>/<reward_id>`: one key per reward slot, so a second story
	# reward added later gets its own persistent claim automatically.
	var grant := LootGrant.from_reward(
		LootGrant.key_for(definition.dungeon_id, reward_id), reward, scope
	)
	if grant == null:
		return CODE_UNKNOWN_REWARD
	grant.run_id = run_id
	return _loot.grant(grant)


func _definition_for(run: DungeonRunState) -> DungeonDefinition:
	if _registry == null:
		return null
	return _registry.find_dungeon(run.dungeon_id)


func _to_string() -> String:
	return "DungeonService(progress=%s, run=%s)" % [_progress, _run]
