extends "res://tests/test_case.gd"

## AC-24 — `ContentRegistry.build()` reports authoring problems as data (ADR-011):
## duplicates, empty ids, null entries, wrong kinds, invalid definitions and broken
## cross-references, while every valid id stays resolvable.
##
## All five kinds use the real definition classes (Sprint 01 for attacks/enemies,
## W1a for items/rewards/worlds), so the registry's typed `is` checks are what the
## test exercises.

# --- fixtures -----------------------------------------------------------------

func _item(id: StringName, display_name: String = "Minor Salve") -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = id
	item.display_name = display_name
	item.stackable = true
	item.max_stack = 5
	return item


func _reward(
	id: StringName, item: ItemDefinition = null, item_count: int = 0, gold: int = 0
) -> RewardDefinition:
	var reward := RewardDefinition.new()
	reward.id = id
	reward.item = item
	reward.item_count = item_count
	reward.gold = gold
	return reward


func _world(id: StringName) -> WorldDefinition:
	var world := WorldDefinition.new()
	world.id = id
	world.display_name = String(id)
	world.scene = PackedScene.new()
	world.default_spawn_id = &"spawn.test"
	return world


func _attack(id: StringName) -> AttackDefinition:
	var attack := AttackDefinition.new()
	attack.id = id
	return attack


func _enemy(id: StringName, attack: AttackDefinition) -> EnemyDefinition:
	var enemy := EnemyDefinition.new()
	enemy.id = id
	enemy.attack_definition = attack
	return enemy


func _valid_manifest() -> ContentManifest:
	var attack := _attack(&"attack.grunt")
	var item := _item(&"item.minor_salve")
	var manifest := ContentManifest.new()
	manifest.attacks.append(attack)
	manifest.enemies.append(_enemy(&"enemy.grunt", attack))
	manifest.items.append(item)
	manifest.rewards.append(_reward(&"reward.grunt_drop", item, 1, 3))
	manifest.worlds.append(_world(&"world.hub"))
	return manifest


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


# --- tests --------------------------------------------------------------------

func test_an_empty_manifest_is_valid() -> void:
	var registry := ContentRegistry.build(ContentManifest.new())
	assert_not_null(registry, "build() never returns null")
	assert_true(registry.is_valid(), "an empty manifest has no error: %s" % registry.errors)
	assert_eq(registry.errors.size(), 0, "no errors")
	assert_eq(registry.all_worlds().size(), 0, "no worlds")


func test_a_null_manifest_degrades_without_crashing() -> void:
	var registry := ContentRegistry.build(null)
	assert_not_null(registry, "build(null) still returns a registry")
	assert_false(registry.is_valid(), "a null manifest is an error")
	assert_true(_has_error(registry.errors, "null"), "the error names the problem")
	assert_null(registry.find_world(&"world.hub"), "and every lookup misses")


func test_a_valid_manifest_resolves_every_lookup() -> void:
	var manifest := _valid_manifest()
	var registry := ContentRegistry.build(manifest)
	assert_true(registry.is_valid(), "the fixture manifest is valid: %s" % registry.errors)
	assert_eq(registry.errors.size(), 0, "no errors are reported")

	assert_eq(registry.find_attack(&"attack.grunt"), manifest.attacks[0], "attack lookup")
	assert_eq(registry.find_enemy(&"enemy.grunt"), manifest.enemies[0], "enemy lookup")
	assert_eq(registry.find_item(&"item.minor_salve"), manifest.items[0], "item lookup")
	assert_eq(registry.find_reward(&"reward.grunt_drop"), manifest.rewards[0], "reward lookup")
	assert_eq(registry.find_world(&"world.hub"), manifest.worlds[0], "world lookup")


