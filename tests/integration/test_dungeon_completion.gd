extends "res://tests/test_case.gd"

## S03 — dungeon completion at *world* level (ADR-014): `WorldHost` reports the death of
## an enemy that carries an `objective_id` to `DungeonService`, which completes the
## dungeon exactly once. An ordinary enemy (empty `objective_id`) never completes it,
## even though its death *is* reported to the run.
##
## Fixture: the real dungeon 01 scene (`world/dungeons/dungeon_proto01.tscn`) instantiated
## by the test and configured with a real session/registry, plus one extra ordinary enemy
## — the real `actors/enemies/enemy.tscn` with `loot_source_id = enemy.extra` and an empty
## `objective_id` — added as a child *before* the world enters the tree, so
## `WorldHost._bind_enemies()` binds it exactly like a scene-placed placement.
## (Reported choice: a test copy of the world, not dungeon 02's `enemy.regular`
## placement, because the objective under test is dungeon 01's.)
##
## Deaths are driven by one lethal `HealthComponent.apply_damage()` instead of real
## swings: the swing/hit path is already covered by test_sprint03_loop.gd, and this file
## is about the objective/completion seam. The duplicate report uses
## `HealthComponent.restore()` to re-arm `died`, so the second report travels the real
## signal chain rather than a test-only shortcut.

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const DUNGEON_01_PATH := "res://world/dungeons/dungeon_proto01.tscn"
const ENEMY_SCENE_PATH := "res://actors/enemies/enemy.tscn"
const TEST_SAVE_PATH := "user://test_dungeon_completion_slot.json"

const DUNGEON_01 := &"dungeon.01"
const DUNGEON_02 := &"dungeon.02"
const OBJECTIVE := &"objective.dungeon01.enemy_a"
const ORDINARY_SOURCE := &"enemy.extra"
const STORY_ITEM := &"item.rusty_dagger"

## Shipped reward values of dungeon 01 (`reward.regular.dungeon01` / `reward.story.dungeon01`).
const REGULAR_GOLD := 5
const STORY_GOLD := 10

var _registry: ContentRegistry = null
var _session: GameSession = null
var _world: WorldHost = null

## One entry per `dungeon_completed` emission: {id, first_clear, run}.
var _completions: Array[Dictionary] = []

## One entry per `reward_granted` emission: {id, scope, code}.
var _grants: Array[Dictionary] = []


func setup() -> void:
	_delete_save_files()
	_registry = ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)
	_session = GameSession.new()
	var save_manager := SaveManager.new()
	save_manager.setup(TEST_SAVE_PATH)
	_session.setup(_registry, save_manager)
	_session.new_game()
	_completions = []
	_grants = []
	_session.dungeons.dungeon_completed.connect(_on_completed)
	_session.dungeons.reward_granted.connect(_on_reward_granted)


func teardown() -> void:
	_world = null
	_session = null
	_registry = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _on_completed(dungeon_id: StringName, first_clear: bool, run_id: int) -> void:
	_completions.append({"id": dungeon_id, "first_clear": first_clear, "run": run_id})


func _on_reward_granted(dungeon_id: StringName, scope: StringName, code: StringName) -> void:
	_grants.append({"id": dungeon_id, "scope": scope, "code": code})


# --- fixture ------------------------------------------------------------------

## Instantiates the real dungeon 01 scene with the extra ordinary enemy already inside.
func _build_world() -> WorldHost:
	var packed := load(DUNGEON_01_PATH) as PackedScene
	if packed == null:
		fail("dungeon 01 scene failed to load: %s" % DUNGEON_01_PATH)
		return null
	var world := packed.instantiate() as WorldHost
	if world == null:
		fail("dungeon 01 scene root is not a WorldHost")
		return null
	var extra := _build_ordinary_enemy()
	if extra == null:
		world.free()
		return null
	# Added off-tree, so `WorldHost._ready()` binds it like any scene placement.
	world.add_child(extra)
	world.configure(
		_session,
		_registry,
		Callable(self, "_noop_travel"),
		Callable(self, "_noop_save"),
		&"spawn.dungeon.entry"
	)
	add_to_tree(world)
	_world = world
	return world


## The real enemy scene, placed as an ordinary (non-objective) enemy.
func _build_ordinary_enemy() -> EnemyBrain:
	var packed := load(ENEMY_SCENE_PATH) as PackedScene
	if packed == null:
		fail("enemy scene failed to load: %s" % ENEMY_SCENE_PATH)
		return null
	var enemy := packed.instantiate() as EnemyBrain
	if enemy == null:
		fail("the enemy scene root is not an EnemyBrain")
		return null
	enemy.name = "EnemyOrdinary"
	enemy.loot_source_id = ORDINARY_SOURCE
	enemy.objective_id = &""
	enemy.position = Vector3(4.0, 0.2, -4.0)
	return enemy


