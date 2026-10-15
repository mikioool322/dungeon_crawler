extends "res://tests/test_case.gd"

## Unit coverage for the session owner (ADR-007/ADR-009): it is the only writer of
## health and location, it re-emits loot-driven gold changes, and re-running
## `setup()` must not double-connect its listeners.

const TEST_SAVE_PATH := "user://test_game_session_slot.json"

var _session: GameSession = null
var _registry: ContentRegistry = null


func setup() -> void:
	_delete_save_files()
	_registry = _registry_with([_item()])
	_session = GameSession.new()
	_session.setup(_registry, _save_manager())


func teardown() -> void:
	_session = null
	_registry = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _save_manager() -> SaveManager:
	var manager := SaveManager.new()
	manager.setup(TEST_SAVE_PATH)
	return manager


func _item() -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = &"item.test_salve"
	item.display_name = "Test Salve"
	item.stackable = true
	item.max_stack = 5
	return item


func _registry_with(items: Array[ItemDefinition]) -> ContentRegistry:
	var manifest := ContentManifest.new()
	manifest.items = items
	# One world is enough for the reward-key filter: a key is known when its world
	# part resolves (ADR-009).
	var world := WorldDefinition.new()
	world.id = &"world.test"
	world.display_name = "Test World"
	world.scene = PackedScene.new()
	world.default_spawn_id = &"spawn.test"
	var worlds: Array[WorldDefinition] = [world]
	manifest.worlds = worlds
	return ContentRegistry.build(manifest)


func _reward() -> RewardDefinition:
	var reward := RewardDefinition.new()
	reward.id = &"reward.test"
	reward.item = _registry.find_item(&"item.test_salve")
	reward.item_count = 1
	reward.gold = 4
	return reward


func test_new_game_starts_in_the_default_world_with_full_health() -> void:
	_session.new_game()
	assert_eq(_session.state.world_id, GameSession.DEFAULT_WORLD_ID, "starts in the hub")
	assert_eq(_session.state.spawn_id, &"", "no explicit spawn yet")
	assert_eq(_session.state.health, GameSession.DEFAULT_MAX_HEALTH, "full health")
	assert_eq(_session.state.gold, 0, "no gold")
	assert_true(_session.state.inventory.is_empty(), "empty bag")


func test_loot_grant_emits_gold_and_inventory_changes() -> void:
	var gold_events: Array[int] = []
	var inventory_events: Array[int] = []
	_session.gold_changed.connect(func(gold: int) -> void: gold_events.append(gold))
	_session.inventory_changed.connect(func() -> void: inventory_events.append(1))

	_session.loot.begin_run(1)  # scene loot is run-scoped since Sprint 03 (ADR-013)
	var key := LootGrant.key_for(&"world.test", &"enemy.a")
	var code := _session.loot.grant(LootGrant.from_reward(key, _reward()))
	assert_eq(code, LootService.CODE_GRANTED, "the grant applies")
	assert_eq(gold_events, [4] as Array[int], "the session reports the new gold exactly once")
	assert_eq(inventory_events.size(), 1, "and the bag change exactly once")
	assert_eq(_session.state.inventory.count_of(&"item.test_salve"), 1, "the item is in the bag")
	assert_true(_session.loot.is_claimed_in_run(key), "the run ledger holds the key")
	assert_true(_session.state.claimed_reward_keys.is_empty(), "the save file gains no run claim")


func test_a_story_grant_is_persisted_and_re_emitted() -> void:
	var gold_events: Array[int] = []
	_session.gold_changed.connect(func(gold: int) -> void: gold_events.append(gold))

	var key := LootGrant.key_for(&"dungeon.test.start", &"reward.story")
	var grant := LootGrant.from_reward(key, _reward(), LootGrant.SCOPE_STORY)
	assert_eq(
		_session.loot.grant(grant),
		LootService.CODE_GRANTED,
		"a story grant applies without an active run"
	)
	assert_eq(_session.state.gold, 4, "the gold landed")
	assert_true(_session.state.is_claimed(key), "the story key is in the persistent ledger")
	assert_eq(gold_events, [4] as Array[int], "and the session re-emitted the gold change")
	assert_eq(
		_session.loot.grant(grant),
		LootService.CODE_DUPLICATE,
		"a second story grant is a duplicate"
	)
	assert_eq(gold_events, [4] as Array[int], "and never re-emits")


func test_setup_can_run_twice_without_double_connecting() -> void:
	var inventory_events: Array[int] = []
	_session.inventory_changed.connect(func() -> void: inventory_events.append(1))
	_session.setup(_registry, _save_manager())  # documented as safe to call again

	_session.state.inventory.add(_registry.find_item(&"item.test_salve"), 1)
	assert_eq(inventory_events.size(), 1, "one bag change produces one notification")


func test_restore_full_health_is_the_death_path_write() -> void:
	_session.new_game()
	_session.state.health = 7.0
	_session.restore_full_health()
	assert_eq(_session.state.health, GameSession.DEFAULT_MAX_HEALTH, "the next life starts full")


func test_note_location_updates_state_and_notifies() -> void:
	var locations: Array[String] = []
	_session.location_changed.connect(
		func(world_id: StringName, spawn_id: StringName) -> void:
			locations.append("%s@%s" % [world_id, spawn_id])
	)
	_session.note_location(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	assert_eq(_session.state.world_id, &"world.dungeon.proto01", "world recorded")
	assert_eq(_session.state.spawn_id, &"spawn.dungeon.entry", "spawn recorded")
	assert_eq(locations, ["world.dungeon.proto01@spawn.dungeon.entry"] as Array[String], "notified once")


func test_apply_snapshot_drops_unknown_content_with_warnings() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 42.0
	snapshot.gold = 9
	snapshot.items = [{"id": "item.test_salve", "count": 2}, {"id": "item.ghost", "count": 1}]
	snapshot.world_id = &"world.unknown"
	snapshot.spawn_id = &"spawn.x"
	snapshot.claimed_reward_keys = PackedStringArray(["world.test/enemy.a", "world.ghost/enemy.a"])

	var warnings := _session.apply_snapshot(snapshot)
	assert_eq(_session.state.health, 42.0, "health restored")
	assert_eq(_session.state.gold, 9, "gold restored")
	assert_eq(_session.state.inventory.count_of(&"item.test_salve"), 2, "known item restored")
	assert_null(_registry.find_item(&"item.ghost"), "the unknown item does not exist")
	assert_eq(_session.state.world_id, GameSession.DEFAULT_WORLD_ID, "unknown world falls back")
	assert_true(_session.state.is_claimed(&"world.test/enemy.a"), "known reward key kept")
	assert_false(_session.state.is_claimed(&"world.ghost/enemy.a"), "unknown reward key dropped")
	assert_eq(warnings.size(), 3, "three warnings: item, world, reward key")
