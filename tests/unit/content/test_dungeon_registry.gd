extends "res://tests/test_case.gd"

## AC (dungeon content validation) - the registry's dungeon bucket reports authoring
## problems as data: duplicates, unknown world, unknown prerequisite/unlock/reward,
## a world owned by two dungeons, unreachable dungeons and a missing start dungeon.

const WORLD_A := &"world.test.a"
const WORLD_B := &"world.test.b"


func _world(id: StringName) -> WorldDefinition:
	var world := WorldDefinition.new()
	world.id = id
	world.display_name = String(id)
	world.scene = PackedScene.new()
	world.default_spawn_id = &"spawn.test"
	return world


func _dungeon(
	id: StringName,
	world_id: StringName = WORLD_A,
	prerequisites: Array[StringName] = [],
	unlocks: Array[StringName] = [],
	regular_reward: StringName = &"",
	story_reward: StringName = &""
) -> DungeonDefinition:
	var dungeon := DungeonDefinition.new()
	dungeon.dungeon_id = id
	dungeon.display_name = String(id)
	dungeon.world_id = world_id
	dungeon.entry_spawn_id = &"spawn.test"
	dungeon.completion_objective = &"objective.%s" % id
	dungeon.prerequisites = prerequisites
	dungeon.first_clear_unlocks = unlocks
	dungeon.regular_reward_id = regular_reward
	dungeon.first_clear_reward_id = story_reward
	return dungeon


func _build(
	dungeons: Array[DungeonDefinition], worlds: Array[WorldDefinition] = [],
	rewards: Array[RewardDefinition] = []
) -> ContentRegistry:
	var manifest := ContentManifest.new()
	manifest.dungeons = dungeons
	var world_list: Array[WorldDefinition] = worlds
	if world_list.is_empty():
		world_list = [_world(WORLD_A), _world(WORLD_B)]
	manifest.worlds = world_list
	manifest.rewards = rewards
	return ContentRegistry.build(manifest)


func _has_error(registry: ContentRegistry, needle: String) -> bool:
	for message in registry.errors:
		if message.contains(needle):
			return true
	return false


func test_a_valid_dungeon_graph_is_accepted() -> void:
	var registry := _build([_dungeon(&"dungeon.a", WORLD_A, [] as Array[StringName],
		[&"dungeon.b"] as Array[StringName]), _dungeon(&"dungeon.b", WORLD_B,
		[&"dungeon.a"] as Array[StringName])])
	assert_true(registry.is_valid(), "valid graph: %s" % registry.errors)
	assert_eq(registry.start_dungeon_ids(), [&"dungeon.a"] as Array[StringName], "one start dungeon")
	assert_not_null(registry.find_dungeon(&"dungeon.a"), "lookup works")
	assert_eq(registry.all_dungeons().size(), 2, "both dungeons are indexed")
	assert_eq(
		registry.find_dungeon_for_world(WORLD_B).dungeon_id, &"dungeon.b", "reverse lookup works"
	)


func test_an_empty_dungeon_bucket_stays_valid() -> void:
	var registry := _build([] as Array[DungeonDefinition])
	assert_true(registry.is_valid(), "no dungeons is not an error: %s" % registry.errors)
	assert_eq(registry.start_dungeon_ids().size(), 0, "and there is nothing to start")


func test_duplicate_dungeon_ids_are_reported() -> void:
	var registry := _build([
		_dungeon(&"dungeon.a", WORLD_A),
		_dungeon(&"dungeon.a", WORLD_B),
	])
	assert_false(registry.is_valid(), "duplicates invalidate")
	assert_true(_has_error(registry, "duplicates the id"), "%s" % registry.errors)
	assert_eq(registry.find_dungeon(&"dungeon.a").world_id, WORLD_A, "the first definition stays")


func test_an_unknown_world_is_reported() -> void:
	var registry := _build([_dungeon(&"dungeon.a", &"world.missing")])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "world 'world.missing' is not listed"), "%s" % registry.errors)


func test_an_unknown_prerequisite_is_reported() -> void:
	var registry := _build([_dungeon(&"dungeon.a", WORLD_A, [&"dungeon.ghost"] as Array[StringName])])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "prerequisite 'dungeon.ghost' is not listed"), "%s" % registry.errors)


func test_an_unknown_unlock_target_is_reported() -> void:
	var registry := _build([_dungeon(&"dungeon.a", WORLD_A, [] as Array[StringName],
		[&"dungeon.ghost"] as Array[StringName])])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "first-clear unlock 'dungeon.ghost' is not listed"), "%s" % registry.errors)


func test_unknown_reward_references_are_reported() -> void:
	var registry := _build([_dungeon(&"dungeon.a", WORLD_A, [] as Array[StringName],
		[] as Array[StringName], &"reward.missing", &"reward.also_missing")])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "regular_reward_id 'reward.missing' is not listed"), "%s" % registry.errors)
	assert_true(_has_error(registry, "first_clear_reward_id 'reward.also_missing' is not listed"), "%s" % registry.errors)


func test_a_world_owned_by_two_dungeons_is_reported() -> void:
	## The travel gate resolves a world to exactly one dungeon, so a shared world would
	## silently disable the second dungeon's gate (ADR-014).
	var registry := _build([
		_dungeon(&"dungeon.a", WORLD_A),
		_dungeon(&"dungeon.b", WORLD_A),
	])
	assert_false(registry.is_valid(), "a shared world invalidates the manifest")
	assert_true(_has_error(registry, "is already owned by dungeon 'dungeon.a'"), "%s" % registry.errors)
	assert_eq(
		registry.find_dungeon_for_world(WORLD_A).dungeon_id, &"dungeon.a", "the first owner wins"
	)


func test_an_unreachable_dungeon_is_reported() -> void:
	var registry := _build([
		_dungeon(&"dungeon.a", WORLD_A),
		_dungeon(&"dungeon.orphan", WORLD_B, [&"dungeon.a"] as Array[StringName]),
	])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "cannot be unlocked"), "%s" % registry.errors)


func test_a_bucket_without_a_start_dungeon_is_reported() -> void:
	var registry := _build([_dungeon(&"dungeon.a", WORLD_A, [&"dungeon.b"] as Array[StringName])])
	assert_false(registry.is_valid(), "invalid")
	assert_true(_has_error(registry, "no start dungeon"), "%s" % registry.errors)
