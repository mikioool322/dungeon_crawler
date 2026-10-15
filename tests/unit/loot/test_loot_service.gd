extends "res://tests/test_case.gd"

## AC-22 — loot idempotency per ledger and grant key, atomic rejection (ADR-009,
## ADR-013).
## Pure domain logic: no SceneTree.
##
## Two ledgers (ADR-013):
## - run scope (`SCOPE_RUN`, the default): one claim per dungeon run in the *transient*
##   ledger opened by `begin_run(run_id)` and cleared by `end_run()`; a run-scoped grant
##   without an active run is `invalid` and mutates nothing, and an optional `run_id`
##   that is not the current run is `stale_run`.
## - story scope (`SCOPE_STORY`): one claim per save in the *persistent*
##   `PlayerSessionState.claimed_reward_keys`; a new run never resets it.
##
## The loot service resolves items through a real `ContentRegistry` built from a
## small in-test manifest, so the registry lookup path is exercised as shipped.

const WORLD_ID := &"world.dungeon.proto01"
const SOURCE_ID := &"enemy.a"
const GRANT_KEY := &"world.dungeon.proto01/enemy.a"
const CHEST_KEY := &"world.dungeon.proto01/chest.a"
const ITEM_ID := &"item.minor_salve"

## Run the fixture opens, so run-scoped grants have a ledger (ADR-013).
const RUN_ID := 1

## A run id that is never the current one while the fixture's run is open.
const STALE_RUN_ID := 99


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
	_loot.begin_run(RUN_ID)
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


func _gold_grant(
	gold: int = 3,
	key: StringName = GRANT_KEY,
	scope: StringName = LootGrant.SCOPE_RUN,
	run_id: int = 0
) -> LootGrant:
	var grant := LootGrant.new()
	grant.grant_key = key
	grant.reward_id = &"reward.grunt_drop"
	grant.gold = gold
	grant.scope = scope
	grant.run_id = run_id
	return grant


func _item_grant(
	count: int = 1,
	gold: int = 0,
	key: StringName = GRANT_KEY,
	item_id: StringName = ITEM_ID,
	scope: StringName = LootGrant.SCOPE_RUN
) -> LootGrant:
	var grant := LootGrant.new()
	grant.grant_key = key
	grant.reward_id = &"reward.chest.proto01"
	grant.item_id = item_id
	grant.item_count = count
	grant.gold = gold
	grant.scope = scope
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
	assert_eq(grant.scope, LootGrant.SCOPE_RUN, "scene rewards default to the run scope")
	assert_false(grant.is_story_scope(), "and are not story rewards")
	assert_true(grant.is_valid(), "the copied grant is usable")

	var story := LootGrant.from_reward(GRANT_KEY, reward, LootGrant.SCOPE_STORY)
	assert_not_null(story, "an explicit story scope produces a grant too")
	if story != null:
		assert_eq(story.scope, LootGrant.SCOPE_STORY, "the scope is copied")
		assert_true(story.is_story_scope(), "and selects the persistent ledger")

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


# --- run scope: granted ---------------------------------------------------------

func test_gold_only_grant_adds_gold_and_reports_granted() -> void:
	var grant := _gold_grant(3)
	assert_eq(grant.scope, LootGrant.SCOPE_RUN, "the fixture grant is run-scoped by default")
	var code := _loot.grant(grant)
	assert_eq(code, LootService.CODE_GRANTED, "a fresh run-scoped grant succeeds")
	assert_eq(_state.gold, 3, "the gold landed on the session")
	assert_true(_loot.is_claimed_in_run(GRANT_KEY), "the key is consumed in the run ledger")
	assert_false(_loot.is_claimed(GRANT_KEY), "and not in the persistent (story) ledger")
	assert_true(_state.claimed_reward_keys.is_empty(), "the save file gains no run claim")
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
	assert_true(_loot.is_claimed_in_run(GRANT_KEY), "the key is consumed in the run ledger")
	assert_true(_state.claimed_reward_keys.is_empty(), "the persistent ledger stays empty")
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
	assert_true(_loot.is_claimed_in_run(GRANT_KEY), "the first source is claimed in the run")
	assert_true(_loot.is_claimed_in_run(CHEST_KEY), "the second source too")
	assert_true(_state.claimed_reward_keys.is_empty(), "no run claim reaches the persistent ledger")


# --- run scope: duplicate -------------------------------------------------------

