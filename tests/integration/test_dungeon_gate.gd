extends "res://tests/test_case.gd"

## S03 — the router travel gate and the dungeon run lifecycle at integration level
## (ADR-012, ADR-014). Fixture: the real bootstrap scene (`world/main.tscn`) with a
## temporary save slot; the real slot is never read or written.
##
## Covered here (no other suite asserts these router-level facts):
## - travelling into a locked dungeon returns `WorldRouter.CODE_BLOCKED`, emits
##   `world_load_failed` and leaves the current world, the active run, the run ledger
##   and the progress untouched;
## - the same travel succeeds after the unlock and starts a run with a fresh id;
## - travelling back to the hub ends the run (`leave_world`) and closes the run ledger;
## - a second entry starts a fresh run with an empty ledger;
## - a second travel while one is in flight returns `CODE_BUSY`.
##
## The `busy` case is driven from a `GameSession.location_changed` handler: that signal
## is emitted *inside* the swap (while `WorldRouter._travelling` is still set), whereas
## `world_loaded` fires only after the single-flight flag has been cleared and would
## therefore start a real second travel. The handler records both the returned code and
## the flag read through `WorldRouter.is_travelling()`.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_dungeon_gate_slot.json"

const DUNGEON_01 := &"dungeon.01"
const DUNGEON_02 := &"dungeon.02"
const WORLD_01 := &"world.dungeon.proto01"
const WORLD_02 := &"world.dungeon.proto02"
const WORLD_HUB := &"world.hub"
const SPAWN_ENTRY := &"spawn.dungeon.entry"
const SPAWN_HUB_PORTAL := &"spawn.hub.dungeon_portal"
const CHEST_A := &"chest.a"
const CHEST_B := &"chest.b"

var _main: Main = null

## Travels observed on the router, in order: {world_id, spawn_id, used_fallback}.
var _loaded: Array[Dictionary] = []

## Refusals observed on the router: {world_id, code}.
var _failed: Array[Dictionary] = []


func setup() -> void:
	_delete_save_files()
	_loaded = []
	_failed = []


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- fixture ------------------------------------------------------------------

## Instantiated before the tree entry, so the boot travel is recorded too.
func _instantiate_main() -> Main:
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	if scene == null:
		fail("main scene failed to load: %s" % MAIN_SCENE_PATH)
		return null
	_main = scene.instantiate() as Main
	if _main == null:
		fail("main scene root is not a Main")
		return null
	_main.save_path = TEST_SAVE_PATH
	_main.router.world_loaded.connect(_on_world_loaded)
	_main.router.world_load_failed.connect(_on_world_load_failed)
	add_to_tree(_main)
	return _main


func _on_world_loaded(world_id: StringName, spawn_id: StringName, used_fallback: bool) -> void:
	_loaded.append({"world_id": world_id, "spawn_id": spawn_id, "used_fallback": used_fallback})


func _on_world_load_failed(world_id: StringName, code: StringName) -> void:
	_failed.append({"world_id": world_id, "code": code})


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _count_nodes(root: Node, type_check: Callable) -> int:
	var count := 0
	for node in _walk(root):
		if type_check.call(node):
			count += 1
	return count


func _players() -> int:
	return _count_nodes(_main, func(node: Node) -> bool: return node is PlayerController)


func _worlds() -> int:
	return _count_nodes(_main, func(node: Node) -> bool: return node is WorldHost)


func _player() -> PlayerController:
	return _main.router.current_player()


func _world() -> WorldHost:
	return _main.router.current_world()


func _chest(world: WorldHost) -> ChestInteractable:
	if world == null:
		return null
	for node in _walk(world):
		if node is ChestInteractable:
			return node as ChestInteractable
	return null


