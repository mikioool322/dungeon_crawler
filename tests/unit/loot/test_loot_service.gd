extends "res://tests/test_case.gd"

## AC-22 — loot idempotency per grant key, atomic rejection (ADR-009).
## Pure domain logic: no SceneTree.
##
## The loot service resolves items through a real `ContentRegistry` built from a
## small in-test manifest, so the registry lookup path is exercised as shipped.

const WORLD_ID := &"world.dungeon.proto01"
const SOURCE_ID := &"enemy.a"
const GRANT_KEY := &"world.dungeon.proto01/enemy.a"
const CHEST_KEY := &"world.dungeon.proto01/chest.a"
const ITEM_ID := &"item.minor_salve"


var _state: PlayerSessionState = null
var _registry: ContentRegistry = null
var _loot: LootService = null
var _granted_count: int = 0
var _last_gold_total: int = -1
var _last_grant: LootGrant = null


func setup() -> void:
	_state = PlayerSessionState.new()
	_registry = _registry_with([_item()])
	_loot = LootService.new()
	_loot.setup(_state, _registry)
	_granted_count = 0
	_last_gold_total = -1
	_last_grant = null
	_loot.reward_granted.connect(_on_reward_granted)


## Builds a registry from a hand-written manifest (ADR-011: explicit content list).
func _registry_with(items: Array[ItemDefinition]) -> ContentRegistry:
	var manifest := ContentManifest.new()
	manifest.items = items
	return ContentRegistry.build(manifest)


func _on_reward_granted(grant: LootGrant, gold_total: int) -> void:
	_granted_count += 1
	_last_grant = grant
	_last_gold_total = gold_total


func _item() -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = ITEM_ID
	item.display_name = "Minor Salve"
	item.description = "A stackable test salve"
	item.kind = ItemDefinition.Kind.CONSUMABLE
	item.stackable = true
	item.max_stack = 5
	return item


func _gold_grant(gold: int = 3, key: StringName = GRANT_KEY) -> LootGrant:
	var grant := LootGrant.new()
	grant.grant_key = key
	grant.reward_id = &"reward.grunt_drop"
	grant.gold = gold
	return grant


func _item_grant(
	count: int = 1,
	gold: int = 0,
	key: StringName = GRANT_KEY,
	item_id: StringName = ITEM_ID
) -> LootGrant:
	var grant := LootGrant.new()
	grant.grant_key = key
	grant.reward_id = &"reward.chest.proto01"
	grant.item_id = item_id
	grant.item_count = count
	grant.gold = gold
	return grant


# --- key and grant construction ------------------------------------------------

func test_key_for_builds_the_documented_key() -> void:
	var key := LootGrant.key_for(WORLD_ID, SOURCE_ID)
	assert_eq(key, GRANT_KEY, "the key is <world_id>/<loot_source_id>")
	assert_eq(key, &"world.dungeon.proto01/enemy.a", "with literal ids")
	assert_eq(typeof(key), TYPE_STRING_NAME, "the key stays a StringName for the session dictionary")
	assert_eq(LootGrant.key_for(&"", SOURCE_ID), &"", "a missing world never yields '/enemy.a'")
	assert_eq(LootGrant.key_for(WORLD_ID, &""), &"", "a missing source never yields 'world/'")
	assert_eq(LootGrant.key_for(&"", &""), &"", "an empty source never yields a usable key")


func test_from_reward_copies_an_item_reward() -> void:
	var reward := RewardDefinition.new()
	reward.id = &"reward.chest.proto01"
	reward.item = _item()
	reward.item_count = 2
	reward.gold = 5

	var grant := LootGrant.from_reward(GRANT_KEY, reward)
	assert_not_null(grant, "a reward produces a grant")
	if grant == null:
		return
	assert_eq(grant.grant_key, GRANT_KEY, "the key is passed through")
	assert_eq(grant.reward_id, &"reward.chest.proto01", "the reward id is informational")
	assert_eq(grant.item_id, ITEM_ID, "the item travels as its stable id")
	assert_eq(grant.item_count, 2, "with its count")
	assert_eq(grant.gold, 5, "and the gold")
	assert_true(grant.is_valid(), "the copied grant is usable")
	assert_null(LootGrant.from_reward(GRANT_KEY, null), "no reward, no grant")


