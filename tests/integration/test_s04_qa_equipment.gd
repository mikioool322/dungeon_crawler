extends "res://tests/test_case.gd"

## S04-QA — independent verification of the equipment contract through the session
## owner (ADR-015): stat buckets follow a swap chain, every refusal is inert at the
## session level, a hand-written save is filtered by `apply_snapshot`, and the
## multi-copy edge of the "equipped is never sellable" rule is recorded.

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const TEST_SAVE_PATH := "user://test_s04_qa_equipment_session.json"

const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const DAGGER := &"item.rusty_dagger"
const SALVE := &"item.minor_salve"

var _registry: ContentRegistry = null
var _session: GameSession = null


func setup() -> void:
	_delete_save_files()
	_registry = ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)
	_session = _new_session()


func teardown() -> void:
	_session = null
	_registry = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _new_session() -> GameSession:
	var manager := SaveManager.new()
	manager.setup(TEST_SAVE_PATH)
	var session := GameSession.new()
	session.setup(_registry, manager)
	session.new_game()
	return session


func _bag(item_id: StringName) -> int:
	return _session.state.inventory.count_of(item_id)


func _state_snapshot() -> String:
	return var_to_str({
		"bag": _session.state.inventory.entries(),
		"slots": _session.state.equipment.equipped_entries(),
		"stats": [
			_session.stats.effective(CharacterStats.ATTACK_DAMAGE),
			_session.stats.effective(CharacterStats.DEFENSE),
			_session.stats.effective(CharacterStats.MAX_HEALTH),
			_session.stats.effective(CharacterStats.MOVEMENT_SPEED),
		],
		"gold": _session.state.gold,
	})


# --- swap chain ----------------------------------------------------------------

func test_a_swap_chain_through_the_session_replaces_the_stat_bucket() -> void:
	_session.state.inventory.add(_registry.find_item(SWORD), 1)
	_session.state.inventory.add(_registry.find_item(DAGGER), 1)
	_session.state.inventory.add(_registry.find_item(VEST), 1)

	assert_eq(_session.equip_item(SWORD), EquipmentState.CODE_OK, "sword equipped")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "34 + 15"
	)
	assert_eq(_bag(SWORD), 0, "the sword left the bag")

	assert_eq(_session.equip_item(DAGGER), EquipmentState.CODE_OK, "swap to the dagger")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 40.0, 0.0001,
		"the dagger's 6 replaced the sword's 15, never stacked"
	)
	assert_eq(_bag(SWORD), 1, "the sword returned to the bag")
	assert_eq(_bag(DAGGER), 0, "the dagger left the bag")
	assert_eq(_session.stats.sources().has(&"main_hand"), true, "still one hand bucket")

	assert_eq(_session.equip_item(SWORD), EquipmentState.CODE_OK, "swap back to the sword")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "back to 34 + 15"
	)
	assert_eq(_bag(DAGGER), 1, "the dagger is bagged again")

	assert_eq(
		_session.unequip_slot(EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "hand unequipped"
	)
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "back to the base"
	)
	assert_false(_session.stats.has_source(&"main_hand"), "the hand bucket is gone")
	assert_eq(_bag(SWORD), 1, "the sword is bagged")

	assert_eq(_session.equip_item(VEST), EquipmentState.CODE_OK, "the vest equips")
	assert_almost_eq(_session.stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "defense rose")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001,
		"and the attack stayed at the base"
	)


## Reported S04-QA finding (MEDIUM): `PlayerSessionState.reset_to_new_game()` replaces
## `equipment` with a fresh record and `GameSession._wire_equipment()` re-binds it but
## never re-connects `state.equipment.changed` to `_on_equipment_changed`. The session's
## public `equipment_changed` signal is therefore dead after every `new_game()` and
## every `apply_snapshot()` (i.e. after every real boot). The stats and the panels still
## follow through the direct `_sync_equipment_modifiers()` call and the
## `stats_changed`/`inventory_changed` signals, which is why the shipped suites pass.
## Regression guard for the review fix: `_wire_equipment()` re-arms the record's change signal on
## every rebuild, so the public `equipment_changed` fires after a production-shaped boot.
func test_the_equipment_changed_signal_survives_a_new_game() -> void:
	var events: Array[int] = []
	_session.equipment_changed.connect(func() -> void: events.append(1))
	_session.state.inventory.add(_registry.find_item(SWORD), 1)
	assert_eq(_session.equip_item(SWORD), EquipmentState.CODE_OK, "the equip itself succeeds")
	assert_eq(
		events.size(), 1,
		"equipment_changed fires after new_game (the signal is re-armed on every rebuild)"
	)
	assert_true(
		_session.stats.has_source(&"main_hand"),
		"and the stat bucket was updated"
	)
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"so the effective attack is correct"
	)