func test_a_second_identical_grant_in_the_same_run_is_a_duplicate() -> void:
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "the first grant succeeds")
	var code := _loot.grant(_gold_grant(3))
	assert_eq(code, LootService.CODE_DUPLICATE, "the second identical grant is a duplicate")
	assert_eq(_state.gold, 3, "gold is not awarded twice")
	assert_eq(_granted_count, 1, "and no second signal is emitted")
	assert_eq(_state.claimed_reward_keys.size(), 0, "still no persistent key")


# --- run scope: repeatable per run ----------------------------------------------

func test_a_new_run_grants_the_same_key_again() -> void:
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "run 1 earns the key")
	assert_eq(
		_loot.grant(_gold_grant(3)),
		LootService.CODE_DUPLICATE,
		"a second claim inside run 1 is a duplicate"
	)
	assert_eq(_loot.current_run_id(), RUN_ID, "the service is on run 1")

	_loot.begin_run(RUN_ID + 1)
	assert_eq(_loot.current_run_id(), RUN_ID + 1, "the service moved to run 2")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "a new run starts with an empty ledger")
	var code := _loot.grant(_gold_grant(3))
	assert_eq(code, LootService.CODE_GRANTED, "the same key is earnable again in the new run")
	assert_eq(_state.gold, 6, "and pays again")
	assert_eq(_granted_count, 2, "one signal per run")
	assert_true(_state.claimed_reward_keys.is_empty(), "still nothing in the save file")


func test_end_run_discards_the_run_ledger() -> void:
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "the run earns the key")
	assert_true(_loot.is_claimed_in_run(GRANT_KEY), "the run ledger holds it")

	_loot.end_run()
	assert_eq(_loot.current_run_id(), 0, "no run is active")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "leaving the world discards the run ledger")
	assert_eq(_state.gold, 3, "the earned gold stays")


func test_a_run_scoped_grant_without_an_active_run_is_invalid() -> void:
	_loot.end_run()
	var code := _loot.grant(_gold_grant(3))
	assert_eq(code, LootService.CODE_INVALID, "a repeatable reward without a run is invalid")
	assert_eq(_state.gold, 0, "and mutates nothing (gold)")
	assert_true(_state.inventory.is_empty(), "and nothing (bag)")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "and claims nothing in the run ledger")
	assert_true(_state.claimed_reward_keys.is_empty(), "and nothing in the persistent ledger")
	assert_eq(_granted_count, 0, "no signal")

	# The key was not consumed: the next run can still grant it.
	_loot.begin_run(RUN_ID)
	assert_eq(_loot.grant(_gold_grant(3)), LootService.CODE_GRANTED, "the next run still grants the key")
	assert_eq(_state.gold, 3, "exactly once")


func test_a_grant_from_a_stale_run_is_refused() -> void:
	assert_eq(
		_loot.grant(_gold_grant(3, GRANT_KEY, LootGrant.SCOPE_RUN, STALE_RUN_ID)),
		LootService.CODE_STALE_RUN,
		"a grant stamped with a run that is not current is stale_run"
	)
	assert_eq(_state.gold, 0, "and mutates nothing")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "and consumes no key")
	assert_eq(_granted_count, 0, "no signal")

	assert_eq(
		_loot.grant(_gold_grant(3, GRANT_KEY, LootGrant.SCOPE_RUN, RUN_ID)),
		LootService.CODE_GRANTED,
		"a grant stamped with the current run applies"
	)
	assert_eq(_state.gold, 3, "the gold landed")

	_loot.begin_run(RUN_ID + 1)
	assert_eq(
		_loot.grant(_gold_grant(3, GRANT_KEY, LootGrant.SCOPE_RUN, RUN_ID)),
		LootService.CODE_STALE_RUN,
		"the previous run's grant is refused once a new run is current"
	)
	assert_eq(_state.gold, 3, "and still nothing changes")
	assert_eq(_granted_count, 1, "and no extra signal")


# --- story scope ----------------------------------------------------------------