func test_from_reward_copies_a_gold_only_reward() -> void:
	var reward := RewardDefinition.new()
	reward.id = &"reward.grunt_drop"
	reward.gold = 3

	var grant := LootGrant.from_reward(GRANT_KEY, reward)
	assert_not_null(grant, "a gold-only reward produces a grant")
	if grant == null:
		return
	assert_eq(grant.item_id, &"", "no item id")
	assert_eq(grant.item_count, 0, "no item count")
	assert_eq(grant.gold, 3, "gold only")
	assert_true(grant.is_valid(), "a gold-only grant is valid")


func test_a_grant_that_awards_nothing_is_invalid() -> void:
	var grant := LootGrant.new()
	grant.grant_key = GRANT_KEY
	assert_false(grant.is_valid(), "no item and no gold is not a usable grant")


# --- granted --------------------------------------------------------------------

func test_gold_only_grant_adds_gold_and_reports_granted() -> void:
	var grant := _gold_grant(3)
	var code := _loot.grant(grant)
	assert_eq(code, LootService.CODE_GRANTED, "a fresh grant succeeds")
	assert_eq(_state.gold, 3, "the gold landed on the session")
	assert_true(_state.is_claimed(GRANT_KEY), "the key is consumed")
	assert_true(_state.inventory.is_empty(), "a gold-only grant does not touch the bag")
	assert_eq(_granted_count, 1, "reward_granted fired exactly once")
	assert_eq(_last_grant, grant, "and carries the granted object")
	assert_eq(_last_gold_total, 3, "and the new gold total")


func test_item_reward_is_added_through_the_registry_lookup() -> void:
	var code := _loot.grant(_item_grant(1, 5))
	assert_eq(code, LootService.CODE_GRANTED, "an item+gold grant succeeds")
	assert_eq(_state.inventory.count_of(ITEM_ID), 1, "the bag holds the item")
	assert_eq(_state.inventory.stack_count(ITEM_ID), 1, "in one stack")
	assert_eq(_state.inventory.ids(), PackedStringArray([String(ITEM_ID)]), "resolved via find_item")
	assert_eq(_state.gold, 5, "the gold landed too")
	assert_true(_state.is_claimed(GRANT_KEY), "the key is consumed")
	assert_eq(_granted_count, 1, "one signal")


func test_two_grants_fill_two_stacks_through_the_service() -> void:
	assert_eq(_loot.grant(_item_grant(2)), LootService.CODE_GRANTED, "stackable item granted")
	assert_eq(
		_loot.grant(_item_grant(2, 0, CHEST_KEY)),
		LootService.CODE_GRANTED,
		"a different source can grant the same item"
	)
	assert_eq(_state.inventory.count_of(ITEM_ID), 4, "both grants landed")
	assert_eq(_state.inventory.stack_count(ITEM_ID), 1, "and they share a stack of five")
	assert_eq(_state.claimed_reward_keys.size(), 2, "one key per source")


# --- duplicate ------------------------------------------------------------------

func test_a_second_identical_grant_is_a_duplicate() -> void:
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "the first grant succeeds")
	var code := _loot.grant(_gold_grant(3))
	assert_eq(code, LootService.CODE_DUPLICATE, "the second identical grant is a duplicate")
	assert_eq(_state.gold, 3, "gold is not awarded twice")
	assert_eq(_granted_count, 1, "and no second signal is emitted")
	assert_eq(_state.claimed_reward_keys.size(), 1, "still exactly one claimed key")


func test_a_key_claimed_by_the_save_is_a_duplicate() -> void:
	_state.claim(GRANT_KEY)
	assert_true(_loot.is_claimed(GRANT_KEY), "is_claimed reads the session (the save path)")
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_DUPLICATE, "a restored key is a duplicate")
	assert_eq(_state.gold, 0, "and grants nothing")
	assert_false(_loot.is_claimed(CHEST_KEY), "an unclaimed key stays false")


# --- unknown item ---------------------------------------------------------------