## Stands the rig in front of `target` and drives the real interaction ray (the same
## seam test_sprint03_loop.gd uses for chests and pickups).
func _place_player_near(target: Node3D, distance: float, pitch: float = 0.0) -> void:
	var player := _player()
	if player == null or target == null:
		return
	var offset := Vector3(0, 0, distance)
	player.global_position = target.global_position + offset
	player.rotation.y = atan2(offset.x, offset.z)
	player.velocity = Vector3.ZERO
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = pitch


func _open_chest(world: WorldHost) -> bool:
	var chest := _chest(world)
	if chest == null:
		fail("no chest in '%s'" % (world.world_id if world != null else "<no world>"))
		return false
	_place_player_near(chest, 1.2, -0.6)
	await wait_physics_frames(3)
	var controller := InteractionController.find_on(_player())
	if controller == null:
		fail("the rig has no InteractionController")
		return false
	var result := controller.try_interact()
	return result != null and result.succeeded()


# --- the gate -----------------------------------------------------------------

func test_travel_into_a_locked_dungeon_is_blocked_and_changes_nothing() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	var router := main.router
	assert_eq(_loaded.size(), 1, "the boot travel is the only load so far")
	assert_eq(_failed.size(), 0, "and nothing failed at boot")

	# Live state: inside dungeon 01, with an active run and one recorded run fact.
	assert_eq(
		router.request_travel(WORLD_01, SPAWN_ENTRY),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 01 is enterable"
	)
	await wait_physics_frames(10)
	assert_eq(router.current_world_id(), WORLD_01, "the player is inside dungeon 01")
	var run := session.dungeons.active_run()
	assert_not_null(run, "entering the dungeon started a run")
	if run == null:
		return
	assert_true(await _open_chest(_world()), "a run fact was recorded (the chest was opened)")
	var chest_key := LootGrant.key_for(WORLD_01, CHEST_A)
	assert_true(session.loot.is_claimed_in_run(chest_key), "the run ledger holds the chest claim")

	var world_before := router.current_world()
	var player_before := router.current_player()
	var run_id_before := run.run_id
	var chests_before := run.opened_chest_ids()
	var location_before := session.state.spawn_id

	# --- the refusal ----------------------------------------------------------
	var blocked := router.request_travel(WORLD_02, SPAWN_ENTRY)
	assert_eq(blocked, WorldRouter.CODE_BLOCKED, "a locked dungeon is refused with 'blocked'")
	assert_eq(_failed.size(), 1, "exactly one world_load_failed was emitted")
	if _failed.size() == 1:
		assert_eq(_failed[0]["world_id"], WORLD_02, "for the refused destination")
		assert_eq(_failed[0]["code"], WorldRouter.CODE_BLOCKED, "carrying the blocked code")
	assert_eq(_loaded.size(), 2, "the refusal loaded no world")

	# --- the current world is untouched ---------------------------------------
	assert_eq(router.current_world_id(), WORLD_01, "the current world did not change")
	assert_true(router.current_world() == world_before, "the same world instance is still current")
	assert_true(router.current_player() == player_before, "and the same rig")
	assert_eq(main.world_slot.get_child_count(), 1, "no world was stacked into the slot")
	assert_eq(_worlds(), 1, "exactly one world")
	assert_eq(_players(), 1, "exactly one rig")
	assert_eq(session.state.world_id, WORLD_01, "the session location is untouched")
	assert_eq(session.state.spawn_id, location_before, "including the spawn id")

	# --- the active run is untouched ------------------------------------------
	assert_true(session.dungeons.active_run() == run, "the same run is still active")
	assert_eq(run.status, DungeonRunState.Status.ACTIVE, "and still active")
	assert_eq(run.run_id, run_id_before, "with the same id")
	assert_eq(run.opened_chest_ids(), chests_before, "and the same facts")
	assert_eq(session.loot.current_run_id(), run_id_before, "the run ledger still belongs to that run")
	assert_true(session.loot.is_claimed_in_run(chest_key), "and still holds its claim")

	# --- progress is untouched ------------------------------------------------
	assert_false(session.progress.is_unlocked(DUNGEON_02), "the refused dungeon is still locked")
	assert_eq(
		session.dungeons.can_enter(DUNGEON_02),
		DungeonService.CODE_LOCKED,
		"the session gate still refuses it"
	)
	assert_eq(session.progress.completed_ids(), [] as Array[StringName], "nothing was completed")


