extends "res://tests/test_case.gd"

## AC (definition validation) - DungeonDefinition is self-contained data; the registry
## owns the cross-reference checks (see test_content_registry).


func _definition() -> DungeonDefinition:
	var definition := DungeonDefinition.new()
	definition.dungeon_id = &"dungeon.test"
	definition.display_name = "Test Dungeon"
	definition.world_id = &"world.test"
	definition.entry_spawn_id = &"spawn.test"
	definition.completion_objective = &"objective.test"
	return definition


func test_a_complete_definition_is_valid() -> void:
	var definition := _definition()
	assert_eq(definition.validation_errors().size(), 0, "no errors: %s" % definition.validation_errors())
	assert_true(definition.is_valid(), "valid")
	assert_true(definition.is_start_dungeon(), "no prerequisites means available at the start")
	assert_true(definition.repeatable, "dungeons are repeatable by default")


func test_every_required_field_is_reported() -> void:
	var definition := _definition()
	definition.dungeon_id = &""
	assert_true(_mentions(definition, "dungeon_id"), "empty id")
	definition = _definition()
	definition.display_name = ""
	assert_true(_mentions(definition, "display_name"), "empty display name")
	definition = _definition()
	definition.world_id = &""
	assert_true(_mentions(definition, "world_id"), "empty world")
	definition = _definition()
	definition.entry_spawn_id = &""
	assert_true(_mentions(definition, "entry_spawn_id"), "empty entry spawn")
	definition = _definition()
	definition.completion_objective = &""
	assert_true(_mentions(definition, "completion_objective"), "empty objective")


func test_id_lists_reject_empty_duplicate_and_self_references() -> void:
	var definition := _definition()
	definition.prerequisites = [&""] as Array[StringName]
	assert_true(_mentions(definition, "empty id"), "empty prerequisite")

	definition = _definition()
	definition.prerequisites = [&"dungeon.a", &"dungeon.a"] as Array[StringName]
	assert_true(_mentions(definition, "repeats"), "duplicate prerequisite")

	definition = _definition()
	definition.prerequisites = [&"dungeon.test"] as Array[StringName]
	assert_true(_mentions(definition, "itself"), "self prerequisite")

	definition = _definition()
	definition.first_clear_unlocks = [&"dungeon.test"] as Array[StringName]
	assert_true(_mentions(definition, "itself"), "self unlock")

	definition = _definition()
	definition.first_clear_unlocks = [&""] as Array[StringName]
	assert_true(_mentions(definition, "empty id"), "empty unlock target")


func test_prerequisites_make_it_a_non_start_dungeon() -> void:
	var definition := _definition()
	definition.prerequisites = [&"dungeon.01"] as Array[StringName]
	assert_true(definition.is_valid(), "a prerequisite is valid data")
	assert_false(definition.is_start_dungeon(), "it needs an earlier completion")


func test_reward_ids_are_optional_content_ids() -> void:
	var definition := _definition()
	assert_eq(definition.regular_reward_id, &"", "no regular reward by default")
	assert_eq(definition.first_clear_reward_id, &"", "no story reward by default")
	assert_true(definition.is_valid(), "a dungeon without rewards is valid")
	definition.regular_reward_id = &"reward.regular.test"
	definition.first_clear_reward_id = &"reward.story.test"
	assert_true(definition.is_valid(), "reward ids are plain references")


func _mentions(definition: DungeonDefinition, needle: String) -> bool:
	for message in definition.validation_errors():
		if message.contains(needle):
			return true
	return false
