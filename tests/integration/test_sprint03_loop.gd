extends "res://tests/test_case.gd"

## Sprint 03 end-to-end loop (ADR-012/013/014) on the real bootstrap scene:
## hub board -> dungeon 01 (locked dungeon 02 refused) -> objective completion ->
## story reward + unlock -> return -> dungeon 02 enterable -> re-enter dungeon 01 with
## reset enemies/loot and no second story reward -> save -> fresh Main restores progress.
##
## The save slot is a temporary user:// path; the real slot is never touched.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_sprint03_loop.json"
const DUNGEON_01 := &"dungeon.01"
const DUNGEON_02 := &"dungeon.02"
const WORLD_01 := &"world.dungeon.proto01"
const WORLD_02 := &"world.dungeon.proto02"
const STORY_ITEM := &"item.rusty_dagger"

var _main: Main = null


func setup() -> void:
	_delete_save_files()


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- fixture ------------------------------------------------------------------

func _instantiate_main() -> Main:
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	if scene == null:
		fail("main scene failed to load")
		return null
	_main = scene.instantiate() as Main
	_main.save_path = TEST_SAVE_PATH
	add_to_tree(_main)
	return _main


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


func _panel() -> DungeonPanel:
	return _main.hud.dungeon_panel if _main != null and _main.hud != null else null


func _player() -> PlayerController:
	return _main.router.current_player()


func _world() -> WorldHost:
	return _main.router.current_world()


func _enemy(objective_id: StringName) -> EnemyBrain:
	for node in _walk(_world()):
		if node is EnemyBrain and (node as EnemyBrain).objective_id == objective_id:
			return node as EnemyBrain
	return null


func _place_player_near(target: Node3D, distance: float, pitch: float = 0.0) -> void:
	var player := _player()
	if player == null or target == null:
		return
	# The player stands on the +Z side of the target and must look back at it: with
	# Godot's -Z forward, yaw = atan2(offset.x, offset.z). A negative pitch aims the
	# interaction ray down at low props (pickups and chests sit below eye height).
	var offset := Vector3(0, 0, distance)
	player.global_position = target.global_position + offset
	player.rotation.y = atan2(offset.x, offset.z)
	player.velocity = Vector3.ZERO
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = pitch


func _press_attack() -> void:
	var event := InputEventAction.new()
	event.action = &"attack_primary"
	event.pressed = true
	_player()._unhandled_input(event)


func _kill_objective_enemy(objective_id: StringName) -> bool:
	var enemy := _enemy(objective_id)
	if enemy == null:
		fail("objective enemy '%s' not found" % objective_id)
		return false
	var health := HealthComponent.find_on(enemy)
	if health == null:
		fail("objective enemy has no HealthComponent")
		return false
	for _swing in 8:
		if not health.is_alive():
			break
		_place_player_near(enemy, 1.4)
		await wait_physics_frames(3)
		_press_attack()
		await wait_physics_frames(45)
	return not health.is_alive()


func _travel(dungeon_id: StringName) -> StringName:
	var panel := _panel()
	if panel == null:
		fail("no dungeon panel")
		return &""
	return panel.select(dungeon_id)


# --- tests --------------------------------------------------------------------

func test_a_new_game_has_one_unlocked_dungeon_and_the_board_says_so() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)

	assert_true(main.registry.is_valid(), "content is valid: %s" % main.registry.errors)
	assert_eq(main.session.progress.is_unlocked(DUNGEON_01), true, "dungeon 01 starts unlocked")
	assert_false(main.session.progress.is_unlocked(DUNGEON_02), "dungeon 02 starts locked")
	assert_eq(main.registry.start_dungeon_ids(), [DUNGEON_01] as Array[StringName], "one start dungeon")

	var panel := _panel()
	assert_not_null(panel, "the HUD owns the dungeon panel")
	if panel == null:
		return
	var rows := panel.rows()
	assert_eq(rows.size(), 2, "two dungeons are listed")
	var by_id := {}
	for row: Dictionary in rows:
		by_id[row["dungeon_id"]] = row
	assert_eq(by_id[DUNGEON_01]["state"], &"unlocked", "dungeon 01 is enterable")
	assert_eq(by_id[DUNGEON_02]["state"], &"locked", "dungeon 02 is locked")
	assert_true(str(by_id[DUNGEON_02]["reason"]).length() > 0, "and the lock explains itself")


