extends "res://tests/test_case.gd"

## S04-QA — Sprint 01-03 dungeon regression *with equipment in play* (ADR-012/ADR-013/
## ADR-014/ADR-016): dungeon 01 -> 02 still unlock, a repeat run still resets ordinary
## loot while the first-clear reward stays one-time, and death still aborts the run
## without touching the equipment or the recomputed stats.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_s04_qa_regression.json"

const DUNGEON_01 := &"dungeon.01"
const DUNGEON_02 := &"dungeon.02"
const WORLD_01 := &"world.dungeon.proto01"
const WORLD_02 := &"world.dungeon.proto02"
const OBJECTIVE_01 := &"objective.dungeon01.enemy_a"
const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const DAGGER := &"item.rusty_dagger"
const SALVE := &"item.minor_salve"

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
	if root == null:
		return found
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _count(root: Node, type_check: Callable) -> int:
	var count := 0
	for node in _walk(root):
		if type_check.call(node):
			count += 1
	return count


func _player() -> PlayerController:
	return _main.router.current_player()


func _enemy(objective_id: StringName) -> EnemyBrain:
	for node in _walk(_main.router.current_world()):
		if node is EnemyBrain and (node as EnemyBrain).objective_id == objective_id:
			return node as EnemyBrain
	return null


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


func _press_attack() -> void:
	var event := InputEventAction.new()
	event.action = &"attack_primary"
	event.pressed = true
	_player()._unhandled_input(event)


func _kill_objective(objective_id: StringName) -> bool:
	var enemy := _enemy(objective_id)
	if enemy == null:
		fail("objective enemy '%s' not found" % objective_id)
		return false
	var health := HealthComponent.find_on(enemy)
	if health == null:
		fail("the objective enemy has no HealthComponent")
		return false
	for _swing in 8:
		if not health.is_alive():
			break
		_place_player_near(enemy, 1.6)
		await wait_physics_frames(3)
		_press_attack()
		await wait_physics_frames(50)
	return not health.is_alive()


func _equip_kit(session: GameSession) -> void:
	session.state.inventory.add(_main.registry.find_item(SWORD), 1)
	session.state.inventory.add(_main.registry.find_item(VEST), 1)
	assert_eq(session.equip_item(SWORD), EquipmentState.CODE_OK, "the sword equips")
	assert_eq(session.equip_item(VEST), EquipmentState.CODE_OK, "the vest equips")
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "attack with the sword"
	)
	assert_almost_eq(session.stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "defense with the vest")


# --- progression and repeat runs ------------------------------------------------

