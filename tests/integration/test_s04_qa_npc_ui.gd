extends "res://tests/test_case.gd"

## S04-QA — independent verification of the ADR-017/ADR-008 NPC and panel contracts on
## the real composition root.
##
## Gaps this file closes:
## - NPC focus/refusal is driven through the real interaction ray: out of reach and
##   behind a wall both yield no focus and no interaction.
## - closing the dialogue restores cursor, interaction ray and player input, and an open
##   panel really blocks attacks (not only look input).
## - exactly one panel owns the screen across dialogue -> inventory.
## - the shop entry exists only on a dialogue whose NPC has a merchant.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_s04_qa_npc_ui.json"

var _main: Main = null


func setup() -> void:
	_delete_save_files()


func teardown() -> void:
	_main = null
	Input.action_release(&"ui_cancel")
	Input.action_release(&"inventory")
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


func _npc() -> NpcInteractable:
	for node in _walk(_main.router.current_world()):
		if node is NpcInteractable:
			return node as NpcInteractable
	return null


## Places the player at `position` with the body yaw looking at `target` (the camera
## looks along -Z, so yaw = atan2(-dx, -dz)).
func _place_player_looking_at(position: Vector3, target: Vector3, pitch: float = 0.0) -> void:
	var player := _player()
	if player == null:
		return
	player.global_position = position
	var direction := target - position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.velocity = Vector3.ZERO
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = pitch


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _press_attack() -> void:
	_player()._unhandled_input(_action_event(&"attack_primary", true))


func _press_ui_cancel() -> void:
	if _main != null and _main.hud != null:
		_main.hud._unhandled_input(_action_event(&"ui_cancel", true))


func _press_inventory() -> void:
	Input.parse_input_event(_action_event(&"inventory", true))
	Input.flush_buffered_events()


# --- the real ray --------------------------------------------------------------

func test_npc_focus_needs_reach_and_line_of_sight() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var npc := _npc()
	assert_not_null(npc, "the hub holds the merchant NPC")
	if npc == null:
		return
	var controller := InteractionController.find_on(_player())
	assert_not_null(controller, "the rig has its InteractionController")
	if controller == null:
		return

	# In reach, in the open: focused.
	_place_player_looking_at(npc.global_position + Vector3(0, 0, 1.5), npc.global_position)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), npc, "the NPC is focused through the real ray")

	# Out of reach: no focus, and no interaction can resolve.
	_place_player_looking_at(npc.global_position + Vector3(0, 0, 4.0), npc.global_position)
	await wait_physics_frames(3)
	assert_null(controller.current_focus(), "4 m away is beyond the 2.5 m ray: no focus")
	var resolved: Array[InteractionResult] = []
	controller.interaction_resolved.connect(func(result: InteractionResult) -> void: resolved.append(result))
	var refused := controller.try_interact()
	assert_false(refused.succeeded(), "an out-of-reach interact is refused: %s" % refused)
	assert_eq(resolved.size(), 0, "and nothing was resolved")

	# Behind a wall inside reach: still no focus (a hand-built fixture isolates the
	# occlusion rule from the hub's geometry).
	var wall_fixture := Node3D.new()
	add_to_tree(wall_fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10, 1, 10)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, -1.5)
	wall_fixture.add_child(floor_body)

	var npc_definition := NpcDefinition.new()
	npc_definition.id = &"npc.qa.hermit"
	npc_definition.display_name = "QA Hermit"
	npc_definition.greeting = "Nothing to sell."
	var hidden_npc := NpcInteractable.new()
	hidden_npc.npc = npc_definition
	hidden_npc.name = "HiddenNpc"
	var npc_shape := CollisionShape3D.new()
	var npc_capsule := CapsuleShape3D.new()
	npc_capsule.radius = 0.5
	npc_capsule.height = 1.8
	npc_shape.shape = npc_capsule
	npc_shape.position = Vector3(0, 0.9, 0)
	hidden_npc.add_child(npc_shape)
	hidden_npc.position = Vector3(0, 0, -1.5)
	wall_fixture.add_child(hidden_npc)

	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(2, 2, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0, 1, -0.75)
	wall_fixture.add_child(wall)

	var player_scene := load("res://actors/player/player.tscn") as PackedScene
	assert_not_null(player_scene, "the player scene loads")
	if player_scene == null:
		return
	var fixture_player := player_scene.instantiate() as PlayerController
	assert_not_null(fixture_player, "the player scene root is a PlayerController")
	if fixture_player == null:
		return
	add_to_tree(fixture_player)
	fixture_player.global_position = Vector3(0, 0, 0)
	fixture_player.rotation.y = 0.0
	await wait_physics_frames(4)
	var fixture_controller := InteractionController.find_on(fixture_player)
	assert_not_null(fixture_controller, "the fixture rig has its InteractionController")
	if fixture_controller == null:
		return
	assert_null(
		fixture_controller.current_focus(),
		"the wall blocks the NPC even though it is only 1.5 m away"
	)

	# Removing the wall exposes the same NPC: the refusal was the wall, not the setup.
	wall.queue_free()
	await wait_physics_frames(4)
	assert_eq(
		fixture_controller.current_focus(), hidden_npc,
		"without the wall the same NPC is focused"
	)
	var interacted := fixture_controller.try_interact()
	assert_true(interacted.succeeded(), "and can be talked to: %s" % interacted)


