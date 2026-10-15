extends "res://tests/test_case.gd"

## AC (progress + completion + rewards) - the dungeon policy: unlock gate, one active
## run, objective-driven completion, idempotent first clear and repeatable rewards.

const START := &"dungeon.start"
const NEXT := &"dungeon.next"
const OBJECTIVE := &"objective.boss"
const OTHER_OBJECTIVE := &"objective.regular"
const REGULAR_REWARD := &"reward.regular.test"
const STORY_REWARD := &"reward.story.test"
const ITEM := &"item.test"
const WORLD := &"world.dungeon.test"

var _registry: ContentRegistry = null
var _state: PlayerSessionState = null
var _loot: LootService = null
var _progress: DungeonProgress = null
var _service: DungeonService = null
var _completions: Array = []
var _grants: Array = []


func setup() -> void:
	_registry = _build_registry(true)
	_state = PlayerSessionState.new()
	_loot = LootService.new()
	_loot.setup(_state, _registry)
	_progress = DungeonProgress.new()
	_progress.reset_to_new_game(_registry.start_dungeon_ids())
	_service = DungeonService.new()
	_service.setup(_registry, _progress, _loot)
	_service.dungeon_completed.connect(
		func(dungeon_id: StringName, first_clear: bool, run_id: int) -> void:
			_completions.append({"id": dungeon_id, "first_clear": first_clear, "run": run_id})
	)
	_service.reward_granted.connect(
		func(dungeon_id: StringName, scope: StringName, code: StringName) -> void:
			_grants.append({"id": dungeon_id, "scope": scope, "code": code})
	)
	_completions = []
	_grants = []


# --- fixture -----------------------------------------------------------------

func _build_registry(with_story_reward: bool) -> ContentRegistry:
	var manifest := ContentManifest.new()

	var item := ItemDefinition.new()
	item.id = ITEM
	item.display_name = "Test Item"
	item.stackable = true
	item.max_stack = 5
	var items: Array[ItemDefinition] = [item]
	manifest.items = items

	var regular := RewardDefinition.new()
	regular.id = REGULAR_REWARD
	regular.gold = 5
	var rewards: Array[RewardDefinition] = [regular]
	if with_story_reward:
		var story := RewardDefinition.new()
		story.id = STORY_REWARD
		story.item = item
		story.item_count = 1
		story.gold = 10
		rewards.append(story)
	manifest.rewards = rewards

	var world := WorldDefinition.new()
	world.id = WORLD
	world.display_name = "Test Dungeon World"
	world.scene = PackedScene.new()
	world.default_spawn_id = &"spawn.test"
	var worlds: Array[WorldDefinition] = [world]
	manifest.worlds = worlds

	var start := DungeonDefinition.new()
	start.dungeon_id = START
	start.display_name = "Start Dungeon"
	start.world_id = WORLD
	start.entry_spawn_id = &"spawn.test"
	start.first_clear_unlocks = [NEXT] as Array[StringName]
	start.completion_objective = OBJECTIVE
	start.regular_reward_id = REGULAR_REWARD
	start.first_clear_reward_id = STORY_REWARD

	var next := DungeonDefinition.new()
	next.dungeon_id = NEXT
	next.display_name = "Next Dungeon"
	next.world_id = WORLD
	next.entry_spawn_id = &"spawn.test"
	next.prerequisites = [START] as Array[StringName]
	next.completion_objective = OBJECTIVE

	var dungeons: Array[DungeonDefinition] = [start, next]
	manifest.dungeons = dungeons
	return ContentRegistry.build(manifest)


func _enter_start() -> DungeonRunState:
	var run := _service.start_run(START)
	assert_not_null(run, "the start dungeon can be entered")
	return run


func _complete_objective() -> bool:
	return _service.note_objective(OBJECTIVE)


# --- gate --------------------------------------------------------------------

func test_can_enter_reflects_progress_and_repeatability() -> void:
	assert_eq(_service.can_enter(START), DungeonService.CODE_OK, "a start dungeon is enterable")
	assert_eq(_service.can_enter(NEXT), DungeonService.CODE_LOCKED, "the next dungeon is locked")
	assert_eq(
		_service.can_enter(&"dungeon.unknown"), DungeonService.CODE_UNKNOWN_DUNGEON, "unknown id"
	)


func test_a_locked_dungeon_cannot_start_a_run() -> void:
	assert_null(_service.start_run(NEXT), "a locked dungeon is refused")
	assert_null(_service.current_run(), "and no run was created")


