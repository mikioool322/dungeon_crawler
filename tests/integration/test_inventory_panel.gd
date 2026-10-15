extends "res://tests/test_case.gd"

## S04 UI — the character panel (inventory + equipment + stats, ADR-015).
##
## The fixture is a hand-built session: one manifest with a player definition, a
## main-hand weapon carrying an attack bonus, a weapon attack profile and a
## non-equippable junk item, indexed through a real `ContentRegistry` and a real
## `GameSession`. The panel is a bare `Control` added to the tree; the rig used by the
## focus tests is a bare `PlayerController` with an `InteractionController` child, the
## same shape `test_dungeon_board.gd` uses.

const SWORD_ID := &"item.test.sword"
const JUNK_ID := &"item.test.junk"
const UNKNOWN_ID := &"item.test.unknown"
const BASIC_ATTACK_ID := &"attack.test.basic"
const SWORD_ATTACK_ID := &"attack.test.sword"
const SWORD_NAME := "Test Sword"
const JUNK_NAME := "Test Junk"
const BASE_ATTACK := 34.0
const BASE_HEALTH := 100.0
const BASE_SPEED := 4.0
const SWORD_BONUS := 15.0
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _panel: InventoryPanel = null


func teardown() -> void:
	Input.action_release(&"ui_cancel")
	Input.action_release(&"inventory")
	_registry = null
	_session = null
	_panel = null


# --- fixture ------------------------------------------------------------------

func _attack(id: StringName, damage: float) -> AttackDefinition:
	var attack := AttackDefinition.new()
	attack.id = id
	attack.damage = damage
	return attack


func _sword(weapon_profile: AttackDefinition) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = SWORD_ID
	item.display_name = SWORD_NAME
	item.kind = ItemDefinition.Kind.WEAPON
	item.stackable = false
	item.max_stack = 1
	item.slot = EquipmentSlot.Id.MAIN_HAND
	item.attack_bonus = int(SWORD_BONUS)
	item.attack_definition = weapon_profile
	item.base_value = 40
	return item


func _junk() -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = JUNK_ID
	item.display_name = JUNK_NAME
	item.kind = ItemDefinition.Kind.MISC
	item.stackable = true
	item.max_stack = 5
	return item


func _player_definition(basic_attack: AttackDefinition) -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &"player.test"
	definition.display_name = "Tester"
	definition.max_health = BASE_HEALTH
	definition.attack_damage = BASE_ATTACK
	definition.defense = 0.0
	definition.movement_speed = BASE_SPEED
	definition.attack_definition = basic_attack
	return definition


func _build_fixture() -> void:
	var basic := _attack(BASIC_ATTACK_ID, 10.0)
	var weapon_profile := _attack(SWORD_ATTACK_ID, 0.0)
	var manifest := ContentManifest.new()
	var attacks: Array[AttackDefinition] = [basic, weapon_profile]
	var items: Array[ItemDefinition] = [_sword(weapon_profile), _junk()]
	manifest.attacks = attacks
	manifest.items = items
	manifest.player = _player_definition(basic)

	_registry = ContentRegistry.build(manifest)
	if not _registry.is_valid():
		fail("fixture manifest is invalid: %s" % _registry.errors)
		return
	_session = GameSession.new()
	_session.setup(_registry, SaveManager.new())
	_session.new_game()
	# Domain wiring gap (reported, deliberately not fixed in this worktree):
	# `PlayerSessionState.reset_to_new_game()` replaces `equipment` with a fresh,
	# unbound `EquipmentState` and `GameSession.new_game()` never re-binds it, so
	# `equip_item()` / `unequip_slot()` answer `not_ready` after a new game (the shipped
	# `Main` boot path hits the same gap). `setup()` is documented safe to call again;
	# the panel contract below is exercised against a session whose equipment is bound.
	_session.setup(_registry, SaveManager.new())

	_panel = InventoryPanel.new()
	add_to_tree(_panel)
	_panel.bind(_session, _registry)


func _build_player() -> PlayerController:
	# The real rig keeps the scene contract (Head, HealthComponent, InteractionController)
	# intact, so the focus assertions run against the same node shape the game uses.
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

