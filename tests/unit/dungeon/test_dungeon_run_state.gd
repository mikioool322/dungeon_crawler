extends "res://tests/test_case.gd"

## AC (run lifecycle) - the transient run state: one lifecycle, mutations only while
## ACTIVE, facts recorded once, and no way for a stale run to mutate.

func _ids(values: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in values:
		ids.append(StringName(value))
	return ids


func _run() -> DungeonRunState:
	var run := DungeonRunState.new()
	run.begin(1, &"dungeon.01")
	return run


func test_a_fresh_run_starts_not_started_and_begin_activates_it_once() -> void:
	var run := DungeonRunState.new()
	assert_eq(run.status, DungeonRunState.Status.NOT_STARTED, "fresh state is NOT_STARTED")
	assert_false(run.is_active(), "not active")
	assert_true(run.begin(1, &"dungeon.01"), "begin activates")
	assert_true(run.is_active(), "active")
	assert_eq(run.run_id, 1, "run id recorded")
	assert_eq(run.dungeon_id, &"dungeon.01", "dungeon recorded")
	assert_false(run.begin(2, &"dungeon.02"), "a run is started exactly once")
	assert_eq(run.run_id, 1, "and it keeps its identity")


func test_begin_rejects_invalid_arguments() -> void:
	var run := DungeonRunState.new()
	assert_false(run.begin(0, &"dungeon.01"), "run id 0 is not an identity")
	assert_false(run.begin(1, &""), "an empty dungeon id is refused")
	assert_false(run.is_active(), "still not started")


func test_facts_are_recorded_once() -> void:
	var run := _run()
	assert_true(run.mark_enemy_defeated(&"enemy.a"), "first defeat recorded")
	assert_false(run.mark_enemy_defeated(&"enemy.a"), "a second report is ignored")
	assert_true(run.mark_chest_opened(&"chest.a"), "chest recorded")
	assert_false(run.mark_chest_opened(&"chest.a"), "a second open is ignored")
	assert_true(run.note_objective(&"objective.a"), "objective recorded")
	assert_false(run.note_objective(&"objective.a"), "a repeat is ignored")
	assert_true(run.is_objective_completed(&"objective.a"), "and it is queryable")
	assert_eq(run.defeated_enemy_ids(), _ids([&"enemy.a"]), "defeats")
	assert_eq(run.opened_chest_ids(), _ids([&"chest.a"]), "chests")
	assert_eq(run.completed_objectives(), _ids([&"objective.a"]), "objectives")


func test_empty_ids_are_never_recorded() -> void:
	var run := _run()
	assert_false(run.mark_enemy_defeated(&""), "empty enemy id")
	assert_false(run.mark_chest_opened(&""), "empty chest id")
	assert_false(run.note_objective(&""), "empty objective id")
	assert_eq(run.defeated_enemy_ids().size(), 0, "nothing recorded")


func test_completion_is_one_way_and_idempotent() -> void:
	var run := _run()
	assert_true(run.complete(), "ACTIVE -> COMPLETED")
	assert_true(run.is_completed(), "completed")
	assert_false(run.is_active(), "no longer active")
	assert_false(run.complete(), "completing twice is refused")


func test_abort_records_the_reason_and_is_one_way() -> void:
	var run := _run()
	assert_true(run.abort(&"left_world"), "ACTIVE -> ABORTED")
	assert_eq(run.abort_reason, &"left_world", "reason recorded")
	assert_eq(run.status, DungeonRunState.Status.ABORTED, "aborted")
	assert_false(run.abort(&"again"), "aborting twice is refused")
	assert_false(run.complete(), "an aborted run cannot complete")


func test_a_finished_run_refuses_further_mutations() -> void:
	var completed := _run()
	completed.complete()
	assert_false(completed.mark_enemy_defeated(&"enemy.a"), "no defeats after completion")
	assert_false(completed.mark_chest_opened(&"chest.a"), "no chests after completion")
	assert_false(completed.note_objective(&"objective.a"), "no objectives after completion")

	var aborted := _run()
	aborted.abort(&"left_world")
	assert_false(aborted.mark_enemy_defeated(&"enemy.a"), "no defeats after abort")
	assert_false(aborted.note_objective(&"objective.a"), "no objectives after abort")


func test_status_names_are_stable() -> void:
	var run := DungeonRunState.new()
	assert_eq(run.status_name(), &"not_started", "not started")
	run.begin(1, &"dungeon.01")
	assert_eq(run.status_name(), &"active", "active")
	run.complete()
	assert_eq(run.status_name(), &"completed", "completed")
	var other := DungeonRunState.new()
	other.begin(2, &"dungeon.01")
	other.abort(&"x")
	assert_eq(other.status_name(), &"aborted", "aborted")
