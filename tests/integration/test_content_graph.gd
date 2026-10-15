extends "res://tests/test_case.gd"

## AC-24/AC-29 — the shipped content graph is valid and frozen: every id resolves,
## every portal destination exists, spawn ids are unique per world, the loot sources
## are authored exactly once, and the Sprint 03 dungeon graph is complete (one start
## dungeon, one unlock, resolvable worlds/entry spawns/objectives/rewards) (ADR-009,
## ADR-011, ADR-012).

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"

var _instances: Array[Node] = []


func teardown() -> void:
	_instances.clear()


func _registry() -> ContentRegistry:
	var manifest := load(MANIFEST_PATH) as ContentManifest
	if manifest == null:
		fail("the shipped manifest failed to load")
		return ContentRegistry.build(null)
	return ContentRegistry.build(manifest)


func _world_instance(definition: WorldDefinition) -> WorldHost:
	var instance := definition.scene.instantiate()
	_instances.append(instance)
	add_to_tree(instance)
	return instance as WorldHost


func test_the_shipped_manifest_is_valid() -> void:
	var registry := _registry()
	assert_true(registry.is_valid(), "no authoring problems: %s" % registry.errors)
	assert_eq(registry.errors.size(), 0, "the error list is empty")
	assert_eq(registry.all_worlds().size(), 3, "three worlds ship in Sprint 03")
	assert_eq(registry.all_dungeons().size(), 2, "two dungeons ship in Sprint 03")


func test_the_shipped_dungeon_graph_has_one_start_and_one_unlock() -> void:
	var registry := _registry()
	var start_dungeons := registry.start_dungeons()
	assert_eq(start_dungeons.size(), 1, "exactly one dungeon is available at the start")
	if start_dungeons.size() == 1:
		assert_eq(start_dungeons[0].dungeon_id, &"dungeon.01", "dungeon.01 is the start dungeon")

	var first := registry.find_dungeon(&"dungeon.01")
	var second := registry.find_dungeon(&"dungeon.02")
	assert_not_null(first, "dungeon.01 exists")
	assert_not_null(second, "dungeon.02 exists")
	if first == null or second == null:
		return
	assert_true(first.is_start_dungeon(), "dungeon.01 needs no earlier completion")
	assert_false(second.is_start_dungeon(), "dungeon.02 is not a start dungeon")
	assert_eq(
		second.prerequisites,
		[&"dungeon.01"] as Array[StringName],
		"dungeon.02 requires dungeon.01"
	)
	assert_eq(
		first.first_clear_unlocks,
		[&"dungeon.02"] as Array[StringName],
		"dungeon.01's first clear unlocks dungeon.02"
	)
	assert_true(first.repeatable, "dungeon.01 is repeatable (ADR-012)")
	assert_true(second.repeatable, "dungeon.02 is repeatable (ADR-012)")


func test_every_dungeon_points_at_a_loadable_world_and_entry_spawn() -> void:
	var registry := _registry()
	for dungeon in registry.all_dungeons():
		var world := registry.find_world(dungeon.world_id)
		assert_not_null(
			world,
			"dungeon '%s' world '%s' is listed in the manifest" % [dungeon.dungeon_id, dungeon.world_id]
		)
		if world == null or world.scene == null:
			continue
		var instance := _world_instance(world)
		assert_not_null(
			instance, "dungeon '%s' world scene instantiates as a WorldHost" % dungeon.dungeon_id
		)
		if instance == null:
			continue
		assert_not_null(
			instance.resolve_spawn(dungeon.entry_spawn_id),
			"dungeon '%s' entry spawn '%s' exists in '%s'" % [
				dungeon.dungeon_id, dungeon.entry_spawn_id, world.id
			]
		)


func test_every_completion_objective_matches_an_enemy_placement() -> void:
	var registry := _registry()
	for dungeon in registry.all_dungeons():
		assert_ne(
			dungeon.completion_objective,
			&"",
			"dungeon '%s' declares a completion objective" % dungeon.dungeon_id
		)
		var world := registry.find_world(dungeon.world_id)
		if world == null or world.scene == null:
			continue
		var instance := _world_instance(world)
		if instance == null:
			continue
		var matching := 0
		for node in instance.find_children("*", "CharacterBody3D", true, false):
			if not (node is EnemyBrain):
				continue
			var enemy := node as EnemyBrain
			if enemy.objective_id == &"":
				continue
			assert_eq(
				enemy.objective_id,
				dungeon.completion_objective,
				"enemy '%s' in '%s' reports the dungeon's objective id" % [enemy.name, world.id]
			)
			matching += 1
		assert_true(
			matching >= 1,
			"dungeon '%s' has an enemy placement reporting '%s' in '%s'" % [
				dungeon.dungeon_id, dungeon.completion_objective, world.id
			]
		)


func test_every_dungeon_reward_reference_resolves() -> void:
	var registry := _registry()
	for dungeon in registry.all_dungeons():
		assert_ne(
			dungeon.regular_reward_id,
			&"",
			"dungeon '%s' declares a regular reward" % dungeon.dungeon_id
		)
		assert_ne(
			dungeon.first_clear_reward_id,
			&"",
			"dungeon '%s' declares a first-clear reward" % dungeon.dungeon_id
		)
		var regular := registry.find_reward(dungeon.regular_reward_id)
		assert_not_null(
			regular,
			"dungeon '%s' regular reward '%s' is listed" % [
				dungeon.dungeon_id, dungeon.regular_reward_id
			]
		)
		if regular != null:
			assert_true(regular.is_valid(), "the regular reward '%s' is valid data" % regular.id)
		var first_clear := registry.find_reward(dungeon.first_clear_reward_id)
		assert_not_null(
			first_clear,
			"dungeon '%s' first-clear reward '%s' is listed" % [
				dungeon.dungeon_id, dungeon.first_clear_reward_id
			]
		)
		if first_clear != null:
			assert_true(
				first_clear.is_valid(), "the first-clear reward '%s' is valid data" % first_clear.id
			)