# --- dialogue input ownership --------------------------------------------------

func test_the_dialogue_blocks_attacks_and_escape_restores_control() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var npc := _npc()
	assert_not_null(npc, "the hub holds the merchant NPC")
	if npc == null:
		return
	var player := _player()
	var controller := InteractionController.find_on(player)
	_place_player_looking_at(npc.global_position + Vector3(0, 0, 1.5), npc.global_position)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), npc, "the NPC is focused")
	assert_true(controller.try_interact().succeeded(), "talking succeeds")
	assert_true(main.hud.dialogue_panel.is_open(), "the dialogue opened through the HUD")
	assert_false(player.mouse_captured, "the open dialogue released the cursor")
	assert_false(controller.is_enabled(), "and suspended the interaction ray")

	# The panel owns the screen: look and attack input are both ignored.
	var rotation_before := player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(200.0, 0.0)
	player._unhandled_input(motion)
	assert_almost_eq(player.rotation.y, rotation_before, 0.0001, "look input is ignored while open")
	_press_attack()
	assert_eq(
		player.attack_controller.phase, AttackController.Phase.IDLE,
		"no swing starts while the dialogue owns the screen"
	)
	assert_almost_eq(player.attack_controller.cooldown_remaining(), 0.0, 0.0001, "no cooldown started")

	# Escape closes it and hands everything back.
	_press_ui_cancel()
	assert_false(main.hud.dialogue_panel.is_open(), "Escape closed the dialogue")
	assert_true(player.mouse_captured, "the cursor returned")
	assert_true(controller.is_enabled(), "interaction resumed")
	player._unhandled_input(motion)
	assert_ne(player.rotation.y, rotation_before, "look input works again")
	_press_attack()
	assert_eq(
		player.attack_controller.phase, AttackController.Phase.WINDUP,
		"attacks work again after the dialogue closed"
	)
	player.attack_controller.abort(&"test")


func test_an_open_inventory_panel_blocks_attacks() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var player := _player()
	_press_inventory()
	await wait_physics_frames(2)
	Input.action_release(&"inventory")
	assert_true(main.hud.inventory_panel.is_open(), "the inventory action opened the character panel")
	assert_false(player.mouse_captured, "the open panel released the cursor")

	var rotation_before := player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(200.0, 0.0)
	player._unhandled_input(motion)
	assert_almost_eq(player.rotation.y, rotation_before, 0.0001, "look input is ignored while open")
	_press_attack()
	assert_eq(
		player.attack_controller.phase, AttackController.Phase.IDLE,
		"no swing starts while the character panel owns the screen"
	)
	assert_null(player.attack_controller.last_result(), "and no swing ever resolved")

	_press_ui_cancel()
	assert_false(main.hud.inventory_panel.is_open(), "Escape closed the panel")
	assert_true(player.mouse_captured, "the cursor returned")
	_press_attack()
	assert_eq(
		player.attack_controller.phase, AttackController.Phase.WINDUP,
		"attacks work again after the panel closed"
	)
	player.attack_controller.abort(&"test")


func test_exactly_one_panel_owns_the_screen() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var npc := _npc()
	if npc == null:
		fail("no NPC to talk to")
		return
	_place_player_looking_at(npc.global_position + Vector3(0, 0, 1.5), npc.global_position)
	await wait_physics_frames(3)
	assert_true(InteractionController.find_on(_player()).try_interact().succeeded(), "dialogue opens")
	assert_true(main.hud.dialogue_panel.is_open(), "the dialogue is open")

	_press_inventory()
	await wait_physics_frames(2)
	Input.action_release(&"inventory")
	assert_true(main.hud.inventory_panel.is_open(), "the character panel opened")
	assert_false(main.hud.dialogue_panel.is_open(), "and the dialogue handed the screen over")

	_press_ui_cancel()
	assert_false(main.hud.inventory_panel.is_open(), "Escape closed the last panel")
	assert_false(main.hud.shop_panel.is_open(), "no other panel was left open")
	assert_true(_player().mouse_captured, "input is back with the game")


# --- shop gate -----------------------------------------------------------------

func test_the_shop_entry_needs_a_merchant_dialogue() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var npc := _npc()
	assert_not_null(npc, "the shipped smith exists")
	if npc == null:
		return
	assert_true(npc.npc.has_shop(), "the shipped NPC has a merchant")

	var hermit := NpcDefinition.new()
	hermit.id = &"npc.qa.hermit"
	hermit.display_name = "QA Hermit"
	hermit.greeting = "Leave me be."
	assert_null(hermit.merchant, "the fixture NPC has no merchant")

	# Open the dialogue exactly the way the world announces it.
	main.hud._on_dialogue_requested(hermit)
	assert_true(main.hud.dialogue_panel.is_open(), "the hermit dialogue opens")
	assert_false(main.hud.dialogue_panel.has_shop_button(), "but it offers no shop entry")
	assert_false(main.hud.shop_panel.is_open(), "and no shop panel opened")
	assert_null(main.hud.shop_panel.find_child("ShopButton", true, false), "no shop button exists")
	assert_false(
		main.session.trading.is_ready(),
		"the trade service stays unbound while no shop is open"
	)
	_press_ui_cancel()
	assert_false(main.hud.dialogue_panel.is_open(), "Escape closes the hermit dialogue")