func test_a_non_repeatable_completed_dungeon_is_refused() -> void:
	var manifest := ContentManifest.new()
	var one_shot := DungeonDefinition.new()
	one_shot.dungeon_id = START
	one_shot.display_name = "One Shot"
	one_shot.world_id = WORLD
	one_shot.entry_spawn_id = &"spawn.test"
	one_shot.completion_objective = OBJECTIVE
	one_shot.repeatable = false
	var dungeons: Array[DungeonDefinition] = [one_shot]
	manifest.dungeons = dungeons
	manifest.worlds = _registry.all_worlds()
	var registry := ContentRegistry.build(manifest)
	var progress := DungeonProgress.new()
	progress.reset_to_new_game(registry.start_dungeon_ids())
	var service := DungeonService.new()
	service.setup(registry, progress, _loot)

	assert_eq(service.can_enter(START), DungeonService.CODE_OK, "first entry allowed")
	progress.mark_completed(START)
	assert_eq(
		service.can_enter(START), DungeonService.CODE_ALREADY_COMPLETED, "a completed one-shot is closed"
	)


# --- run lifecycle -----------------------------------------------------------

func test_starting_a_run_opens_the_run_ledger() -> void:
	var run := _enter_start()
	assert_eq(run.run_id, 1, "first run id")
	assert_eq(_loot.current_run_id(), run.run_id, "the loot service follows the run")
	assert_true(_loot.is_claimed_in_run(&"anything") == false, "a fresh ledger is empty")


func test_one_active_run_at_a_time() -> void:
	var first := _enter_start()
	var second := _service.start_run(START)
	assert_not_null(second, "a new run starts")
	assert_ne(second.run_id, first.run_id, "with a new id")
	assert_eq(second.status, DungeonRunState.Status.ACTIVE, "and it is active")
	assert_eq(first.status, DungeonRunState.Status.ABORTED, "the previous run is aborted")
	assert_false(first.is_active(), "the old run cannot mutate")
	assert_false(first.mark_enemy_defeated(&"enemy.a"), "its facts are frozen")


func test_leaving_the_world_aborts_an_unfinished_run() -> void:
	var run := _enter_start()
	_service.leave_world()
	assert_eq(run.status, DungeonRunState.Status.ABORTED, "the run is aborted")
	assert_false(_service.is_run_active(), "nothing is active")
	assert_eq(_loot.current_run_id(), 0, "the run ledger is closed")


func test_a_completed_run_stays_as_a_record_until_the_next_one() -> void:
	var run := _enter_start()
	_complete_objective()
	assert_true(run.is_completed(), "completed")
	_service.leave_world()
	assert_eq(run.status, DungeonRunState.Status.COMPLETED, "a completed run is not aborted")
	var next_run := _service.start_run(START)
	assert_not_null(next_run, "a new run can start")
	assert_ne(next_run.run_id, run.run_id, "with a fresh id")


# --- objectives and completion ------------------------------------------------

func test_an_ordinary_objective_never_completes_the_dungeon() -> void:
	_enter_start()
	assert_false(_service.note_objective(OTHER_OBJECTIVE), "not the required objective")
	assert_eq(_completions.size(), 0, "no completion")
	assert_false(_progress.is_completed(START), "and no progress")


func test_the_required_objective_completes_once() -> void:
	var run := _enter_start()
	assert_true(_complete_objective(), "the required objective completes the dungeon")
	assert_true(run.is_completed(), "the run is completed")
	assert_eq(_completions.size(), 1, "one completion event")
	assert_true(_completions[0]["first_clear"], "it was the first clear")
	assert_eq(_completions[0]["id"], START, "for the right dungeon")
	assert_false(_complete_objective(), "a second report cannot complete again")
	assert_eq(_completions.size(), 1, "and emits nothing")
	assert_true(_progress.is_completed(START), "progress recorded")


func test_completion_without_a_run_is_refused() -> void:
	assert_false(_service.note_objective(OBJECTIVE), "no run, no completion")
	assert_false(_service.complete_run(), "and complete_run refuses")
	assert_eq(_completions.size(), 0, "nothing happened")


func test_complete_run_requires_the_objective() -> void:
	_enter_start()
	assert_false(_service.complete_run(), "the objective is not met yet")
	assert_eq(_completions.size(), 0, "no completion")


# --- rewards -----------------------------------------------------------------

