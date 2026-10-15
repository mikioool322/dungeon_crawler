extends "res://tests/test_case.gd"

## S03 — the hub dungeon-selection panel (ADR-012, presentation only).
##
## The fixture is a hand-built session (no `Main`): one world, a start dungeon and a
## dependent dungeon, indexed through a real `ContentRegistry` and a real `GameSession`.
##
## Router route: an inner `StubRouter extends WorldRouter` overriding `request_travel`.
## A real `WorldRouter` cannot complete a travel without a `world_slot` and a
## `player_scene` (it would answer `CODE_INVALID_WORLD`), and the panel never calls the
## router itself anyway: the test wires `travel_requested -> StubRouter.request_travel`
## exactly like `GameHud` does, so the recorded call is the signal's payload.

const WORLD_ID := &"world.test.hub"
const START_ID := &"dungeon.test.start"
const LOCKED_ID := &"dungeon.test.locked"
const START_NAME := "Dungeon 01"
const LOCKED_NAME := "Dungeon 02"
const ENTRY_START := &"spawn.test.start"
const ENTRY_LOCKED := &"spawn.test.locked"
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"


class StubRouter extends WorldRouter:
	var travels: Array[Dictionary] = []

	func request_travel(world_id: StringName, spawn_id: StringName) -> StringName:
		travels.append({"world_id": world_id, "spawn_id": spawn_id})
		return WorldRouter.CODE_TRAVEL_STARTED


var _registry: ContentRegistry = null
var _session: GameSession = null
var _router: StubRouter = null
var _panel: DungeonPanel = null


func teardown() -> void:
	Input.action_release(&"move_back")
	Input.action_release(&"attack_primary")
	Input.action_release(&"ui_cancel")
	_registry = null
	_session = null
	_router = null
	_panel = null


# --- fixture ------------------------------------------------------------------

## One world, a start dungeon (no prerequisites) and a dependent dungeon that the start
## dungeon's first clear unlocks, so the registry's reachability check stays green.
func _build_board() -> void:
	var world := WorldDefinition.new()
	world.id = WORLD_ID
	world.display_name = "Test Hub"
	world.default_spawn_id = &"spawn.test.hub"
	world.scene = PackedScene.new()

	var start := DungeonDefinition.new()
	start.dungeon_id = START_ID
	start.display_name = START_NAME
	start.world_id = WORLD_ID
	start.entry_spawn_id = ENTRY_START
	start.completion_objective = &"objective.test.start"
	var unlocks: Array[StringName] = [LOCKED_ID]
	start.first_clear_unlocks = unlocks

	var locked := DungeonDefinition.new()
	locked.dungeon_id = LOCKED_ID
	locked.display_name = LOCKED_NAME
	locked.world_id = WORLD_ID
	locked.entry_spawn_id = ENTRY_LOCKED
	locked.completion_objective = &"objective.test.locked"
	var prerequisites: Array[StringName] = [START_ID]
	locked.prerequisites = prerequisites

	var manifest := ContentManifest.new()
	var worlds: Array[WorldDefinition] = [world]
	var dungeons: Array[DungeonDefinition] = [start, locked]
	manifest.worlds = worlds
	manifest.dungeons = dungeons

	_registry = ContentRegistry.build(manifest)
	_session = GameSession.new()
	_session.setup(_registry, SaveManager.new())
	_session.new_game()

	_router = StubRouter.new()
	add_to_tree(_router)

	_panel = DungeonPanel.new()
	add_to_tree(_panel)
	_panel.bind(_session, _router, _registry)
	_panel.travel_requested.connect(_router.request_travel)


func _build_player() -> PlayerController:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("%s failed to load" % PLAYER_SCENE_PATH)
		return null
	var player := packed.instantiate() as PlayerController
	if player == null:
		fail("the player scene root is not a PlayerController")
		return null
	add_to_tree(player)
	return player


# --- helpers ------------------------------------------------------------------

