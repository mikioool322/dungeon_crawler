extends "res://tests/test_case.gd"

## AC-45 — the owner's Sprint 04 loop on the real bootstrap scene: hub → stats → merchant →
## buy → equip (attack rises) → dungeon 01 → kill with the equipped weapon → loot → return →
## sell → equip armour (defense rises) → save → relaunch restores everything, while the
## Sprint 03 dungeon progression keeps working.
##
## The panels are presentation and are covered by their own suites; this loop drives the
## session operations the panels call.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_sprint04_loop.json"
const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const SALVE := &"item.minor_salve"
const DAGGER := &"item.rusty_dagger"
const SWORD_PRICE := 40
const SWORD_BONUS := 15
const VEST_DEFENSE := 5
const BASE_ATTACK := 34.0

var _main: Main = null
var _dialogue_requests: Array[NpcDefinition] = []


func setup() -> void:
	_delete_save_files()


func teardown() -> void:
	_main = null
	_dialogue_requests = []
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
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _player() -> PlayerController:
	return _main.router.current_player()


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


func _kill_objective_enemy() -> bool:
	var enemy: EnemyBrain = null
	for node in _walk(_main.router.current_world()):
		if node is EnemyBrain and (node as EnemyBrain).objective_id != &"":
			enemy = node as EnemyBrain
			break
	if enemy == null:
		fail("no objective enemy found")
		return false
	var health := HealthComponent.find_on(enemy)
	if health == null:
		fail("the objective enemy has no HealthComponent")
		return false
	var swings := 0
	for _i in 8:
		if not health.is_alive():
			break
		_place_player_near(enemy, 1.6)
		await wait_physics_frames(3)
		var event := InputEventAction.new()
		event.action = &"attack_primary"
		event.pressed = true
		_player()._unhandled_input(event)
		swings += 1
		await wait_physics_frames(50)
	return not health.is_alive()