func test_a_locked_dungeon_cannot_be_entered_from_the_board() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var code := _travel(DUNGEON_02)
	assert_eq(code, DungeonService.CODE_LOCKED, "the board refuses a locked dungeon")
	assert_eq(main.router.current_world_id(), &"world.hub", "and the player stays in the hub")
	assert_false(main.session.dungeons.is_run_active(), "no run was created")


func test_the_full_progression_loop() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	var progress := session.progress

	# --- 1. enter dungeon 01 through the board --------------------------------
	assert_eq(_travel(DUNGEON_01), WorldRouter.CODE_TRAVEL_STARTED, "the board starts the run")
	await wait_physics_frames(10)
	assert_eq(main.router.current_world_id(), WORLD_01, "we are in dungeon 01")
	assert_eq(_players(), 1, "exactly one player rig")
	assert_eq(_worlds(), 1, "exactly one world")
	var run := session.dungeons.current_run()
	assert_not_null(run, "a run is active")
	if run == null:
		return
	assert_eq(run.dungeon_id, DUNGEON_01, "the run belongs to dungeon 01")
	assert_eq(run.status, DungeonRunState.Status.ACTIVE, "and it is active")
	var first_run_id := run.run_id

	# --- 2. the objective enemy completes the dungeon -------------------------
	var gold_before := session.state.gold
	assert_true(await _kill_objective_enemy(&"objective.dungeon01.enemy_a"), "the boss died")
	await wait_physics_frames(5)
	assert_true(progress.is_completed(DUNGEON_01), "the dungeon is completed")
	assert_true(progress.is_unlocked(DUNGEON_02), "dungeon 02 is unlocked by the first clear")
	assert_true(progress.was_first_clear_claimed(DUNGEON_01), "the story claim is recorded")
	assert_eq(
		session.state.gold, gold_before + 15, "regular (5) + story (10) gold were granted"
	)
	assert_eq(session.state.inventory.count_of(STORY_ITEM), 1, "the story item was granted once")
	assert_true(run.is_completed(), "the run is completed")

	# --- 3. the drop still spawns and can be collected ------------------------
	var gold_after_completion := session.state.gold
	var pickups: Array[PickupInteractable] = []
	for node in _walk(_world()):
		if node is PickupInteractable:
			pickups.append(node as PickupInteractable)
	assert_eq(pickups.size(), 1, "the defeated boss left one drop")
	if pickups.size() == 1:
		_place_player_near(pickups[0], 1.2, -0.6)
		await wait_physics_frames(3)
		var controller := InteractionController.find_on(_player())
		assert_eq(controller.current_focus(), pickups[0], "the drop is focused")
		var picked := controller.try_interact()
		assert_true(picked.succeeded(), "the drop is collected: %s" % picked)
		assert_eq(session.state.gold, gold_after_completion + 3, "the drop paid 3 gold")

	# --- 4. return to the hub -------------------------------------------------
	var hub_code := main.router.request_travel(&"world.hub", &"spawn.hub.dungeon_portal")
	assert_eq(hub_code, WorldRouter.CODE_TRAVEL_STARTED, "the return portal works")
	await wait_physics_frames(10)
	assert_eq(main.router.current_world_id(), &"world.hub", "back in the hub")
	assert_false(session.dungeons.is_run_active(), "the run ended with the world")
	assert_eq(_players(), 1, "still one rig")

	# --- 5. dungeon 02 is now enterable ---------------------------------------
	var panel := _panel()
	assert_eq(panel.select(DUNGEON_02), WorldRouter.CODE_TRAVEL_STARTED, "dungeon 02 is enterable")
	await wait_physics_frames(10)
	assert_eq(main.router.current_world_id(), WORLD_02, "we are in dungeon 02")
	var run02 := session.dungeons.current_run()
	assert_not_null(run02, "dungeon 02 has its own run")
	if run02 != null:
		assert_eq(run02.dungeon_id, DUNGEON_02, "with the right dungeon id")
		assert_ne(run02.run_id, first_run_id, "and a fresh run id")

	# --- 6. re-enter dungeon 01: reset enemies, no second story reward --------
	var gold_before_rerun := session.state.gold
	var salves_before := session.state.inventory.count_of(&"item.minor_salve")
	assert_eq(
		main.router.request_travel(WORLD_01, &"spawn.dungeon.entry"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 01 can be re-entered"
	)
	await wait_physics_frames(10)
	var rerun := session.dungeons.current_run()
	assert_not_null(rerun, "a new run started")
	if rerun == null:
		return
	assert_ne(rerun.run_id, first_run_id, "with a fresh id")
	assert_eq(rerun.defeated_enemy_ids().size(), 0, "the new run knows no defeats")

	var boss := _enemy(&"objective.dungeon01.enemy_a")
	assert_not_null(boss, "the boss is back (enemies reset)")
	var chest: ChestInteractable = null
	for node in _walk(_world()):
		if node is ChestInteractable:
			chest = node as ChestInteractable
	assert_not_null(chest, "the chest is back")
	if chest != null:
		_place_player_near(chest, 1.2, -0.6)
		await wait_physics_frames(3)
		var opened := InteractionController.find_on(_player()).try_interact()
		assert_true(opened.succeeded(), "the chest can be looted again: %s" % opened)
		assert_eq(
			session.state.inventory.count_of(&"item.minor_salve"), salves_before + 1,
			"ordinary loot repeats per run"
		)

	if boss != null:
		assert_true(await _kill_objective_enemy(&"objective.dungeon01.enemy_a"), "the boss died again")
		await wait_physics_frames(5)
	assert_eq(
		session.state.inventory.count_of(STORY_ITEM), 1, "the story item was NOT granted twice"
	)
	assert_true(progress.was_first_clear_claimed(DUNGEON_01), "the claim stays recorded")
	assert_eq(
		session.state.claimed_reward_keys.size(), 1, "no extra persistent keys accumulate"
	)
	assert_true(session.state.gold > gold_before_rerun, "ordinary rewards were earned again")

	# --- 7. save in the hub, then reload with a fresh Main --------------------
	main.router.request_travel(&"world.hub", &"spawn.hub.dungeon_portal")
	await wait_physics_frames(10)
	var gold_before_save := session.state.gold
	var save_result := session.save_now()
	assert_true(save_result.ok(), "the shrine save path works: %s" % save_result.message)

	var expected_gold := gold_before_save
	var expected_salves := session.state.inventory.count_of(&"item.minor_salve")
	var expected_claims := session.state.claimed_reward_keys.size()
	_main = null
	await wait_process_frames(2)

	var reloaded := _instantiate_main()
	if reloaded == null:
		return
	await wait_physics_frames(20)
	assert_true(reloaded.boot_result.ok(), "the save loads: %s" % reloaded.boot_result.message)
	assert_eq(reloaded.session.state.gold, expected_gold, "gold survives the relaunch")
	assert_eq(
		reloaded.session.state.inventory.count_of(STORY_ITEM), 1, "the story item survives once"
	)
	assert_eq(
		reloaded.session.state.inventory.count_of(&"item.minor_salve"), expected_salves,
		"the ordinary items survive"
	)
	assert_eq(reloaded.session.state.claimed_reward_keys.size(), expected_claims, "claims survive")
	assert_true(reloaded.session.progress.is_completed(DUNGEON_01), "the completion survives")
	assert_true(reloaded.session.progress.is_unlocked(DUNGEON_02), "the unlock survives")
	assert_true(
		reloaded.session.progress.was_first_clear_claimed(DUNGEON_01), "the story claim survives"
	)
	assert_eq(reloaded.session.dungeons.claim_pending_first_clear_rewards(), 0, "nothing to re-grant")
	assert_eq(_players(), 1, "exactly one rig after the relaunch")
	assert_eq(_worlds(), 1, "exactly one world after the relaunch")
	assert_false(reloaded.session.dungeons.is_run_active(), "no run survived the restart")
