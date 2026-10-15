extends "res://tests/test_case.gd"

## AC-36 — equipment under ownership semantics A: an equipped item leaves the bag, a swap
## returns the previous one, every refusal mutates nothing, and the save round trip is
## tolerant.

const SWORD := &"item.test.sword"
const VEST := &"item.test.vest"
const ROCK := &"item.test.rock"

var _registry: ContentRegistry = null
var _bag: Inventory = null
var _equipment: EquipmentState = null


func setup() -> void:
	_registry = _build_registry()
	_bag = Inventory.new()
	_equipment = EquipmentState.new()
	_equipment.setup(_registry, _bag)


func _build_registry() -> ContentRegistry:
	var manifest := ContentManifest.new()

	var sword := ItemDefinition.new()
	sword.id = SWORD
	sword.display_name = "Test Sword"
	sword.kind = ItemDefinition.Kind.WEAPON
	sword.stackable = false
	sword.max_stack = 1
	sword.slot = EquipmentSlot.Id.MAIN_HAND
	sword.attack_bonus = 15
	sword.base_value = 40

	var vest := ItemDefinition.new()
	vest.id = VEST
	vest.display_name = "Test Vest"
	vest.kind = ItemDefinition.Kind.MISC
	vest.stackable = false
	vest.max_stack = 1
	vest.slot = EquipmentSlot.Id.CHEST_ARMOR
	vest.defense_bonus = 5
	vest.base_value = 30

	var rock := ItemDefinition.new()
	rock.id = ROCK
	rock.display_name = "Test Rock"
	rock.kind = ItemDefinition.Kind.MISC
	rock.stackable = true
	rock.max_stack = 5

	var items: Array[ItemDefinition] = [sword, vest, rock]
	manifest.items = items
	return ContentRegistry.build(manifest)


func _definition(item_id: StringName) -> ItemDefinition:
	return _registry.find_item(item_id)


func teardown() -> void:
	# Lambda connections and the shared instances: drop the references to avoid a cycle.
	_equipment = null
	_bag = null
	_registry = null


# --- can_equip ----------------------------------------------------------------

func test_can_equip_reports_every_refusal_reason() -> void:
	assert_eq(
		_equipment.can_equip(&"item.ghost", EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_UNKNOWN_ITEM,
		"unknown id"
	)
	assert_eq(
		_equipment.can_equip(SWORD, EquipmentSlot.Id.CHEST_ARMOR),
		EquipmentState.CODE_NOT_EQUIPPABLE,
		"wrong slot"
	)
	assert_eq(
		_equipment.can_equip(ROCK, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_EQUIPPABLE,
		"a non-equippable item"
	)
	assert_eq(
		_equipment.can_equip(SWORD, 99),
		EquipmentState.CODE_WRONG_SLOT,
		"an unsupported slot"
	)
	assert_eq(
		_equipment.can_equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_OWNED,
		"not in the bag yet"
	)
	_bag.add(_definition(SWORD), 1)
	assert_eq(
		_equipment.can_equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_OK,
		"owned and compatible"
	)


# --- equip / unequip ----------------------------------------------------------

func test_equipping_moves_the_item_out_of_the_bag() -> void:
	_bag.add(_definition(SWORD), 1)
	var changed: Array[int] = []
	_equipment.changed.connect(func() -> void: changed.append(1))

	assert_eq(_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "equipped")
	assert_eq(_equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD, "the slot holds it")
	assert_eq(_bag.count_of(SWORD), 0, "the bag no longer holds it (ownership A)")
	assert_true(_equipment.is_equipped(SWORD), "is_equipped agrees")
	assert_eq(changed.size(), 1, "one notification")


func test_equipping_an_unowned_item_is_refused_without_mutation() -> void:
	assert_eq(
		_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_OWNED,
		"refused"
	)
	assert_eq(_equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), &"", "the slot stays empty")
	assert_eq(_bag.count_of(SWORD), 0, "the bag is untouched")


func test_a_swap_returns_the_previous_item_to_the_bag() -> void:
	var other := _make_sword_copy()
	_bag.add(_definition(SWORD), 1)
	_bag.add(other, 1)
	assert_eq(_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "first")
	assert_eq(_equipment.equip(other.id, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "swap")
	assert_eq(_equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), other.id, "the new weapon is worn")
	assert_eq(_bag.count_of(SWORD), 1, "the previous weapon went back to the bag")
	assert_eq(_bag.count_of(other.id), 0, "the new weapon left the bag")


func test_unequip_returns_the_item_and_is_idempotent() -> void:
	_bag.add(_definition(VEST), 1)
	_equipment.equip(VEST, EquipmentSlot.Id.CHEST_ARMOR)
	assert_eq(_equipment.unequip(EquipmentSlot.Id.CHEST_ARMOR), EquipmentState.CODE_OK, "unequipped")
	assert_eq(_bag.count_of(VEST), 1, "back in the bag")
	assert_eq(_equipment.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), &"", "the slot is empty")
	assert_eq(
		_equipment.unequip(EquipmentSlot.Id.CHEST_ARMOR),
		EquipmentState.CODE_SLOT_EMPTY,
		"a second unequip is refused"
	)