func test_first_clear_grants_both_rewards_and_unlocks_the_next_dungeon() -> void:
	_enter_start()
	_complete_objective()

	assert_eq(_state.gold, 15, "regular (5) + story (10) gold")
	assert_eq(_state.inventory.count_of(ITEM), 1, "the story item landed")
	assert_true(_progress.is_unlocked(NEXT), "the next dungeon is unlocked")
	assert_true(_progress.was_first_clear_claimed(START), "the story claim is recorded")
	assert_true(_state.is_claimed(LootGrant.key_for(START, STORY_REWARD)), "story key persisted")
	assert_false(
		_state.is_claimed(LootGrant.key_for(START, REGULAR_REWARD)),
		"the regular reward key is NOT persisted (ADR-013)"
	)
	var scopes: Array[StringName] = []
	for grant: Dictionary in _grants:
		scopes.append(grant["scope"])
	assert_true(scopes.has(LootGrant.SCOPE_RUN), "a run-scoped grant happened")
	assert_true(scopes.has(LootGrant.SCOPE_STORY), "a story-scoped grant happened")


func test_a_repeat_clear_grants_only_the_regular_reward() -> void:
	_enter_start()
	_complete_objective()
	var gold_after_first := _state.gold

	_enter_start()
	_complete_objective()

	assert_eq(_state.gold, gold_after_first + 5, "only the regular reward again")
	assert_eq(_state.inventory.count_of(ITEM), 1, "no second story item")
	assert_eq(_completions.size(), 2, "two completions")
	assert_false(_completions[1]["first_clear"], "the second is not a first clear")
	assert_eq(_service.can_enter(NEXT), DungeonService.CODE_OK, "the unlock stays")


func test_the_story_reward_cannot_be_granted_twice_across_runs() -> void:
	_enter_start()
	_complete_objective()
	var claims_after_first := _state.claimed_reward_keys.size()

	for _i in 3:
		_enter_start()
		_complete_objective()

	assert_eq(_state.claimed_reward_keys.size(), claims_after_first, "no new persistent claims")
	assert_eq(_state.inventory.count_of(ITEM), 1, "the unique item stays unique")
	assert_eq(_state.gold, 15 + 3 * 5, "only repeatable gold accumulated")


func test_a_failed_story_grant_stays_retryable() -> void:
	# The registry does not know the story reward yet: completion must still record
	# progress and must NOT mark the claim.
	var broken_registry := _build_registry(false)
	var loot := LootService.new()
	loot.setup(_state, broken_registry)
	var progress := DungeonProgress.new()
	progress.reset_to_new_game(broken_registry.start_dungeon_ids())
	var service := DungeonService.new()
	service.setup(broken_registry, progress, loot)

	var run := service.start_run(START)
	assert_not_null(run, "the run starts")
	assert_true(service.note_objective(OBJECTIVE), "completion happens even with broken content")
	assert_true(progress.is_completed(START), "progress recorded")
	assert_false(progress.was_first_clear_claimed(START), "the claim is NOT marked")

	# Content fixed: the retry grants the story reward exactly once.
	loot.setup(_state, _registry)
	var fixed := DungeonService.new()
	fixed.setup(_registry, progress, loot)
	assert_eq(fixed.claim_pending_first_clear_rewards(), 1, "the pending reward is granted")
	assert_true(progress.was_first_clear_claimed(START), "the claim is recorded now")
	assert_eq(fixed.claim_pending_first_clear_rewards(), 0, "a second retry grants nothing")


func test_an_unknown_regular_reward_is_reported_and_does_not_break_completion() -> void:
	var manifest := ContentManifest.new()
	var dungeon := DungeonDefinition.new()
	dungeon.dungeon_id = START
	dungeon.display_name = "Broken Rewards"
	dungeon.world_id = WORLD
	dungeon.entry_spawn_id = &"spawn.test"
	dungeon.completion_objective = OBJECTIVE
	dungeon.regular_reward_id = &"reward.does_not_exist"
	var dungeons: Array[DungeonDefinition] = [dungeon]
	manifest.dungeons = dungeons
	manifest.worlds = _registry.all_worlds()
	var registry := ContentRegistry.build(manifest)
	var progress := DungeonProgress.new()
	progress.reset_to_new_game(registry.start_dungeon_ids())
	var service := DungeonService.new()
	service.setup(registry, progress, _loot)

	service.start_run(START)
	assert_true(service.note_objective(OBJECTIVE), "completion survives a broken reward id")
	assert_true(progress.is_completed(START), "progress is recorded")


func test_dungeon_for_world_resolves_only_dungeon_worlds() -> void:
	var definition := _service.dungeon_for_world(WORLD)
	assert_not_null(definition, "the dungeon world resolves")
	if definition != null:
		assert_eq(definition.dungeon_id, START, "to the right dungeon")
	assert_null(_service.dungeon_for_world(&"world.hub"), "a non-dungeon world resolves to null")
