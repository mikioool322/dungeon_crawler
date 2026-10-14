extends "res://tests/test_case.gd"

## Sprint 02 content definitions: field defaults, enum values and per-field validation
## for `ItemDefinition`, `RewardDefinition` and `WorldDefinition` (ADR-009, ADR-011).
## Pure domain logic: no SceneTree and no `.tres` on disk.

const ITEM_ID := &"item.test.salve"
const REWARD_ID := &"reward.test.drop"
const WORLD_ID := &"world.test.hub"


func _item(stackable: bool = true, max_stack: int = 5) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = ITEM_ID
	definition.display_name = "Test Salve"
	definition.description = "A stackable test item"
	definition.kind = ItemDefinition.Kind.CONSUMABLE
	definition.stackable = stackable
	definition.max_stack = max_stack
	return definition


func _reward() -> RewardDefinition:
	var reward := RewardDefinition.new()
	reward.id = REWARD_ID
	reward.item = _item()
	reward.item_count = 1
	reward.gold = 3
	return reward


func _world() -> WorldDefinition:
	var world := WorldDefinition.new()
	world.id = WORLD_ID
	world.display_name = "Test Hub"
	world.scene = PackedScene.new()
	world.default_spawn_id = &"spawn.test.start"
	return world


func _errors_mention(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if message.contains(needle):
			return true
	return false


# --- ItemDefinition -------------------------------------------------------------

func test_item_valid_definition_has_no_errors() -> void:
	var item := _item()
	assert_eq(item.validation_errors().size(), 0, "a fully authored item is valid")
	assert_true(item.is_valid(), "is_valid agrees")


func test_item_defaults_match_the_frozen_contract() -> void:
	var item := ItemDefinition.new()
	assert_eq(item.id, &"", "id defaults to empty (the author must supply it)")
	assert_eq(item.display_name, "", "display_name defaults to empty")
	assert_eq(item.description, "", "description defaults to empty")
	assert_eq(item.kind, ItemDefinition.Kind.MISC, "kind defaults to MISC")
	assert_true(item.stackable, "items are stackable by default")
	assert_eq(item.max_stack, 1, "with max_stack 1")
	assert_null(item.icon, "no icon by default (presentation only)")
	assert_eq(
		item.validation_errors().size(),
		3,
		"a fresh item reports id, display_name and the stackable/max_stack mismatch"
	)
	assert_false(item.is_valid(), "and is unusable until authored")


func test_item_kind_enum_values_are_frozen() -> void:
	# .tres files persist the enum as an integer, so the order is content format.
	assert_eq(ItemDefinition.Kind.MISC, 0, "MISC")
	assert_eq(ItemDefinition.Kind.CONSUMABLE, 1, "CONSUMABLE")
	assert_eq(ItemDefinition.Kind.WEAPON, 2, "WEAPON")
	assert_eq(ItemDefinition.Kind.KEY, 3, "KEY")


func test_item_id_and_display_name_are_required() -> void:
	var item := _item()
	item.id = &""
	var errors := item.validation_errors()
	assert_eq(errors.size(), 1, "an empty id is one error")
	assert_true(_errors_mention(errors, "id"), "and it names the id field")

	item = _item()
	item.display_name = "   "
	errors = item.validation_errors()
	assert_eq(errors.size(), 1, "a blank display name is one error")
	assert_true(_errors_mention(errors, "display_name"), "and it names the field")

	item.display_name = ""
	item.id = &""
	assert_eq(item.validation_errors().size(), 2, "one message per broken field")


func test_item_stack_rule_follows_the_stackable_flag() -> void:
	var cases := [
		{"stackable": true, "max_stack": 2, "valid": true},
		{"stackable": true, "max_stack": 99, "valid": true},
		{"stackable": true, "max_stack": 1, "valid": false},
		{"stackable": true, "max_stack": 0, "valid": false},
		{"stackable": false, "max_stack": 1, "valid": true},
		{"stackable": false, "max_stack": 2, "valid": false},
		{"stackable": false, "max_stack": 0, "valid": false},
	]
	for case in cases:
		var item := _item(case["stackable"], case["max_stack"])
		assert_eq(
			item.is_valid(),
			case["valid"],
			"stackable=%s with max_stack=%d" % [case["stackable"], case["max_stack"]]
		)


func test_item_reports_one_message_per_broken_field() -> void:
	var item := _item(true, 1)
	item.id = &""
	item.display_name = ""
	var errors := item.validation_errors()
	assert_eq(errors.size(), 3, "id, display_name and the stack rule: exactly three messages")
	assert_true(_errors_mention(errors, "max_stack"), "and the stack rule is reported")


# --- RewardDefinition -----------------------------------------------------------

func test_reward_gold_only_is_valid() -> void:
	var reward := RewardDefinition.new()
	reward.id = REWARD_ID
	reward.gold = 5
	assert_eq(reward.validation_errors().size(), 0, "a gold-only reward needs no item")
	assert_true(reward.is_valid(), "is_valid agrees")


func test_reward_item_only_is_valid() -> void:
	var reward := RewardDefinition.new()
	reward.id = REWARD_ID
	reward.item = _item()
	reward.item_count = 2
	assert_eq(reward.validation_errors().size(), 0, "an item-only reward needs no gold")
	assert_true(reward.is_valid(), "is_valid agrees")


func test_reward_item_and_gold_is_valid() -> void:
	var reward := _reward()
	assert_eq(reward.validation_errors().size(), 0, "item + gold is the chest path")
	assert_true(reward.is_valid(), "is_valid agrees")


func test_reward_defaults_match_the_frozen_contract() -> void:
	var reward := RewardDefinition.new()
	assert_eq(reward.id, &"", "id defaults to empty")
	assert_null(reward.item, "item defaults to null (gold-only)")
	assert_eq(reward.item_count, 0, "item_count defaults to 0")
	assert_eq(reward.gold, 0, "gold defaults to 0")
	assert_eq(reward.validation_errors().size(), 2, "a fresh reward misses the id and grants nothing")
	assert_false(reward.is_valid(), "and is unusable until authored")


func test_reward_id_is_required() -> void:
	var reward := _reward()
	reward.id = &""
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 1, "an empty id is one error")
	assert_true(_errors_mention(errors, "id"), "and it names the id field")