func test_dungeon_01_to_02_and_a_repeat_run_with_equipment() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	_equip_kit(session)

	# --- dungeon 01 with the equipped weapon ----------------------------------
	assert_eq(
		main.router.request_travel(WORLD_01, &"spawn.dungeon.entry"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 01 starts"
	)
	await wait_physics_frames(10)
	assert_eq(main.router.current_world_id(), WORLD_01, "we are in dungeon 01")
	assert_almost_eq(_player().move_speed, 4.0, 0.0001, "the rig speed follows the effective stats")
	assert_eq(
		_player().attack_controller.attack_profile().id, &"attack.player.iron_sword",
		"the rig swings with the equipped weapon"
	)
	assert_true(await _kill_objective(OBJECTIVE_01), "the objective enemy dies to the equipped weapon")
	await wait_physics_frames(5)
	assert_true(session.progress.is_completed(DUNGEON_01), "dungeon 01 is completed")
	assert_true(session.progress.is_unlocked(DUNGEON_02), "dungeon 02 is unlocked")
	assert_true(session.progress.was_first_clear_claimed(DUNGEON_01), "the first-clear claim is recorded")
	assert_eq(session.state.inventory.count_of(DAGGER), 1, "the story dagger was granted once")
	assert_eq(
		session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"the equipment survived the world swap"
	)
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"and the effective stats survived it"
	)

	# --- back to the hub, then dungeon 02 --------------------------------------
	assert_eq(
		main.router.request_travel(&"world.hub", &"spawn.hub.dungeon_portal"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"the return works"
	)
	await wait_physics_frames(10)
	assert_false(session.dungeons.is_run_active(), "the completed run is no longer active")
	assert_eq(
		main.router.request_travel(WORLD_02, &"spawn.dungeon.entry"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 02 is enterable after the first clear"
	)
	await wait_physics_frames(10)
	assert_eq(main.router.current_world_id(), WORLD_02, "we are in dungeon 02")
	var run02 := session.dungeons.current_run()
	assert_not_null(run02, "dungeon 02 has a run")
	if run02 != null:
		assert_eq(run02.dungeon_id, DUNGEON_02, "with the right dungeon id")
	main.router.request_travel(&"world.hub", &"spawn.hub.dungeon_portal")
	await wait_physics_frames(10)

	# --- repeat run of dungeon 01 ----------------------------------------------
	var salves_before := session.state.inventory.count_of(SALVE)
	var gold_before := session.state.gold
	assert_eq(
		main.router.request_travel(WORLD_01, &"spawn.dungeon.entry"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"dungeon 01 can be re-entered"
	)
	await wait_physics_frames(10)
	var rerun := session.dungeons.current_run()
	assert_not_null(rerun, "a new run started")
	if rerun != null:
		assert_eq(rerun.defeated_enemy_ids().size(), 0, "the new run knows no defeats")

	var chest: ChestInteractable = null
	for node in _walk(main.router.current_world()):
		if node is ChestInteractable:
			chest = node as ChestInteractable
	assert_not_null(chest, "the chest is back for the new run")
	if chest != null:
		_place_player_near(chest, 1.2, -0.6)
		await wait_physics_frames(3)
		var opened := InteractionController.find_on(_player()).try_interact()
		assert_true(opened.succeeded(), "the chest can be looted again: %s" % opened)
		assert_eq(
			session.state.inventory.count_of(SALVE), salves_before + 1,
			"ordinary loot resets and repeats per run"
		)

	assert_true(await _kill_objective(OBJECTIVE_01), "the objective enemy dies again")
	await wait_physics_frames(5)
	assert_eq(session.state.inventory.count_of(DAGGER), 1, "the first-clear reward is NOT granted twice")
	assert_true(session.progress.was_first_clear_claimed(DUNGEON_01), "the claim stays recorded")
	assert_true(session.state.gold > gold_before, "ordinary rewards were earned again")
	assert_eq(session.state.claimed_reward_keys.size(), 1, "no extra persistent keys accumulate")
	assert_eq(_count(main, func(node: Node) -> bool: return node is PlayerController), 1, "one rig")
	assert_eq(_count(main, func(node: Node) -> bool: return node is WorldHost), 1, "one world")


# --- death aborts the run -------------------------------------------------------

func test_death_in_a_dungeon_aborts_the_run_and_keeps_equipment() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session
	_equip_kit(session)
	var gold_before := session.state.gold

	assert_eq(
		main.router.request_travel(WORLD_01, &"spawn.dungeon.entry"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"the run starts"
	)
	await wait_physics_frames(10)
	assert_true(session.dungeons.is_run_active(), "a run is active")

	var health := HealthComponent.find_on(_player())
	assert_not_null(health, "the live rig has its HealthComponent")
	if health == null:
		return
	health.apply_damage(
		DamageRequest.new(&"attack.qa.lethal", &"qa", 1000.0, _player().global_position, Vector3.UP)
	)
	await wait_physics_frames(10)

	assert_eq(main.router.current_world_id(), &"world.hub", "death respawned the player in the hub")
	assert_false(session.dungeons.is_run_active(), "the run was aborted by the death")
	var run := session.dungeons.current_run()
	if run != null:
		assert_eq(run.status, DungeonRunState.Status.ABORTED, "and its record reads ABORTED")
	assert_false(session.progress.is_completed(DUNGEON_01), "an aborted run cannot complete the dungeon")
	assert_eq(
		session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"the weapon survived the death"
	)
	assert_eq(
		session.state.equipment.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), VEST,
		"the armour survived the death"
	)
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"the effective attack survived the death"
	)
	assert_almost_eq(
		session.stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001,
		"the effective defense survived the death"
	)
	assert_eq(session.state.inventory.count_of(SWORD), 0, "the equipped sword is still not in the bag")
	assert_eq(session.state.gold, gold_before, "gold is untouched by the death")

	var respawned := _player()
	assert_not_null(respawned, "a fresh rig exists")
	if respawned != null:
		var respawned_health := HealthComponent.find_on(respawned)
		if respawned_health != null:
			assert_almost_eq(respawned_health.current_health, 100.0, 0.0001, "the next life starts full")
			assert_almost_eq(respawned_health.max_health, 100.0, 0.0001, "with the effective maximum")
	assert_eq(_count(main, func(node: Node) -> bool: return node is PlayerController), 1, "one rig")
	assert_eq(_count(main, func(node: Node) -> bool: return node is WorldHost), 1, "one world")