## The world layer never travels or saves in this fixture; both callables are inert.
func _noop_travel(_world_id: StringName, _spawn_id: StringName) -> StringName:
	return WorldRouter.CODE_INVALID_WORLD


func _noop_save() -> SaveResult:
	var result := SaveResult.new()
	result.status = SaveResult.Status.IO_ERROR
	result.message = "no save provider in this fixture"
	return result


# --- helpers ------------------------------------------------------------------

func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _enemy_with_objective(objective_id: StringName) -> EnemyBrain:
	for node in _walk(_world):
		if node is EnemyBrain and (node as EnemyBrain).objective_id == objective_id:
			return node as EnemyBrain
	return null


func _enemy_with_source(source: StringName) -> EnemyBrain:
	for node in _walk(_world):
		if node is EnemyBrain and (node as EnemyBrain).loot_source_id == source:
			return node as EnemyBrain
	return null


## One lethal hit through the real damage entry point.
func _kill(enemy: EnemyBrain) -> bool:
	if enemy == null:
		fail("cannot kill a null enemy")
		return false
	var health := HealthComponent.find_on(enemy)
	if health == null:
		fail("enemy '%s' has no HealthComponent" % enemy.name)
		return false
	health.apply_damage(
		DamageRequest.new(&"attack.test.lethal", &"test", 1000.0, enemy.global_position, Vector3.UP)
	)
	return not health.is_alive()


func _world_count_in_tree() -> int:
	var count := 0
	if runner_root == null:
		return 0
	for node in _walk(runner_root):
		if node is WorldHost:
			count += 1
	return count


# --- an ordinary enemy --------------------------------------------------------

func test_an_ordinary_enemy_death_does_not_complete_the_dungeon() -> void:
	var world := _build_world()
	if world == null:
		return
	await wait_physics_frames(5)
	var run := _session.dungeons.start_run(DUNGEON_01)
	assert_not_null(run, "the dungeon starts a run")
	if run == null:
		return
	assert_eq(run.status, DungeonRunState.Status.ACTIVE, "the run is active")

	var ordinary := _enemy_with_source(ORDINARY_SOURCE)
	assert_not_null(ordinary, "the extra ordinary enemy is in the world")
	if ordinary == null:
		return
	assert_eq(ordinary.objective_id, &"", "and it carries no objective id")
	assert_not_null(_enemy_with_objective(OBJECTIVE), "the scene's objective enemy is still there")

	var gold_before := _session.state.gold
	assert_true(_kill(ordinary), "the ordinary enemy died")
	assert_true(
		run.defeated_enemy_ids().has(ORDINARY_SOURCE),
		"its death WAS reported to the run: %s" % [run.defeated_enemy_ids()]
	)
	assert_eq(_completions.size(), 0, "an ordinary death never completes the dungeon")
	assert_eq(_grants.size(), 0, "and grants no completion reward")
	assert_false(_session.progress.is_completed(DUNGEON_01), "no completion was recorded")
	assert_eq(run.status, DungeonRunState.Status.ACTIVE, "the run stays active")
	assert_eq(_session.state.gold, gold_before, "and no gold was paid")
	assert_eq(
		_session.dungeons.can_enter(DUNGEON_02), DungeonService.CODE_LOCKED, "dungeon 02 stays locked"
	)


# --- the objective enemy ------------------------------------------------------