func test_a_story_grant_is_once_per_save_and_needs_no_run() -> void:
	_loot.end_run()  # story rewards are not run-bound (ADR-013)
	var grant := _item_grant(
		2, 7, &"dungeon.01/reward.story.dungeon01", ITEM_ID, LootGrant.SCOPE_STORY
	)
	assert_eq(_loot.grant(grant), LootService.CODE_GRANTED, "a story grant works without an active run")
	assert_eq(_state.inventory.count_of(ITEM_ID), 2, "the story item landed")
	assert_eq(_state.gold, 7, "and the gold")
	assert_true(_state.is_claimed(grant.grant_key), "the story key is recorded in the persistent ledger")
	assert_false(_loot.is_claimed_in_run(grant.grant_key), "and not in the transient run ledger")
	assert_eq(_state.claimed_reward_keys.size(), 1, "exactly one persistent key")
	assert_eq(_granted_count, 1, "one signal")

	var code := _loot.grant(grant)
	assert_eq(code, LootService.CODE_DUPLICATE, "a second story grant is a duplicate")
	assert_eq(_state.gold, 7, "gold is never awarded twice")
	assert_eq(_state.inventory.count_of(ITEM_ID), 2, "the item is never awarded twice")
	assert_eq(_granted_count, 1, "and no second signal")

	# A fresh service over the same state reads the same persistent ledger (load path).
	var fresh := LootService.new()
	fresh.setup(_state, _registry)
	assert_true(fresh.is_claimed(grant.grant_key), "the claim survives a fresh service (the load path)")
	assert_eq(fresh.grant(grant), LootService.CODE_DUPLICATE, "and blocks the grant again")

	# A new run never resets a story claim.
	fresh.begin_run(RUN_ID + 5)
	assert_eq(fresh.grant(grant), LootService.CODE_DUPLICATE, "a new run does not re-grant a story reward")
	assert_eq(_state.claimed_reward_keys.size(), 1, "still exactly one persistent key")


func test_a_story_key_restored_from_a_save_is_a_duplicate() -> void:
	var key := &"dungeon.01/reward.story.dungeon01"
	_state.claim(key)  # the save path restored this claim
	assert_true(_loot.is_claimed(key), "is_claimed reads the persistent (save) ledger")
	assert_eq(
		_loot.grant(_gold_grant(3, key, LootGrant.SCOPE_STORY)),
		LootService.CODE_DUPLICATE,
		"a restored story key is a duplicate"
	)
	assert_eq(_state.gold, 0, "and grants nothing")
	assert_false(_loot.is_claimed_in_run(key), "a restored story key is not a run claim")
	assert_false(_loot.is_claimed(CHEST_KEY), "an unclaimed key stays false")


# --- cross-ledger ---------------------------------------------------------------

func test_a_persistent_key_does_not_block_a_run_grant() -> void:
	var key := &"dungeon.01/reward.shared"
	_state.claim(key)  # a story claim restored from a save
	assert_true(_loot.is_claimed(key), "the persistent ledger holds the key")

	assert_eq(
		_loot.grant(_gold_grant(3, key)),
		LootService.CODE_GRANTED,
		"a run-scoped grant with the same key still applies"
	)
	assert_eq(_state.gold, 3, "and pays")
	assert_true(_loot.is_claimed_in_run(key), "the run ledger now holds the key")
	assert_eq(
		_loot.grant(_gold_grant(3, key)),
		LootService.CODE_DUPLICATE,
		"and the run still blocks a second claim"
	)
	assert_eq(
		_loot.grant(_gold_grant(3, key, LootGrant.SCOPE_STORY)),
		LootService.CODE_DUPLICATE,
		"while the persistent ledger still blocks the story scope"
	)
	assert_eq(_state.gold, 3, "the key was awarded exactly once in total")


func test_a_run_claim_does_not_block_a_story_grant() -> void:
	var key := &"dungeon.01/reward.shared"
	assert_eq(_loot.grant(_gold_grant(3, key)), LootService.CODE_GRANTED, "the run claims the key")
	assert_true(_loot.is_claimed_in_run(key), "the run ledger holds the key")
	assert_false(_state.is_claimed(key), "the persistent ledger is untouched")

	assert_eq(
		_loot.grant(_gold_grant(4, key, LootGrant.SCOPE_STORY)),
		LootService.CODE_GRANTED,
		"a story grant with the same key still applies"
	)
	assert_eq(_state.gold, 7, "both awards landed")
	assert_true(_state.is_claimed(key), "the persistent ledger now holds it")
	assert_eq(
		_loot.grant(_gold_grant(4, key, LootGrant.SCOPE_STORY)),
		LootService.CODE_DUPLICATE,
		"and the story claim is one-time"
	)
	assert_eq(_state.gold, 7, "never awarded twice")


# --- unknown item ---------------------------------------------------------------