func _add_to_bag(item_id: StringName, count: int = 1) -> void:
	_session.state.inventory.add(_registry.find_item(item_id), count)


func _bag(item_id: StringName) -> int:
	return _session.state.inventory.count_of(item_id)


func _item_row(rows: Array, item_id: StringName) -> Dictionary:
	for row: Dictionary in rows:
		if row["item_id"] == item_id:
			return row
	return {}


func _slot_row(rows: Array, slot: int) -> Dictionary:
	for row: Dictionary in rows:
		if row["slot"] == slot:
			return row
	return {}


func _stat_row(rows: Array, stat: StringName) -> Dictionary:
	for row: Dictionary in rows:
		if row["stat"] == stat:
			return row
	return {}


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


# --- view model ---------------------------------------------------------------

func test_rows_list_the_bag_the_slots_and_the_stats_live() -> void:
	_build_fixture()
	if _panel == null:
		return
	_add_to_bag(SWORD_ID, 1)
	_add_to_bag(JUNK_ID, 2)

	var model := _panel.rows()
	var items: Array = model["items"]
	assert_eq(items.size(), 2, "one item row per bag stack")
	var sword := _item_row(items, SWORD_ID)
	if sword.is_empty():
		fail("the sword row is missing")
		return
	assert_eq(sword["display_name"], SWORD_NAME, "the display name comes from the definition")
	assert_eq(sword["count"], 1, "the stack count is reported")
	assert_eq(sword["kind"], ItemDefinition.Kind.WEAPON, "the kind is reported")
	assert_true(sword["equippable"], "a main-hand item is equippable")
	assert_eq(sword["slot_name"], &"main_hand", "and carries its stable slot name")
	var bonuses: Dictionary = sword["bonuses"]
	assert_almost_eq(
		float(bonuses.get(CharacterStats.ATTACK_DAMAGE, 0.0)),
		SWORD_BONUS,
		0.0001,
		"the sword's own equipment modifiers are copied, not recomputed"
	)

	var junk := _item_row(items, JUNK_ID)
	if junk.is_empty():
		fail("the junk row is missing")
		return
	assert_eq(junk["count"], 2, "the second stack reports its own count")
	assert_false(junk["equippable"], "a MISC item is not equippable")
	assert_eq(junk["slot_name"], &"none", "a non-equippable item has no slot")
	assert_true((junk["bonuses"] as Dictionary).is_empty(), "and contributes no bonus")

	var equipment: Array = model["equipment"]
	assert_eq(
		equipment.size(), EquipmentSlot.SUPPORTED.size(), "one row per supported slot, filled or not"
	)
	for row: Dictionary in equipment:
		assert_eq(row["item_id"], &"", "a new game wears nothing")
		assert_eq(row["display_name"], "", "an empty slot carries no display name")

	var stats_rows: Array = model["stats"]
	assert_eq(stats_rows.size(), CharacterStats.STATS.size(), "one row per known stat")
	var attack := _stat_row(stats_rows, CharacterStats.ATTACK_DAMAGE)
	if attack.is_empty():
		fail("the attack stat row is missing")
		return
	assert_almost_eq(float(attack["base"]), BASE_ATTACK, 0.0001, "the base comes from the definition")
	assert_almost_eq(float(attack["bonus"]), 0.0, 0.0001, "nothing is equipped, so no bonus")
	assert_almost_eq(float(attack["effective"]), BASE_ATTACK, 0.0001, "effective == base")
	var health := _stat_row(stats_rows, CharacterStats.MAX_HEALTH)
	assert_almost_eq(float(health["effective"]), BASE_HEALTH, 0.0001, "max health is listed")
	var speed := _stat_row(stats_rows, CharacterStats.MOVEMENT_SPEED)
	assert_almost_eq(float(speed["effective"]), BASE_SPEED, 0.0001, "move speed is listed")