func test_all_worlds_returns_the_manifest_worlds() -> void:
	var manifest := _valid_manifest()
	var dungeon := _world(&"world.dungeon.proto01")
	manifest.worlds.append(dungeon)
	var registry := ContentRegistry.build(manifest)

	var worlds := registry.all_worlds()
	assert_eq(worlds.size(), 2, "both worlds are returned")
	assert_eq(worlds[0], manifest.worlds[0], "manifest order is preserved")
	assert_eq(worlds[1], dungeon, "the second world is the dungeon")
	assert_eq(registry.find_world(&"world.dungeon.proto01"), dungeon, "and it is resolvable by id")


func test_unknown_ids_return_null() -> void:
	var registry := ContentRegistry.build(_valid_manifest())
	assert_null(registry.find_attack(&"attack.unknown"), "unknown attack")
	assert_null(registry.find_enemy(&"enemy.unknown"), "unknown enemy")
	assert_null(registry.find_item(&"item.unknown"), "unknown item")
	assert_null(registry.find_reward(&"reward.unknown"), "unknown reward")
	assert_null(registry.find_world(&"world.unknown"), "unknown world")
	assert_null(registry.find_item(&""), "the empty id is never resolvable")


func test_duplicate_ids_within_a_kind_are_reported() -> void:
	var manifest := ContentManifest.new()
	manifest.items.append(_item(&"item.duplicated"))
	manifest.items.append(_item(&"item.duplicated"))
	manifest.attacks.append(_attack(&"attack.duplicated"))
	manifest.attacks.append(_attack(&"attack.duplicated"))

	var registry := ContentRegistry.build(manifest)
	assert_false(registry.is_valid(), "duplicates invalidate the registry")
	assert_true(_has_error(registry.errors, "duplicates"), "items: %s" % registry.errors)
	assert_true(
		_has_error(registry.errors, "attacks[1] duplicates"),
		"attacks report the duplicated index: %s" % registry.errors
	)
	assert_eq(registry.find_item(&"item.duplicated"), manifest.items[0], "the first definition wins")
	assert_eq(registry.find_attack(&"attack.duplicated"), manifest.attacks[0], "for attacks too")


func test_empty_ids_and_null_entries_are_reported() -> void:
	var manifest := ContentManifest.new()
	manifest.items.append(_item(&""))
	manifest.items.append(null)
	manifest.attacks.append(null)

	var registry := ContentRegistry.build(manifest)
	assert_false(registry.is_valid(), "empty ids and nulls invalidate the registry")
	assert_true(_has_error(registry.errors, "items[0] has an empty id"), "%s" % registry.errors)
	assert_true(_has_error(registry.errors, "items[1] is null"), "%s" % registry.errors)
	assert_true(_has_error(registry.errors, "attacks[0] is null"), "%s" % registry.errors)
	assert_null(registry.find_item(&""), "the empty id is not indexed")


func test_a_definition_with_a_unique_id_is_indexed_even_when_it_is_invalid() -> void:
	var manifest := _valid_manifest()
	var nameless := _item(&"item.nameless", "")
	manifest.items.append(nameless)

	var registry := ContentRegistry.build(manifest)
	assert_false(registry.is_valid(), "the invalid item invalidates the registry")
	assert_true(
		_has_error(registry.errors, "item 'item.nameless': display_name"),
		"the definition's own message is echoed: %s" % registry.errors
	)
	assert_eq(registry.find_item(&"item.nameless"), nameless, "the id stays resolvable")


func test_the_manifest_buckets_are_typed_to_their_definition_classes() -> void:
	## The typed array is the first line of defence: a wrong-kind resource cannot even be
	## stored, so the registry's own kind guard is only reachable from a hand-edited or
	## future non-manifest source (tested below). Asserting the typing avoids provoking an
	## engine error on purpose.
	var manifest := ContentManifest.new()
	assert_eq(manifest.items.get_typed_script(), ItemDefinition, "items is typed to ItemDefinition")
	assert_eq(manifest.rewards.get_typed_script(), RewardDefinition, "rewards is typed")
	assert_eq(manifest.worlds.get_typed_script(), WorldDefinition, "worlds is typed")
	assert_eq(manifest.attacks.get_typed_script(), AttackDefinition, "attacks is typed")
	assert_eq(manifest.enemies.get_typed_script(), EnemyDefinition, "enemies is typed")