func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _horizontal_delta(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## The script-built row buttons, keyed by the dungeon id meta the panel sets.
func _row_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node in _panel.find_children("*", "Button", true, false):
		if node.has_meta(&"dungeon_id"):
			buttons.append(node as Button)
	return buttons


# --- view model ---------------------------------------------------------------

func test_rows_follow_manifest_order_and_live_progress() -> void:
	_build_board()
	if _panel == null:
		return
	assert_true(_registry.is_valid(), "the fixture manifest is valid: %s" % _registry.errors)

	var rows := _panel.rows()
	assert_eq(rows.size(), 2, "one row per manifest dungeon")
	if rows.size() != 2:
		return
	assert_eq(rows[0]["dungeon_id"], START_ID, "the start dungeon comes first (manifest order)")
	assert_eq(rows[1]["dungeon_id"], LOCKED_ID, "the dependent dungeon comes second")
	assert_eq(rows[0]["display_name"], START_NAME, "the display name is copied from the definition")
	assert_eq(rows[0]["state"], DungeonPanel.STATE_UNLOCKED, "the start dungeon is unlocked after new_game()")
	assert_eq(rows[0]["reason"], "", "an unlocked row carries no lock reason")
	assert_eq(rows[1]["state"], DungeonPanel.STATE_LOCKED, "the dependent dungeon starts locked")
	assert_true(rows[1]["reason"] != "", "a locked row explains itself")
	assert_true(
		String(rows[1]["reason"]).contains(START_NAME),
		"the reason names the prerequisite display name: '%s'" % rows[1]["reason"]
	)
	assert_eq(rows[0]["world_id"], WORLD_ID, "the row carries the destination world id")
	assert_eq(rows[0]["entry_spawn_id"], ENTRY_START, "the row carries the entry spawn id")
	assert_eq(rows[1]["entry_spawn_id"], ENTRY_LOCKED, "the dependent row carries its own entry spawn id")


func test_refresh_follows_progress_and_completion() -> void:
	_build_board()
	if _panel == null:
		return
	# rows() reads the session live, so even without refresh() the new state shows.
	assert_true(_session.progress.unlock(LOCKED_ID), "the test unlocks the dependent dungeon")
	var live := _panel.rows()
	assert_eq(live[1]["state"], DungeonPanel.STATE_UNLOCKED, "rows() reads progress live, without a refresh()")
	assert_eq(live[1]["reason"], "", "the lock reason is gone once unlocked")

	_panel.refresh()
	assert_eq(
		_panel.rows()[1]["state"],
		DungeonPanel.STATE_UNLOCKED,
		"refresh() shows the newly unlocked dungeon"
	)

	assert_true(_session.progress.mark_completed(START_ID), "the start dungeon is completed")
	_panel.refresh()
	var rows := _panel.rows()
	assert_eq(rows[0]["state"], DungeonPanel.STATE_COMPLETED, "a completed dungeon is shown as completed")
	assert_eq(rows[1]["state"], DungeonPanel.STATE_UNLOCKED, "the other row is unaffected")


# --- the entry gate -----------------------------------------------------------

func test_select_refuses_locked_and_records_one_travel_for_unlocked() -> void:
	_build_board()
	if _panel == null:
		return

	var refusal := _panel.select(LOCKED_ID)
	assert_eq(refusal, DungeonService.CODE_LOCKED, "a locked dungeon is refused by the session gate")
	assert_eq(_router.travels.size(), 0, "no travel was requested for the locked dungeon")

	var accepted := _panel.select(START_ID)
	assert_eq(accepted, WorldRouter.CODE_TRAVEL_STARTED, "an unlocked dungeon reports travel_started")
	assert_eq(_router.travels.size(), 1, "exactly one travel was requested")
	if _router.travels.size() == 1:
		assert_eq(
			_router.travels[0]["world_id"], WORLD_ID, "the travel carries the definition's world id"
		)
		assert_eq(
			_router.travels[0]["spawn_id"], ENTRY_START, "and the definition's entry spawn id"
		)

	assert_eq(
		_panel.select(&"dungeon.test.unknown"),
		DungeonService.CODE_UNKNOWN_DUNGEON,
		"an unknown id is refused"
	)
	assert_eq(_router.travels.size(), 1, "an unknown id never travels either")


# --- open / close and input focus ---------------------------------------------

func test_open_builds_rows_and_close_restores_cursor_and_input() -> void:
	_build_board()
	var player := _build_player()
	if _panel == null or player == null:
		return
	_panel.bind_player(player)
	player.mouse_captured = true

	_panel.open()
	assert_true(_panel.is_open(), "open() reports the panel open")
	assert_true(_panel.visible, "open() makes the panel visible")
	assert_false(player.mouse_captured, "open() releases the cursor through the player flag")

	var buttons := _row_buttons()
	assert_eq(buttons.size(), 2, "open() builds one button per dungeon")
	var by_id := {}
	for button in buttons:
		by_id[button.get_meta(&"dungeon_id")] = button
	var start_button: Button = by_id.get(START_ID)
	var locked_button: Button = by_id.get(LOCKED_ID)
	assert_not_null(start_button, "the unlocked dungeon has a row button")
	assert_not_null(locked_button, "the locked dungeon has a row button")
	if start_button != null and locked_button != null:
		assert_false(start_button.disabled, "the unlocked dungeon's button is enabled")
		assert_true(locked_button.disabled, "the locked dungeon's button is disabled")
		assert_true(
			start_button.text.contains(DungeonPanel.LABEL_ENTER),
			"the unlocked button reads ENTER: '%s'" % start_button.text
		)
		assert_true(
			locked_button.text.contains(DungeonPanel.LABEL_LOCKED),
			"the locked button reads LOCKED: '%s'" % locked_button.text
		)

	# Input focus: look, attack and movement stay suspended while the panel is open.
	player.mouse_captured = true  # a recapture must not defeat the UI lockout
	player._unhandled_input(_mouse_motion(Vector2(200.0, 0.0)))
	assert_almost_eq(player.rotation.y, 0.0, 0.0001, "look input is ignored while the panel owns the screen")
	var attack := player.get_node_or_null(^"AttackController") as AttackController
	assert_not_null(attack, "the rig has an AttackController")
	if attack == null:
		return
	player._unhandled_input(_action_event(&"attack_primary", true))
	assert_false(attack.is_busy(), "attack input is ignored while the panel owns the screen")

	var before := player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(10)
	Input.action_release(&"move_back")
	assert_almost_eq(
		_horizontal_delta(before, player.global_position),
		0.0,
		0.01,
		"movement is frozen while the panel is open"
	)

	player.mouse_captured = false  # back to the released state open() left behind
	_panel.close()
	assert_false(_panel.is_open(), "close() reports the panel closed")
	assert_false(_panel.visible, "close() hides the panel")
	assert_true(player.mouse_captured, "close() restores the cursor")

	player._unhandled_input(_action_event(&"attack_primary", true))
	assert_true(attack.is_busy(), "attack input works again after close()")
	attack.abort(&"test")

	before = player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(10)
	Input.action_release(&"move_back")
	var moved := _horizontal_delta(before, player.global_position)
	assert_true(moved > 0.2, "movement resumes after close() (moved %.3f m)" % moved)


func test_ui_cancel_closes_an_open_panel() -> void:
	_build_board()
	if _panel == null:
		return
	_panel.open()
	assert_true(_panel.is_open(), "the panel is open before the key press")

	Input.parse_input_event(_action_event(&"ui_cancel", true))
	await wait_physics_frames(2)
	Input.action_release(&"ui_cancel")

	assert_false(_panel.is_open(), "ui_cancel closes the panel")
	assert_false(_panel.visible, "and hides it")