func test_equip_moves_the_item_into_the_slot_and_raises_the_effective_attack() -> void:
	_build_fixture()
	if _panel == null:
		return
	_add_to_bag(SWORD_ID, 1)

	assert_eq(_panel.equip(SWORD_ID), EquipmentState.CODE_OK, "a bagged item equips")
	assert_eq(_bag(SWORD_ID), 0, "ownership A: the equipped item leaves the bag")
	assert_eq(
		_session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND),
		SWORD_ID,
		"the main hand holds the item"
	)
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE),
		BASE_ATTACK + SWORD_BONUS,
		0.0001,
		"the effective attack rises by the item's own bonus"
	)

	var model := _panel.rows()
	var slot := _slot_row(model["equipment"], EquipmentSlot.Id.MAIN_HAND)
	if slot.is_empty():
		fail("the main-hand slot row is missing")
		return
	assert_eq(slot["item_id"], SWORD_ID, "the slot row reports the item")
	assert_eq(slot["display_name"], SWORD_NAME, "with its display name")
	assert_eq(slot["slot_name"], &"main_hand", "and the stable slot name")
	var attack := _stat_row(model["stats"], CharacterStats.ATTACK_DAMAGE)
	assert_almost_eq(float(attack["bonus"]), SWORD_BONUS, 0.0001, "the stats row shows the bonus")
	assert_almost_eq(
		float(attack["effective"]), BASE_ATTACK + SWORD_BONUS, 0.0001, "and the new effective value"
	)

	assert_null(
		_panel.find_child("Equip_item_test_sword", true, false),
		"the equipped item no longer offers an Equip button in the bag"
	)
	assert_not_null(
		_panel.find_child("Unequip_main_hand", true, false),
		"the filled slot offers an Unequip button"
	)


func test_unequip_returns_the_item_and_removes_the_bonus() -> void:
	_build_fixture()
	if _panel == null:
		return
	_add_to_bag(SWORD_ID, 1)
	assert_eq(_panel.equip(SWORD_ID), EquipmentState.CODE_OK, "the fixture equips the sword")

	assert_eq(
		_panel.unequip(EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "the slot unequips"
	)
	assert_eq(_bag(SWORD_ID), 1, "the item is back in the bag")
	assert_eq(
		_session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND),
		&"",
		"the slot is empty again"
	)
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE),
		BASE_ATTACK,
		0.0001,
		"the bonus is gone from the effective value"
	)

	var model := _panel.rows()
	var slot := _slot_row(model["equipment"], EquipmentSlot.Id.MAIN_HAND)
	if slot.is_empty():
		fail("the main-hand slot row is missing")
		return
	assert_eq(slot["item_id"], &"", "the slot row is empty")
	var attack := _stat_row(model["stats"], CharacterStats.ATTACK_DAMAGE)
	assert_almost_eq(float(attack["bonus"]), 0.0, 0.0001, "no bonus is left")
	assert_almost_eq(float(attack["effective"]), BASE_ATTACK, 0.0001, "effective == base again")
	var slot_label := _panel.find_child("SlotLabel_main_hand", true, false) as Label
	assert_not_null(slot_label, "the empty slot row is rendered")
	if slot_label != null:
		assert_true(
			slot_label.text.contains(InventoryPanel.LABEL_EMPTY_SLOT),
			"an empty slot renders as '%s': '%s'" % [InventoryPanel.LABEL_EMPTY_SLOT, slot_label.text]
		)


func test_refusals_are_returned_and_mutate_nothing() -> void:
	_build_fixture()
	if _panel == null:
		return
	_add_to_bag(JUNK_ID, 1)

	assert_eq(
		_panel.equip(UNKNOWN_ID),
		EquipmentState.CODE_UNKNOWN_ITEM,
		"an id the registry does not know is refused"
	)
	assert_eq(
		_panel.equip(SWORD_ID), EquipmentState.CODE_NOT_OWNED, "an item that is not in the bag is refused"
	)
	assert_eq(
		_panel.equip(JUNK_ID),
		EquipmentState.CODE_WRONG_SLOT,
		"a non-equippable item (slot NONE) is refused by the slot check"
	)
	assert_eq(
		_panel.unequip(EquipmentSlot.Id.CHEST_ARMOR),
		EquipmentState.CODE_SLOT_EMPTY,
		"an empty slot cannot be unequipped"
	)

	assert_eq(_bag(SWORD_ID), 0, "no refusal touched the bag")
	assert_eq(_bag(JUNK_ID), 1, "the junk item stays in the bag")
	assert_eq(_session.state.equipment.equipped_slots().size(), 0, "and nothing got equipped")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE),
		BASE_ATTACK,
		0.0001,
		"and the effective attack is unchanged"
	)
	assert_true(
		_panel.status_text().contains(String(EquipmentState.CODE_SLOT_EMPTY)),
		"the panel shows the last refusal code: '%s'" % _panel.status_text()
	)