func test_the_same_travel_succeeds_after_the_unlock_with_a_fresh_run() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	var router := main.router

	assert_eq(
		router.request_travel(WORLD_01, SPAWN_ENTRY),
		WorldRouter.CODE_TRAVEL_STARTED,
		"the first dungeon is enterable"
	)
	await wait_physics_frames(10)
	var first_run := session.dungeons.active_run()
	assert_not_null(first_run, "the dungeon 01 run is active")
	if first_run == null:
		return
	assert_eq(
		router.request_travel(WORLD_02, SPAWN_ENTRY),
		WorldRouter.CODE_BLOCKED,
		"the second dungeon is still refused"
	)

	# The first clear of dungeon 01 is what unlocks dungeon 02 in the shipped content;
	# the completion path itself is covered by test_dungeon_completion.gd and the loop.
	assert_true(session.progress.unlock(DUNGEON_02), "the unlock is applied (as a first clear would)")
	assert_eq(
		session.dungeons.can_enter(DUNGEON_02), DungeonService.CODE_OK, "the session gate now allows it"
	)

	var code := router.request_travel(WORLD_02, SPAWN_ENTRY)
	assert_eq(code, WorldRouter.CODE_TRAVEL_STARTED, "the same travel now succeeds")
	await wait_physics_frames(10)
	assert_eq(router.current_world_id(), WORLD_02, "the destination world is current")
	assert_eq(_failed.size(), 1, "only the earlier attempt failed")
	assert_eq(_loaded.size(), 3, "boot + two successful travels were loaded")
	if _loaded.size() == 3:
		assert_eq(_loaded[2]["world_id"], WORLD_02, "the last load is dungeon 02")
		assert_eq(_loaded[2]["spawn_id"], SPAWN_ENTRY, "at the definition's entry spawn")
		assert_false(_loaded[2]["used_fallback"], "and it is not a fallback")

	assert_eq(first_run.status, DungeonRunState.Status.ABORTED, "the dungeon 01 run was superseded")
	assert_eq(first_run.abort_reason, &"superseded", "with the documented reason")
	var second_run := session.dungeons.active_run()
	assert_not_null(second_run, "dungeon 02 has an active run")
	if second_run == null:
		return
	assert_eq(second_run.dungeon_id, DUNGEON_02, "for dungeon 02")
	assert_ne(second_run.run_id, first_run.run_id, "with a fresh run id")
	assert_eq(session.loot.current_run_id(), second_run.run_id, "the run ledger follows the new run")
	assert_eq(session.state.world_id, WORLD_02, "the session records the new location")
	assert_eq(_worlds(), 1, "one world after two travels")
	assert_eq(_players(), 1, "one rig after two travels")


# --- leaving and re-entering --------------------------------------------------