func test_every_session_refusal_is_inert() -> void:
	_session.state.inventory.add(_registry.find_item(SWORD), 1)
	_session.state.inventory.add(_registry.find_item(SALVE), 1)
	_session.equip_item(SWORD)

	var refusals: Array[Dictionary] = [
		{"code": EquipmentState.CODE_UNKNOWN_ITEM, "call": func() -> StringName: return _session.equip_item(&"item.ghost")},
		{"code": EquipmentState.CODE_WRONG_SLOT, "call": func() -> StringName: return _session.equip_item(SALVE)},
		{"code": EquipmentState.CODE_NOT_OWNED, "call": func() -> StringName: return _session.equip_item(DAGGER)},
		{"code": EquipmentState.CODE_SLOT_EMPTY, "call": func() -> StringName: return _session.unequip_slot(EquipmentSlot.Id.CHEST_ARMOR)},
	]
	for refusal: Dictionary in refusals:
		var before := _state_snapshot()
		var call: Callable = refusal["call"]
		var code: StringName = call.call()
		assert_eq(code, refusal["code"], "the refusal code")
		assert_eq(_state_snapshot(), before, "the refusal changed nothing (%s)" % refusal["code"])


# --- hand-written saves through the session ------------------------------------

func _snapshot() -> SaveSnapshot:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 100.0
	snapshot.gold = 5
	snapshot.world_id = &"world.hub"
	snapshot.spawn_id = &""
	return snapshot


func test_a_hand_written_save_is_filtered_by_apply_snapshot() -> void:
	var snapshot := _snapshot()
	snapshot.items = [{"id": String(SWORD), "count": 1}, {"id": String(SALVE), "count": 2}]
	snapshot.equipment = {
		"main_hand": "item.ghost",
		"hat": String(VEST),
		"chest_armor": String(SWORD),
	}
	var warnings := _session.apply_snapshot(snapshot)
	assert_eq(_session.state.equipment.equipped_slots().size(), 0, "every damaged entry is dropped")
	assert_eq(_bag(SWORD), 1, "the mismatched sword stays in the bag")
	assert_eq(_bag(SALVE), 2, "the rest of the bag survives")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001,
		"and no ghost bonus reached the stats"
	)
	# Regression guard for the review fix: the equipment drops reach the boot result, like the
	# item/world/reward filtering does.
	assert_eq(
		warnings.size(), 3,
		"every dropped equipment entry is reported in the boot result: %s" % warnings
	)
	# The rebuilt record is wired: a later equip works.
	_session.state.inventory.add(_registry.find_item(VEST), 1)
	assert_eq(_session.equip_item(VEST), EquipmentState.CODE_OK, "the session stays usable after the load")

	# A valid record is authoritative: the bagged duplicate is removed.
	var valid := _snapshot()
	valid.items = [{"id": String(SWORD), "count": 1}]
	valid.equipment = {"main_hand": String(SWORD)}
	_session.apply_snapshot(valid)
	assert_eq(
		_session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"the record wins"
	)
	assert_eq(_bag(SWORD), 0, "the bagged duplicate was removed")
	assert_almost_eq(
		_session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"and the effective stats follow the record"
	)

	# Two bagged copies: one is removed, one survives (the literal invariant cannot
	# hold for a duplicate stack, see test_s04_qa_equipment.gd).
	var duplicate := _snapshot()
	duplicate.items = [{"id": String(SWORD), "count": 2}]
	duplicate.equipment = {"main_hand": String(SWORD)}
	_session.apply_snapshot(duplicate)
	assert_eq(
		_session.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"the record is still authoritative"
	)
	assert_eq(_bag(SWORD), 1, "one spare copy stays in the bag")


# --- the multi-copy sell edge --------------------------------------------------

func test_a_spare_copy_of_an_equipped_item_can_be_sold() -> void:
	_session.state.inventory.add(_registry.find_item(SWORD), 2)
	assert_eq(_session.equip_item(SWORD), EquipmentState.CODE_OK, "one sword equips")
	assert_eq(_bag(SWORD), 1, "the spare stays in the bag")
	assert_true(_session.state.equipment.is_equipped(SWORD), "the id is marked as equipped")

	_session.trading.bind_merchant(_registry.find_merchant(&"merchant.hub.smith"))
	_session.state.gold = 0
	# Ownership A is per copy: the worn sword is untouchable, the bagged spare is ordinary goods.
	assert_eq(
		_session.trading.can_sell(SWORD), TradingService.CODE_OK,
		"the spare copy is sellable even though the same id is worn"
	)
	assert_eq(_session.trading.sell(SWORD), TradingService.CODE_OK, "and it sells")
	assert_eq(_bag(SWORD), 0, "the spare left the bag")
	assert_eq(_session.state.gold, 20, "for the half-rate price")
	assert_true(_session.state.equipment.is_equipped(SWORD), "the worn copy is untouched")
	# Now only the worn copy is left, and that one is not for sale.
	assert_eq(
		_session.trading.sell(SWORD), TradingService.CODE_EQUIPPED,
		"the worn copy alone cannot be sold"
	)
	assert_eq(
		_session.unequip_slot(EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "unequip first"
	)
	assert_eq(_session.trading.sell(SWORD), TradingService.CODE_OK, "then it sells too")
	assert_eq(_session.state.gold, 40, "for another half-rate price")