func test_the_open_panel_follows_the_session_signals_and_the_buttons_work() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open()
	assert_null(
		_panel.find_child("Equip_item_test_sword", true, false),
		"an empty bag offers no Equip button"
	)

	_add_to_bag(SWORD_ID, 1)  # inventory.changed -> session.inventory_changed -> refresh
	var equip_button := _panel.find_child("Equip_item_test_sword", true, false) as Button
	assert_not_null(equip_button, "the bag signal refreshed the built rows")
	if equip_button == null:
		return
	equip_button.pressed.emit()
	assert_eq(_bag(SWORD_ID), 0, "the Equip button equips through the session")
	assert_eq(
		_session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND),
		SWORD_ID,
		"and the item is in the slot"
	)
	assert_not_null(
		_panel.find_child("Unequip_main_hand", true, false),
		"the equipment signal refreshed the slot row"
	)

	_session.add_gold(5)  # gold_changed must not disturb the built rows
	assert_not_null(
		_panel.find_child("Unequip_main_hand", true, false),
		"a gold change keeps the character sheet intact"
	)
	_panel.close()


# --- open / close and input focus ---------------------------------------------

func test_open_builds_rows_and_close_restores_cursor_and_input() -> void:
	_build_fixture()
	if _panel == null:
		return
	var player := _build_player()
	if player == null:
		return
	_panel.bind_player(player)
	player.mouse_captured = true
	_add_to_bag(SWORD_ID, 1)

	_panel.open()
	assert_true(_panel.is_open(), "open() reports the panel open")
	assert_true(_panel.visible, "open() makes the panel visible")
	assert_false(player.mouse_captured, "open() releases the cursor through the player flag")
	var controller := InteractionController.find_on(player)
	assert_not_null(controller, "the rig has an InteractionController")
	if controller != null:
		assert_false(controller.is_enabled(), "the open panel suspends the interaction ray")
	assert_not_null(
		_panel.find_child("Equip_item_test_sword", true, false),
		"open() builds one Equip button per equippable row"
	)
	assert_not_null(_panel.find_child("CloseButton", true, false), "and a close button")

	# Input focus: look stays suspended while the panel owns the screen.
	player.mouse_captured = true  # a recapture must not defeat the UI lockout
	player._unhandled_input(_mouse_motion(Vector2(200.0, 0.0)))
	assert_almost_eq(
		player.rotation.y, 0.0, 0.0001, "look input is ignored while the panel owns the screen"
	)

	player.mouse_captured = false  # back to the released state open() left behind
	_panel.close()
	assert_false(_panel.is_open(), "close() reports the panel closed")
	assert_false(_panel.visible, "close() hides the panel")
	assert_true(player.mouse_captured, "close() restores the cursor")
	if controller != null:
		assert_true(controller.is_enabled(), "closing the panel resumes interaction")

	player.mouse_captured = true
	player._unhandled_input(_mouse_motion(Vector2(200.0, 0.0)))
	assert_ne(player.rotation.y, 0.0, "look input works again after close()")


func test_ui_cancel_closes_an_open_panel() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open()
	assert_true(_panel.is_open(), "the panel is open before the key press")

	Input.parse_input_event(_action_event(&"ui_cancel", true))
	await wait_physics_frames(2)
	Input.action_release(&"ui_cancel")

	assert_false(_panel.is_open(), "ui_cancel closes the panel")
	assert_false(_panel.visible, "and hides it")