func test_unknown_item_is_rejected_without_mutation() -> void:
	var code := _loot.grant(_item_grant(1, 100, GRANT_KEY, &"item.does_not_exist"))
	assert_eq(code, LootService.CODE_UNKNOWN_ITEM, "an id the registry does not know is unknown_item")
	assert_eq(_state.gold, 0, "no gold from a rejected item+gold grant")
	assert_true(_state.inventory.is_empty(), "no item either")
	assert_eq(_state.claimed_reward_keys.size(), 0, "and the key is not consumed")
	assert_eq(_granted_count, 0, "no signal")

	# The content is fixed (or the id corrected); the same key must still work.
	var items: Array[ItemDefinition] = [_item()]
	_loot.setup(_state, _registry_with(items))
	assert_eq(
		_loot.grant(_item_grant(1)), LootService.CODE_GRANTED, "a resolvable item can still grant the key"
	)


# --- invalid --------------------------------------------------------------------

func test_malformed_grants_are_invalid_and_consume_no_key() -> void:
	var malformed: Array[LootGrant] = [
		_gold_grant(3, &""),                      # empty key
		_gold_grant(-1),                          # negative gold
		_gold_grant(0),                           # awards nothing
		_item_grant(0),                           # item id without a count
		_item_grant(-1),                          # negative item count
		_item_grant(1, -5),                       # item plus negative gold
		LootGrant.new(),                          # untouched defaults
	]
	for grant in malformed:
		assert_eq(
			_loot.grant(grant), LootService.CODE_INVALID, "malformed grant rejected: %s" % grant
		)
	assert_eq(_state.gold, 0, "nothing was applied")
	assert_true(_state.inventory.is_empty(), "no item was applied")
	assert_false(_loot.is_claimed(GRANT_KEY), "the key survives every rejection")
	assert_eq(_granted_count, 0, "no signal")

	# The key was not consumed, so a well-formed grant with the same key still applies.
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "the same key still works")
	assert_eq(_state.gold, 3, "and applies exactly once")


func test_a_rejected_grant_never_partially_applies() -> void:
	# Valid item and gold, but an unusable key: the gold must not sneak in.
	var code := _loot.grant(_item_grant(1, 50, &""))
	assert_eq(code, LootService.CODE_INVALID, "an unusable key rejects the whole grant")
	assert_eq(_state.gold, 0, "gold unchanged")
	assert_true(_state.inventory.is_empty(), "bag unchanged")
	assert_eq(_state.claimed_reward_keys.size(), 0, "claimed keys unchanged")

	# Unknown item with a valid key and gold: also all-or-nothing.
	code = _loot.grant(_item_grant(1, 50, CHEST_KEY, &"item.does_not_exist"))
	assert_eq(code, LootService.CODE_UNKNOWN_ITEM, "an unresolvable item rejects the whole grant")
	assert_eq(_state.gold, 0, "gold still unchanged")
	assert_true(_state.inventory.is_empty(), "bag still unchanged")
	assert_false(_loot.is_claimed(CHEST_KEY), "and the key is still free")
	assert_eq(_granted_count, 0, "no signal")


func test_a_null_grant_is_invalid() -> void:
	assert_eq(_loot.grant(null), LootService.CODE_INVALID, "a null grant cannot award anything")
	assert_eq(_state.gold, 0, "gold unchanged")
	assert_true(_state.inventory.is_empty(), "bag unchanged")


# --- service readiness ----------------------------------------------------------

func test_grant_without_a_bound_state_is_invalid() -> void:
	var service := LootService.new()
	assert_false(service.is_claimed(GRANT_KEY), "an unbound service claims nothing")
	assert_eq(service.grant(_gold_grant(3)), LootService.CODE_INVALID, "and cannot grant")
	assert_eq(_state.gold, 0, "the other session is untouched")


func test_gold_only_grants_work_without_a_registry_lookup() -> void:
	var service := LootService.new()
	service.setup(_state, null)
	assert_eq(service.grant(_gold_grant(3)), LootService.CODE_GRANTED, "gold needs no registry")
	assert_eq(
		service.grant(_item_grant(1, 0, CHEST_KEY)),
		LootService.CODE_UNKNOWN_ITEM,
		"an item grant without a registry is unknown_item"
	)
	assert_false(_state.is_claimed(CHEST_KEY), "and consumes no key")
	assert_eq(_state.gold, 3, "the successful gold grant is unaffected")