func test_reward_rejects_negative_gold() -> void:
	var reward := _reward()
	reward.gold = -1
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 1, "negative gold is one error")
	assert_true(_errors_mention(errors, "gold"), "and it names the gold field")


func test_reward_item_count_must_match_the_item_field() -> void:
	var reward := RewardDefinition.new()
	reward.id = REWARD_ID
	reward.gold = 1
	reward.item_count = 3
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 1, "item_count without an item is one error")
	assert_true(_errors_mention(errors, "item_count"), "and it names the field")

	reward.item = _item()
	reward.item_count = 0
	errors = reward.validation_errors()
	assert_eq(errors.size(), 1, "an item without a count is one error")
	assert_true(_errors_mention(errors, "item_count"), "and it names the field")

	reward.item_count = -1
	assert_eq(reward.validation_errors().size(), 1, "a negative count is rejected too")


func test_reward_requires_a_valid_item() -> void:
	var reward := _reward()
	reward.item = ItemDefinition.new()
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 1, "an unauthored item is one error on the reward")
	assert_true(_errors_mention(errors, "item"), "and it names the item field")
	assert_false(reward.is_valid(), "a reward may not reference broken content")


func test_reward_that_grants_nothing_is_rejected() -> void:
	var reward := RewardDefinition.new()
	reward.id = REWARD_ID
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 1, "neither item nor gold is one error")
	assert_true(_errors_mention(errors, "at least"), "and it explains the missing award")
	reward.gold = 1
	assert_true(reward.is_valid(), "adding gold makes the same reward valid")


func test_reward_reports_one_message_per_broken_field() -> void:
	var reward := _reward()
	reward.id = &""
	reward.gold = -5
	reward.item_count = 0
	var errors := reward.validation_errors()
	assert_eq(errors.size(), 3, "id, gold and item_count: exactly three messages")


# --- WorldDefinition ------------------------------------------------------------

func test_world_valid_definition_has_no_errors() -> void:
	var world := _world()
	assert_eq(world.validation_errors().size(), 0, "a fully authored world is valid")
	assert_true(world.is_valid(), "is_valid agrees")


func test_world_defaults_match_the_frozen_contract() -> void:
	var world := WorldDefinition.new()
	assert_eq(world.id, &"", "id defaults to empty")
	assert_eq(world.display_name, "", "display_name defaults to empty")
	assert_null(world.scene, "scene defaults to null")
	assert_eq(world.default_spawn_id, &"", "default_spawn_id defaults to empty")
	assert_eq(world.validation_errors().size(), 3, "a fresh world misses all three required fields")
	assert_false(world.is_valid(), "and is unusable until authored")


func test_world_requires_id_scene_and_default_spawn() -> void:
	var world := _world()
	world.id = &""
	var errors := world.validation_errors()
	assert_eq(errors.size(), 1, "a missing id is one error")
	assert_true(_errors_mention(errors, "id"), "and it names the id field")

	world = _world()
	world.scene = null
	errors = world.validation_errors()
	assert_eq(errors.size(), 1, "a missing scene is one error")
	assert_true(_errors_mention(errors, "scene"), "and it names the scene field")

	world = _world()
	world.default_spawn_id = &""
	errors = world.validation_errors()
	assert_eq(errors.size(), 1, "a missing default spawn is one error")
	assert_true(_errors_mention(errors, "default_spawn_id"), "and it names the field")


func test_world_reports_one_message_per_broken_field() -> void:
	var world := _world()
	world.id = &""
	world.scene = null
	world.default_spawn_id = &""
	assert_eq(world.validation_errors().size(), 3, "three missing fields, three messages")


func test_world_display_name_is_optional() -> void:
	var world := _world()
	world.display_name = ""
	assert_true(world.is_valid(), "display_name is presentation only and may stay empty")


func test_every_definition_is_a_resource() -> void:
	assert_instance_of(ItemDefinition.new(), "Resource")
	assert_instance_of(RewardDefinition.new(), "Resource")
	assert_instance_of(WorldDefinition.new(), "Resource")