func test_unknown_item_is_rejected_without_mutation() -> void:
	var code := _loot.grant(_item_grant(1, 100, GRANT_KEY, &"item.does_not_exist"))
	assert_eq(code, LootService.CODE_UNKNOWN_ITEM, "an id the registry does not know is unknown_item")
	assert_eq(_state.gold, 0, "no gold from a rejected item+gold grant")
	assert_true(_state.inventory.is_empty(), "no item either")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "and the run ledger consumes no key")
	assert_true(_state.claimed_reward_keys.is_empty(), "and the persistent ledger stays empty")
	assert_eq(_granted_count, 0, "no signal")

	# The content is fixed (or the id corrected); the same key must still work.
	var items: Array[ItemDefinition] = [_item()]
	_loot.setup(_state, _registry_with(items))
	assert_eq(
		_loot.grant(_item_grant(1)), LootService.CODE_GRANTED, "a resolvable item can still grant the key"
	)
	assert_true(_loot.is_claimed_in_run(GRANT_KEY), "the retried key is claimed in the run")


# --- invalid --------------------------------------------------------------------

func test_malformed_grants_are_invalid_and_consume_no_key() -> void:
	var malformed: Array[LootGrant] = [
		_gold_grant(3, &""),                          # empty key
		_gold_grant(-1),                              # negative gold
		_gold_grant(0),                               # awards nothing
		_gold_grant(3, GRANT_KEY, &"banana"),         # unknown scope
		_gold_grant(3, GRANT_KEY, LootGrant.SCOPE_RUN, -1),  # negative run id
		_item_grant(0),                               # item id without a count
		_item_grant(-1),                              # negative item count
		_item_grant(1, -5),                           # item plus negative gold
		LootGrant.new(),                              # untouched defaults
	]
	for grant in malformed:
		assert_eq(
			_loot.grant(grant), LootService.CODE_INVALID, "malformed grant rejected: %s" % grant
		)
	assert_eq(_state.gold, 0, "nothing was applied")
	assert_true(_state.inventory.is_empty(), "no item was applied")
	assert_false(_loot.is_claimed_in_run(GRANT_KEY), "the run ledger survives every rejection")
	assert_false(_loot.is_claimed(GRANT_KEY), "and the persistent ledger too")
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
	assert_true(_state.claimed_reward_keys.is_empty(), "persistent claimed keys unchanged")

	# Unknown item with a valid key and gold: also all-or-nothing.
	code = _loot.grant(_item_grant(1, 50, CHEST_KEY, &"item.does_not_exist"))
	assert_eq(code, LootService.CODE_UNKNOWN_ITEM, "an unresolvable item rejects the whole grant")
	assert_eq(_state.gold, 0, "gold still unchanged")
	assert_true(_state.inventory.is_empty(), "bag still unchanged")
	assert_false(_loot.is_claimed_in_run(CHEST_KEY), "and the run ledger is still free")
	assert_eq(_granted_count, 0, "no signal")


func test_a_null_grant_is_invalid() -> void:
	assert_eq(_loot.grant(null), LootService.CODE_INVALID, "a null grant cannot award anything")
	assert_eq(_state.gold, 0, "gold unchanged")
	assert_true(_state.inventory.is_empty(), "bag unchanged")


# --- service readiness ----------------------------------------------------------

func test_grant_without_a_bound_state_is_invalid() -> void:
	var service := LootService.new()
	assert_false(service.is_claimed(GRANT_KEY), "an unbound service claims nothing")
	assert_false(service.is_claimed_in_run(GRANT_KEY), "and has no run claims")
	assert_eq(service.grant(_gold_grant(3)), LootService.CODE_INVALID, "and cannot grant")
	assert_eq(_state.gold, 0, "the other session is untouched")


func test_gold_only_grants_work_without_a_registry_lookup() -> void:
	var service := LootService.new()
	service.setup(_state, null)
	service.begin_run(RUN_ID)
	assert_eq(service.grant(_gold_grant(3)), LootService.CODE_GRANTED, "gold needs no registry")
	assert_eq(
		service.grant(_item_grant(1, 0, CHEST_KEY)),
		LootService.CODE_UNKNOWN_ITEM,
		"an item grant without a registry is unknown_item"
	)
	assert_false(service.is_claimed_in_run(CHEST_KEY), "and consumes no key")
	assert_eq(_state.gold, 3, "the successful gold grant is unaffected")