func test_the_full_sprint04_loop() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session

	# --- 1. stats start at their base values ----------------------------------
	assert_true(session.stats.is_ready(), "the shipped player definition readies the stats")
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), BASE_ATTACK, 0.0001, "base attack"
	)
	assert_almost_eq(session.stats.effective(CharacterStats.DEFENSE), 0.0, 0.0001, "base defense")
	assert_almost_eq(session.stats.effective(CharacterStats.MAX_HEALTH), 100.0, 0.0001, "base HP")

	# --- 2. the merchant NPC announces a dialogue -----------------------------
	var hub := main.router.current_world()
	var npc_node: NpcInteractable = null
	for node in _walk(hub):
		if node is NpcInteractable:
			npc_node = node as NpcInteractable
			break
	assert_not_null(npc_node, "the hub holds the merchant NPC")
	if npc_node == null:
		return
	assert_not_null(npc_node.npc, "the NPC carries its definition")
	assert_true(npc_node.npc.has_shop(), "and it offers a shop")
	hub.dialogue_requested.connect(
		func(npc: NpcDefinition) -> void: _dialogue_requests.append(npc)
	)
	_place_player_near(npc_node, 1.5, -0.3)
	await wait_physics_frames(3)
	var controller := InteractionController.find_on(_player())
	assert_eq(controller.current_focus(), npc_node, "the NPC is focused through the real ray")
	var talked := controller.try_interact()
	assert_true(talked.succeeded(), "talking succeeds: %s" % talked)
	assert_eq(_dialogue_requests.size(), 1, "the dialogue was requested exactly once")
	assert_eq(_dialogue_requests[0].id, &"npc.hub.smith", "for the shipped smith")

	# --- 3. the shop: buy the sword -------------------------------------------
	session.trading.bind_merchant(npc_node.npc.merchant)
	session.add_gold(SWORD_PRICE + 10)
	var gold_before := session.state.gold
	assert_eq(
		session.trading.can_buy(SWORD), TradingService.CODE_OK, "the sword is affordable and stocked"
	)
	assert_eq(session.trading.buy(SWORD), TradingService.CODE_OK, "the sword is bought")
	assert_eq(session.state.gold, gold_before - SWORD_PRICE, "gold paid exactly once")
	assert_eq(session.state.inventory.count_of(SWORD), 1, "the sword is in the bag")

	# --- 4. equip it: attack damage rises -------------------------------------
	var definition := main.registry.find_item(SWORD)
	assert_eq(session.equip_item(SWORD), EquipmentState.CODE_OK, "the sword is equipped")
	assert_eq(session.state.inventory.count_of(SWORD), 0, "and left the bag (ownership A)")
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE),
		BASE_ATTACK + SWORD_BONUS,
		0.0001,
		"the equipped weapon raised the attack damage"
	)
	assert_eq(
		_player().attack_controller.attack_profile(), definition.attack_definition,
		"the rig swings with the weapon's own profile"
	)

	# --- 5. dungeon 01: kill the objective enemy with the equipped weapon -----
	var travel := main.router.request_travel(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	assert_eq(travel, WorldRouter.CODE_TRAVEL_STARTED, "the run starts")
	await wait_physics_frames(10)
	assert_almost_eq(
		_player().attack_controller.attack_profile().reach, 2.2, 0.0001,
		"the weapon profile survives the world swap"
	)
	assert_true(await _kill_objective_enemy(), "the objective enemy dies to the equipped weapon")
	await wait_physics_frames(5)
	assert_true(session.progress.is_completed(&"dungeon.01"), "the dungeon is completed")
	assert_true(session.progress.is_unlocked(&"dungeon.02"), "and dungeon 02 is unlocked")
	assert_eq(session.state.inventory.count_of(DAGGER), 1, "the story reward arrived")
	assert_true(session.stats.is_ready(), "the stats survived the travel")

	# --- 6. loot the drop and the chest ---------------------------------------
	var pickups: Array[PickupInteractable] = []
	for node in _walk(main.router.current_world()):
		if node is PickupInteractable:
			pickups.append(node as PickupInteractable)
	assert_eq(pickups.size(), 1, "the boss left one drop")
	if pickups.size() == 1:
		_place_player_near(pickups[0], 1.2, -0.6)
		await wait_physics_frames(3)
		assert_true(
			InteractionController.find_on(_player()).try_interact().succeeded(), "the drop is collected"
		)
	var chest: ChestInteractable = null
	for node in _walk(main.router.current_world()):
		if node is ChestInteractable:
			chest = node as ChestInteractable
	assert_not_null(chest, "the dungeon holds the chest")
	if chest != null:
		_place_player_near(chest, 1.2, -0.6)
		await wait_physics_frames(3)
		assert_true(
			InteractionController.find_on(_player()).try_interact().succeeded(), "the chest opens"
		)
	assert_eq(session.state.inventory.count_of(SALVE), 1, "the chest loot is in the bag")

	# --- 7. return to the hub and sell the loot -------------------------------
	assert_eq(
		main.router.request_travel(&"world.hub", &"spawn.hub.dungeon_portal"),
		WorldRouter.CODE_TRAVEL_STARTED,
		"the return portal works"
	)
	await wait_physics_frames(10)
	session.trading.bind_merchant(npc_node.npc.merchant)
	var gold_before_sale := session.state.gold
	var sell_price := session.trading.sell_price(SALVE)
	assert_true(sell_price > 0, "the loot is tradable")
	assert_eq(session.trading.sell(SALVE), TradingService.CODE_OK, "the loot is sold")
	assert_eq(session.state.gold, gold_before_sale + sell_price, "gold rose by the sell price")
	assert_eq(session.state.inventory.count_of(SALVE), 0, "and the loot left the bag")

	# --- 8. equip the armour: defense rises -----------------------------------
	assert_eq(
		session.trading.buy(VEST), TradingService.CODE_OK, "the vest is bought with the loot money"
	)
	assert_eq(session.equip_item(VEST), EquipmentState.CODE_OK, "the vest is equipped")
	assert_almost_eq(
		session.stats.effective(CharacterStats.DEFENSE), float(VEST_DEFENSE), 0.0001,
		"the armour raised the defense"
	)

	# --- 9. save at the shrine and relaunch -----------------------------------
	var shrine: SaveShrineInteractable = null
	for node in _walk(main.router.current_world()):
		if node is SaveShrineInteractable:
			shrine = node as SaveShrineInteractable
	assert_not_null(shrine, "the hub shrine exists")
	if shrine != null:
		_place_player_near(shrine, 1.5, -0.5)
		await wait_physics_frames(3)
		assert_true(
			InteractionController.find_on(_player()).try_interact().succeeded(), "the shrine saves"
		)
	var expected_gold := session.state.gold
	var expected_attack := session.stats.effective(CharacterStats.ATTACK_DAMAGE)
	var expected_defense := session.stats.effective(CharacterStats.DEFENSE)
	_main = null
	await wait_process_frames(2)

	var relaunched := _instantiate_main()
	if relaunched == null:
		return
	await wait_physics_frames(20)
	assert_true(relaunched.boot_result.ok(), "the save loads: %s" % relaunched.boot_result.message)
	assert_eq(relaunched.session.state.gold, expected_gold, "gold survives the relaunch")
	assert_eq(
		relaunched.session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND),
		SWORD,
		"the weapon is still equipped"
	)
	assert_eq(
		relaunched.session.state.equipment.get_equipped(EquipmentSlot.Id.CHEST_ARMOR),
		VEST,
		"the armour is still equipped"
	)
	assert_almost_eq(
		relaunched.session.stats.effective(CharacterStats.ATTACK_DAMAGE), expected_attack, 0.0001,
		"effective stats are recomputed identically"
	)
	assert_almost_eq(
		relaunched.session.stats.effective(CharacterStats.DEFENSE), expected_defense, 0.0001,
		"defense is recomputed identically"
	)
	assert_true(relaunched.session.progress.is_completed(&"dungeon.01"), "dungeon progress survived")
	assert_true(relaunched.session.progress.is_unlocked(&"dungeon.02"), "unlocks survived")
	assert_true(
		relaunched.session.progress.was_first_clear_claimed(&"dungeon.01"), "the story claim survived"
	)
	assert_eq(
		relaunched.session.state.inventory.count_of(DAGGER), 1, "the story item survived once"
	)
	assert_eq(_player_attack_profile_id(relaunched), &"attack.player.iron_sword", "the rig uses the sword")
	assert_eq(
		relaunched.session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"and the equipment record is authoritative"
	)


func _player_attack_profile_id(main: Main) -> StringName:
	var player := main.router.current_player()
	if player == null:
		return &""
	var controller := player.get_node_or_null("AttackController") as AttackController
	if controller == null or controller.attack_profile() == null:
		return &""
	return controller.attack_profile().id