func test_one_copy_cannot_be_equipped_twice() -> void:
	_bag.add(_definition(SWORD), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	assert_eq(
		_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_OWNED,
		"the only copy is already worn"
	)


func test_the_bag_and_the_slots_never_hold_the_same_copy() -> void:
	_bag.add(_definition(SWORD), 2)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	assert_eq(_bag.count_of(SWORD), 1, "one copy stays in the bag")
	assert_true(_equipment.is_equipped(SWORD), "one copy is worn")
	_equipment.unequip(EquipmentSlot.Id.MAIN_HAND)
	assert_eq(_bag.count_of(SWORD), 2, "both copies are back")


# --- modifiers ----------------------------------------------------------------

func test_modifiers_are_exported_per_slot() -> void:
	_bag.add(_definition(SWORD), 1)
	_bag.add(_definition(VEST), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	_equipment.equip(VEST, EquipmentSlot.Id.CHEST_ARMOR)

	var by_source := _equipment.modifiers_by_source()
	assert_eq(by_source.size(), 2, "one bucket per slot")
	var hand: Dictionary = by_source[&"main_hand"]
	assert_almost_eq(hand[CharacterStats.ATTACK_DAMAGE], 15.0, 0.0001, "sword attack")
	var chest: Dictionary = by_source[&"chest_armor"]
	assert_almost_eq(chest[CharacterStats.DEFENSE], 5.0, 0.0001, "vest defense")


func test_a_swap_replaces_the_bucket_of_the_slot() -> void:
	var other := _make_sword_copy()
	_bag.add(_definition(SWORD), 1)
	_bag.add(other, 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	_equipment.equip(other.id, EquipmentSlot.Id.MAIN_HAND)
	var by_source := _equipment.modifiers_by_source()
	assert_eq(by_source.size(), 1, "still one hand bucket")
	var hand: Dictionary = by_source[&"main_hand"]
	assert_almost_eq(hand[CharacterStats.ATTACK_DAMAGE], 25.0, 0.0001, "the new weapon's bonus")


# --- persistence --------------------------------------------------------------

func test_the_save_round_trip_uses_stable_slot_names() -> void:
	_bag.add(_definition(SWORD), 1)
	_bag.add(_definition(VEST), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	_equipment.equip(VEST, EquipmentSlot.Id.CHEST_ARMOR)

	var data := _equipment.to_save_dict()
	assert_eq(data.get("main_hand"), String(SWORD), "stable slot name")
	assert_eq(data.get("chest_armor"), String(VEST), "stable slot name")

	var restored_bag := Inventory.new()
	var restored := EquipmentState.from_save_dict(data, _registry, restored_bag)
	assert_eq(restored.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD, "hand restored")
	assert_eq(restored.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), VEST, "chest restored")


func test_loading_drops_unknown_ids_and_slots_and_returns_mismatches_to_the_bag() -> void:
	var bag := Inventory.new()
	bag.add(_definition(VEST), 1)
	var data := {
		"main_hand": "item.ghost",
		"hat": "item.test.vest",
		"chest_armor": String(VEST),
	}
	var restored := EquipmentState.from_save_dict(data, _registry, bag)
	assert_eq(restored.get_equipped(EquipmentSlot.Id.MAIN_HAND), &"", "unknown item dropped")
	assert_eq(restored.equipped_slots().size(), 1, "only the valid slot survives")
	assert_eq(restored.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), VEST, "the valid entry stayed")
	assert_eq(bag.count_of(VEST), 0, "the equipment record wins over the bag copy")


func test_a_slot_mismatch_in_the_save_is_returned_to_the_bag() -> void:
	var bag := Inventory.new()
	var data := {"chest_armor": String(SWORD)}  # a sword in the armour slot
	var restored := EquipmentState.from_save_dict(data, _registry, bag)
	assert_eq(restored.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), &"", "mismatch dropped")
	assert_eq(bag.count_of(SWORD), 1, "and the copy went back to the bag instead of being lost")
	assert_eq(restored.load_warnings().size(), 1, "the load reports what it changed")


func test_a_non_equippable_record_is_returned_to_the_bag_too() -> void:
	var bag := Inventory.new()
	var data := {"main_hand": String(ROCK)}  # a rock cannot be worn
	var restored := EquipmentState.from_save_dict(data, _registry, bag)
	assert_eq(restored.equipped_slots().size(), 0, "nothing equipped")
	assert_eq(bag.count_of(ROCK), 1, "the rock is in the bag")


func test_unknown_records_report_but_cannot_return_anything() -> void:
	var bag := Inventory.new()
	var data := {"main_hand": "item.ghost", "hat": String(SWORD)}
	var restored := EquipmentState.from_save_dict(data, _registry, bag)
	assert_eq(restored.equipped_slots().size(), 0, "nothing equipped")
	assert_eq(bag.count_of(SWORD), 0, "an unknown slot never invents a copy")
	assert_eq(restored.load_warnings().size(), 2, "both drops are reported")


func test_an_empty_save_mapping_yields_empty_equipment() -> void:
	var restored := EquipmentState.from_save_dict({}, _registry, Inventory.new())
	assert_eq(restored.equipped_slots().size(), 0, "nothing equipped")


func _make_sword_copy() -> ItemDefinition:
	var copy := ItemDefinition.new()
	copy.id = &"item.test.sword2"
	copy.display_name = "Test Sword II"
	copy.kind = ItemDefinition.Kind.WEAPON
	copy.stackable = false
	copy.max_stack = 1
	copy.slot = EquipmentSlot.Id.MAIN_HAND
	copy.attack_bonus = 25
	copy.base_value = 60
	# Registered through a fresh registry so the copy is a real content item.
	var manifest := ContentManifest.new()
	var items: Array[ItemDefinition] = [
		_registry.find_item(SWORD), _registry.find_item(VEST), _registry.find_item(ROCK), copy,
	]
	manifest.items = items
	_registry = ContentRegistry.build(manifest)
	_equipment.setup(_registry, _bag)
	return copy