func test_the_objective_enemy_death_completes_once_even_when_reported_twice() -> void:
	var world := _build_world()
	if world == null:
		return
	await wait_physics_frames(5)
	var run := _session.dungeons.start_run(DUNGEON_01)
	assert_not_null(run, "the dungeon starts a run")
	if run == null:
		return

	var objective := _enemy_with_objective(OBJECTIVE)
	assert_not_null(objective, "the objective enemy is in the world")
	if objective == null:
		return
	var gold_before := _session.state.gold

	# --- the first, real death ------------------------------------------------
	assert_true(_kill(objective), "the objective enemy died")
	assert_true(run.is_completed(), "the run is completed")
	assert_eq(_completions.size(), 1, "exactly one dungeon_completed was emitted")
	if _completions.size() == 1:
		assert_eq(_completions[0]["id"], DUNGEON_01, "for dungeon 01")
		assert_true(_completions[0]["first_clear"], "with first_clear = true")
		assert_eq(_completions[0]["run"], run.run_id, "carrying the run id")
	assert_true(_session.progress.is_completed(DUNGEON_01), "the completion is recorded")
	assert_true(_session.progress.is_unlocked(DUNGEON_02), "the first clear unlocked dungeon 02")
	assert_true(_session.progress.was_first_clear_claimed(DUNGEON_01), "the story claim is recorded")
	assert_eq(
		_session.state.gold,
		gold_before + REGULAR_GOLD + STORY_GOLD,
		"the regular and the story gold were granted once"
	)
	assert_eq(_session.state.inventory.count_of(STORY_ITEM), 1, "the story item was granted once")
	assert_eq(_session.state.claimed_reward_keys.size(), 1, "exactly one persistent story key")
	assert_eq(_grants.size(), 2, "one run-scoped and one story-scoped grant were reported")
	var scopes: Array[StringName] = []
	for grant: Dictionary in _grants:
		scopes.append(grant["scope"])
	assert_true(scopes.has(LootGrant.SCOPE_RUN), "the regular grant is run-scoped")
	assert_true(scopes.has(LootGrant.SCOPE_STORY), "the story grant is story-scoped")

	# --- the same death reported a second time -------------------------------
	# `restore()` re-arms `died`, so the second lethal hit travels the real
	# `HealthComponent.died -> WorldHost -> DungeonService` chain once more.
	var gold_after_first := _session.state.gold
	var health := HealthComponent.find_on(objective)
	if health == null:
		fail("the objective enemy has no HealthComponent")
		return
	health.restore(100.0)
	assert_true(_kill(objective), "the enemy died a second time (duplicate report)")
	assert_eq(_completions.size(), 1, "the duplicate report completes nothing")
	assert_eq(run.status, DungeonRunState.Status.COMPLETED, "the run stays completed")
	assert_eq(_session.state.gold, gold_after_first, "no second reward was paid")
	assert_eq(_session.state.inventory.count_of(STORY_ITEM), 1, "the story item stays unique")
	assert_eq(_session.state.claimed_reward_keys.size(), 1, "and the story claim stays single")
	assert_eq(_session.progress.completed_ids().size(), 1, "the completion is recorded once")
	assert_eq(_grants.size(), 2, "no additional grant was reported")
	assert_false(_session.dungeons.is_run_active(), "and the completed run is no longer mutable")


# --- a second run -------------------------------------------------------------

func test_a_second_run_completes_again_with_first_clear_false() -> void:
	var world := _build_world()
	if world == null:
		return
	await wait_physics_frames(5)
	var first_run := _session.dungeons.start_run(DUNGEON_01)
	assert_not_null(first_run, "the first run starts")
	if first_run == null:
		return
	var first_objective := _enemy_with_objective(OBJECTIVE)
	if first_objective == null:
		fail("the objective enemy is missing in the first run")
		return
	assert_true(_kill(first_objective), "the objective died in the first run")
	assert_eq(_completions.size(), 1, "the first clear was reported")
	var first_run_id := first_run.run_id

	# --- a fresh world for the second run (enemies reset per run) -------------
	world.queue_free()
	await wait_process_frames(2)
	assert_eq(_world_count_in_tree(), 0, "the first world was freed")
	var second_world := _build_world()
	if second_world == null:
		return
	await wait_physics_frames(5)
	assert_eq(_world_count_in_tree(), 1, "exactly one world exists for the second run")

	var second_run := _session.dungeons.start_run(DUNGEON_01)
	assert_not_null(second_run, "dungeon 01 is repeatable")
	if second_run == null:
		return
	assert_eq(second_run.status, DungeonRunState.Status.ACTIVE, "the second run is active")
	assert_ne(second_run.run_id, first_run_id, "with a fresh run id")
	assert_eq(second_run.defeated_enemy_ids(), [] as Array[StringName], "and no memory of the first run")

	var objective := _enemy_with_objective(OBJECTIVE)
	assert_not_null(objective, "the objective enemy is back in the second world")
	if objective == null:
		return
	var gold_before := _session.state.gold
	assert_true(_kill(objective), "the objective died in the second run")

	assert_eq(_completions.size(), 2, "a second completion was emitted")
	if _completions.size() == 2:
		assert_eq(_completions[1]["id"], DUNGEON_01, "for dungeon 01 again")
		assert_false(_completions[1]["first_clear"], "and it is NOT a first clear")
		assert_eq(_completions[1]["run"], second_run.run_id, "carrying the second run id")
	assert_eq(
		_session.state.gold, gold_before + REGULAR_GOLD, "only the regular reward was granted again"
	)
	assert_eq(_session.state.inventory.count_of(STORY_ITEM), 1, "no second story item")
	assert_true(_session.progress.was_first_clear_claimed(DUNGEON_01), "the story claim stays recorded")
	assert_eq(_session.progress.completed_ids().size(), 1, "still exactly one completion recorded")
	assert_eq(_session.state.claimed_reward_keys.size(), 1, "still exactly one persistent key")
	assert_true(_session.progress.is_unlocked(DUNGEON_02), "and the unlock stays")