func test_shipped_items_and_rewards_match_the_frozen_numbers() -> void:
	var registry := _registry()
	var dagger := registry.find_item(&"item.rusty_dagger")
	assert_not_null(dagger, "the dagger exists")
	if dagger != null:
		assert_false(dagger.stackable, "the dagger does not stack")
		assert_eq(dagger.max_stack, 1, "a unique item holds one per entry")
		assert_true(dagger.is_valid(), "and is valid data")
	var salve := registry.find_item(&"item.minor_salve")
	assert_not_null(salve, "the salve exists")
	if salve != null:
		assert_true(salve.stackable, "the salve stacks")
		assert_eq(salve.max_stack, 5, "five per stack")

	var grunt_drop := registry.find_reward(&"reward.grunt_drop")
	assert_not_null(grunt_drop, "the enemy drop exists")
	if grunt_drop != null:
		assert_eq(grunt_drop.gold, 3, "gold-only drop")
		assert_null(grunt_drop.item, "no item in the enemy drop")
	var chest_reward := registry.find_reward(&"reward.chest.proto01")
	assert_not_null(chest_reward, "the chest reward exists")
	if chest_reward != null:
		assert_eq(chest_reward.gold, 5, "chest gold")
		assert_eq(chest_reward.item_count, 1, "one item")
		if chest_reward.item != null:
			assert_eq(chest_reward.item.id, &"item.minor_salve", "the chest holds a salve")


func test_every_enemy_reward_is_a_known_reward() -> void:
	var registry := _registry()
	var grunt := registry.find_enemy(&"enemy.grunt")
	assert_not_null(grunt, "the grunt archetype exists")
	if grunt == null:
		return
	assert_not_null(grunt.reward, "the grunt carries a reward")
	if grunt.reward != null:
		assert_not_null(
			registry.find_reward(grunt.reward.id),
			"the reward '%s' is listed in the manifest" % grunt.reward.id
		)


func test_world_definitions_point_at_loadable_scenes() -> void:
	var registry := _registry()
	for definition in registry.all_worlds():
		assert_not_null(definition.scene, "world '%s' has a scene" % definition.id)
		if definition.scene == null:
			continue
		var instance := _world_instance(definition)
		assert_not_null(instance, "world '%s' instantiates as a WorldHost" % definition.id)
		if instance == null:
			continue
		assert_eq(instance.world_id, definition.id, "the scene declares the same world id")
		assert_not_null(
			instance.resolve_spawn(definition.default_spawn_id),
			"world '%s' has its default spawn '%s'" % [definition.id, definition.default_spawn_id]
		)


func test_spawn_ids_are_unique_within_a_world() -> void:
	var registry := _registry()
	for definition in registry.all_worlds():
		var instance := _world_instance(definition)
		if instance == null:
			continue
		var seen: Array[StringName] = []
		for marker in instance.spawn_markers():
			assert_false(
				seen.has(marker.spawn_id),
				"world '%s' repeats the spawn id '%s'" % [definition.id, marker.spawn_id]
			)
			seen.append(marker.spawn_id)


func test_every_portal_target_resolves_to_a_world_and_spawn() -> void:
	var registry := _registry()
	for definition in registry.all_worlds():
		var instance := _world_instance(definition)
		if instance == null:
			continue
		var portals: Array[PortalInteractable] = []
		for node in instance.find_children("*", "Node3D", true, false):
			if node is PortalInteractable:
				portals.append(node as PortalInteractable)
		assert_true(portals.size() >= 1, "world '%s' has at least one portal" % definition.id)
		for portal in portals:
			assert_ne(portal.target_world_id, &"", "a portal in '%s' has no target world" % definition.id)
			assert_ne(portal.target_spawn_id, &"", "a portal in '%s' has no target spawn" % definition.id)
			var target := registry.find_world(portal.target_world_id)
			assert_not_null(
				target,
				"portal target world '%s' is listed in the manifest" % portal.target_world_id
			)
			if target == null or target.scene == null:
				continue
			var target_instance := _world_instance(target)
			if target_instance == null:
				continue
			assert_not_null(
				target_instance.resolve_spawn(portal.target_spawn_id),
				"portal target spawn '%s' exists in '%s'" % [portal.target_spawn_id, target.id]
			)


func test_loot_source_ids_are_authored_and_unique_per_world() -> void:
	var registry := _registry()
	for definition in registry.all_worlds():
		var instance := _world_instance(definition)
		if instance == null:
			continue
		var sources: Array[StringName] = []
		for node in instance.find_children("*", "Node3D", true, false):
			if node is EnemyBrain:
				var enemy := node as EnemyBrain
				if enemy.loot_source_id == &"":
					continue  # an enemy without a drop is allowed
				assert_false(
					sources.has(enemy.loot_source_id),
					"world '%s' repeats the loot source '%s'" % [definition.id, enemy.loot_source_id]
				)
				sources.append(enemy.loot_source_id)
			elif node is ChestInteractable or node is PickupInteractable:
				var source: StringName = node.get("loot_source_id")
				assert_ne(source, &"", "a loot interactable in '%s' has no source id" % definition.id)
				assert_false(
					sources.has(source),
					"world '%s' repeats the loot source '%s'" % [definition.id, source]
				)
				sources.append(source)
		if definition.id == &"world.dungeon.proto01":
			assert_true(sources.size() >= 2, "the dungeon ships both an enemy drop and a chest")