func test_leaving_the_hub_ends_the_run_and_a_second_entry_starts_clean() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	var router := main.router

	assert_true(session.progress.unlock(DUNGEON_02), "the test unlocks dungeon 02")
	assert_eq(
		router.request_travel(WORLD_02, SPAWN_ENTRY),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 02 is enterable"
	)
	await wait_physics_frames(10)
	var first := session.dungeons.active_run()
	assert_not_null(first, "dungeon 02 has an active run")
	if first == null:
		return
	assert_true(await _open_chest(_world()), "chest.b was opened during the run")
	var chest_key := LootGrant.key_for(WORLD_02, CHEST_B)
	assert_true(session.loot.is_claimed_in_run(chest_key), "the run ledger holds the claim")
	var gold_before := session.state.gold

	# --- the hub ends the run -------------------------------------------------
	assert_eq(
		router.request_travel(WORLD_HUB, SPAWN_HUB_PORTAL),
		WorldRouter.CODE_TRAVEL_STARTED,
		"the hub is reachable"
	)
	await wait_physics_frames(10)
	assert_eq(router.current_world_id(), WORLD_HUB, "back in the hub")
	assert_false(session.dungeons.is_run_active(), "the hub has no active run")
	var finished := session.dungeons.current_run()
	assert_not_null(finished, "the finished run stays as a record")
	if finished != null:
		assert_eq(finished.run_id, first.run_id, "the same run instance")
		assert_eq(finished.status, DungeonRunState.Status.ABORTED, "an unfinished run is aborted")
		assert_eq(finished.abort_reason, &"left_world", "with the documented reason")
	assert_eq(session.loot.current_run_id(), 0, "the transient run ledger is closed")
	assert_false(session.loot.is_claimed_in_run(chest_key), "and its claims are gone")
	assert_eq(session.state.gold, gold_before, "the reward already earned is kept")

	# --- a second entry: fresh run, empty ledger ------------------------------
	assert_eq(
		router.request_travel(WORLD_02, SPAWN_ENTRY),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 02 can be re-entered"
	)
	await wait_physics_frames(10)
	var second := session.dungeons.active_run()
	assert_not_null(second, "a new run is active")
	if second == null:
		return
	assert_ne(second.run_id, first.run_id, "with a fresh id")
	assert_eq(second.dungeon_id, DUNGEON_02, "for the same dungeon")
	assert_eq(second.opened_chest_ids(), [] as Array[StringName], "the new run knows no opened chests")
	assert_eq(second.defeated_enemy_ids(), [] as Array[StringName], "and no defeats")
	assert_eq(session.loot.current_run_id(), second.run_id, "the ledger belongs to the new run")
	assert_false(
		session.loot.is_claimed_in_run(chest_key), "which starts empty: the chest can be looted again"
	)
	assert_not_null(_chest(_world()), "the chest is back in the world (world content reset)")
	assert_eq(_worlds(), 1, "one world after the re-entry")
	assert_eq(_players(), 1, "one rig after the re-entry")


# --- single flight ------------------------------------------------------------

func test_a_second_travel_while_one_is_in_flight_returns_busy() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var router := main.router
	assert_eq(_loaded.size(), 1, "the boot travel happened before the test")

	var codes: Array[StringName] = []
	var flags: Array[bool] = []
	var handler := func(_world_id: StringName, _spawn_id: StringName) -> void:
		if not codes.is_empty():
			return
		flags.append(router.is_travelling())
		codes.append(router.request_travel(WORLD_01, SPAWN_ENTRY))
	main.session.location_changed.connect(handler)
	var code := router.request_travel(WORLD_01, SPAWN_ENTRY)
	main.session.location_changed.disconnect(handler)

	assert_eq(code, WorldRouter.CODE_TRAVEL_STARTED, "the outer travel completes")
	assert_eq(codes.size(), 1, "the re-entrant request was observed inside the swap")
	if codes.size() == 1:
		assert_true(flags[0], "the single-flight flag is set while the swap is in progress")
		assert_eq(codes[0], WorldRouter.CODE_BUSY, "a travel in flight returns 'busy'")
	assert_eq(_failed.size(), 0, "the refused re-entry is not a load failure")
	assert_eq(_loaded.size(), 2, "only the outer travel loaded a world")

	await wait_physics_frames(10)
	assert_eq(router.current_world_id(), WORLD_01, "the outer travel arrived")
	assert_eq(_worlds(), 1, "one world after the re-entrant refusal")
	assert_eq(_players(), 1, "one rig after the re-entrant refusal")
	assert_true(main.session.dungeons.is_run_active(), "and the run lifecycle ran exactly once")