func test_the_registry_reports_a_wrong_kind_entry() -> void:
	## White-box: drives the guard directly, because typed arrays make it unreachable
	## through `ContentManifest`. Defence in depth for a hand-edited manifest.
	var registry := ContentRegistry.new()
	var index: Dictionary = {}
	var misplaced: Array = [_world(&"world.hub"), _item(&"item.minor_salve")]
	registry._collect(ContentRegistry.KIND_ITEM, misplaced, index)

	assert_false(registry.is_valid(), "a misplaced resource invalidates the registry")
	assert_true(
		_has_error(registry.errors, "items[0] is not a valid item definition"),
		"%s" % registry.errors
	)
	assert_eq(index.size(), 1, "only the well-formed entry is indexed")
	assert_null(registry.find_item(&"world.hub"), "the misplaced world is not an item")


func test_a_reward_pointing_at_an_unlisted_item_is_reported() -> void:
	var manifest := ContentManifest.new()
	var dangling_item := _item(&"item.not_listed")
	manifest.rewards.append(_reward(&"reward.dangling", dangling_item, 1, 0))

	var registry := ContentRegistry.build(manifest)
	assert_false(registry.is_valid(), "an unresolved reward item invalidates the registry")
	assert_true(
		_has_error(registry.errors, "reward 'reward.dangling': item 'item.not_listed' is not listed"),
		"%s" % registry.errors
	)


func test_an_enemy_without_its_attack_is_reported() -> void:
	var manifest := ContentManifest.new()
	manifest.enemies.append(_enemy(&"enemy.bare", null))
	var unlisted_attack := _attack(&"attack.not_listed")
	manifest.enemies.append(_enemy(&"enemy.unlisted", unlisted_attack))
	var listed_attack := _attack(&"attack.grunt")
	manifest.attacks.append(listed_attack)
	manifest.enemies.append(_enemy(&"enemy.ok", listed_attack))

	var registry := ContentRegistry.build(manifest)
	assert_false(registry.is_valid(), "a broken enemy attack reference invalidates the registry")
	assert_true(_has_error(registry.errors, "enemy 'enemy.bare': attack_definition is null"), "%s" % registry.errors)
	assert_true(
		_has_error(registry.errors, "enemy 'enemy.unlisted': attack 'attack.not_listed' is not listed"),
		"%s" % registry.errors
	)
	assert_false(_has_error(registry.errors, "enemy 'enemy.ok'"), "the resolvable enemy stays clean")


func test_a_reward_resolves_by_id_across_instances() -> void:
	var manifest := _valid_manifest()
	var same_id_item := _item(&"item.minor_salve", "Another Salve")
	manifest.rewards.append(_reward(&"reward.copy", same_id_item, 1, 2))

	var registry := ContentRegistry.build(manifest)
	assert_true(registry.is_valid(), "a reward referencing the listed id resolves: %s" % registry.errors)
	assert_false(_has_error(registry.errors, "reward 'reward.copy'"), "no cross-reference error")


func test_is_valid_mirrors_errors_for_every_fixture() -> void:
	var manifests: Array[ContentManifest] = [
		ContentManifest.new(),
		_valid_manifest(),
	]
	var duplicates := ContentManifest.new()
	duplicates.items.append(_item(&"item.duplicated"))
	duplicates.items.append(_item(&"item.duplicated"))
	manifests.append(duplicates)
	var with_null := ContentManifest.new()
	with_null.enemies.append(null)
	manifests.append(with_null)
	var broken_reference := ContentManifest.new()
	broken_reference.rewards.append(_reward(&"reward.dangling", _item(&"item.missing"), 1, 0))
	manifests.append(broken_reference)

	for manifest: ContentManifest in manifests:
		var registry := ContentRegistry.build(manifest)
		assert_eq(
			registry.is_valid(),
			registry.errors.is_empty(),
			"is_valid() mirrors errors for %s" % registry
		)
