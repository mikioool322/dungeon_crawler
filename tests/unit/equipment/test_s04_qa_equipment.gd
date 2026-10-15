extends "res://tests/test_case.gd"

## S04-QA — independent verification of `EquipmentState` ownership semantics A (ADR-015).
##
## Gaps this file closes:
## - copy conservation across a full equip -> swap -> swap -> unequip chain (no loss,
##   no duplication, `is_equipped(id) => count_of(id) == 0` checked after every step).
## - every refusal code leaves bag, slots and modifier buckets byte-identical.
## - a damaged save record is filtered exactly as ADR-015 documents, including the
##   multi-copy case the literal invariant does not survive.
## - a not-ready state refuses every operation.

const SWORD := &"item.qa.sword"
const SWORD2 := &"item.qa.sword2"
const VEST := &"item.qa.vest"
const ROCK := &"item.qa.rock"

var _registry: ContentRegistry = null
var _bag: Inventory = null
var _equipment: EquipmentState = null


func setup() -> void:
	_registry = _build_registry()
	_bag = Inventory.new()
	_equipment = EquipmentState.new()
	_equipment.setup(_registry, _bag)


func teardown() -> void:
	_equipment = null
	_bag = null
	_registry = null


func _build_registry() -> ContentRegistry:
	var manifest := ContentManifest.new()

	var sword := _weapon(SWORD, "QA Sword", 15)
	var sword2 := _weapon(SWORD2, "QA Sword II", 25)

	var vest := ItemDefinition.new()
	vest.id = VEST
	vest.display_name = "QA Vest"
	vest.kind = ItemDefinition.Kind.MISC
	vest.stackable = false
	vest.max_stack = 1
	vest.slot = EquipmentSlot.Id.CHEST_ARMOR
	vest.defense_bonus = 5

	var rock := ItemDefinition.new()
	rock.id = ROCK
	rock.display_name = "QA Rock"
	rock.kind = ItemDefinition.Kind.MISC
	rock.stackable = true
	rock.max_stack = 5

	var items: Array[ItemDefinition] = [sword, sword2, vest, rock]
	manifest.items = items
	return ContentRegistry.build(manifest)


func _weapon(id: StringName, display_name: String, bonus: int) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = id
	item.display_name = display_name
	item.kind = ItemDefinition.Kind.WEAPON
	item.stackable = false
	item.max_stack = 1
	item.slot = EquipmentSlot.Id.MAIN_HAND
	item.attack_bonus = bonus
	return item


func _definition(item_id: StringName) -> ItemDefinition:
	return _registry.find_item(item_id)


## Copies owned by the player: bag copies plus the one worn in a slot.
func _total(item_id: StringName) -> int:
	return _bag.count_of(item_id) + (1 if _equipment.is_equipped(item_id) else 0)


func _state_snapshot() -> String:
	return var_to_str({
		"bag": _bag.entries(),
		"slots": _equipment.equipped_entries(),
		"modifiers": _equipment.modifiers_by_source(),
	})


func test_copy_conservation_through_a_full_swap_chain() -> void:
	_bag.add(_definition(SWORD), 1)
	_bag.add(_definition(SWORD2), 1)
	_bag.add(_definition(VEST), 1)

	assert_eq(_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "equip A")
	assert_eq(_bag.count_of(SWORD), 0, "A left the bag")
	assert_eq(_total(SWORD), 1, "A is conserved")
	assert_eq(_total(SWORD2), 1, "B is still in the bag")

	assert_eq(_equipment.equip(SWORD2, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "swap to B")
	assert_eq(_bag.count_of(SWORD2), 0, "B left the bag")
	assert_eq(_bag.count_of(SWORD), 1, "A returned to the bag")
	assert_eq(_total(SWORD), 1, "A is conserved across the swap")
	assert_eq(_total(SWORD2), 1, "B is conserved across the swap")
	assert_eq(_equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD2, "B is worn")

	assert_eq(_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "swap back to A")
	assert_eq(_bag.count_of(SWORD), 0, "A left the bag again")
	assert_eq(_bag.count_of(SWORD2), 1, "B returned to the bag")
	assert_eq(_total(SWORD), 1, "A is conserved on the way back")
	assert_eq(_total(SWORD2), 1, "B is conserved on the way back")

	assert_eq(_equipment.unequip(EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "unequip")
	assert_eq(_bag.count_of(SWORD), 1, "A is back in the bag")
	assert_eq(_bag.count_of(SWORD2), 1, "B is still in the bag")
	assert_eq(_bag.count_of(VEST), 1, "the untouched vest is still in the bag")
	assert_eq(_equipment.equipped_slots().size(), 0, "no slot is filled")

	# Every step above kept the two weapons at exactly one copy; two copies of one id
	# are interchangeable, so equipping one must leave the other in the bag.
	_bag.add(_definition(SWORD), 1)
	assert_eq(_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK, "equip one of two")
	assert_eq(_total(SWORD), 2, "both copies still exist")
	assert_eq(_bag.count_of(SWORD), 1, "and the spare stays in the bag")


func test_the_literal_invariant_only_holds_for_a_single_copy() -> void:
	# Single copy: the documented `is_equipped(id) => count_of(id) == 0` holds.
	_bag.add(_definition(SWORD), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	assert_true(_equipment.is_equipped(SWORD), "single copy equipped")
	assert_eq(_bag.count_of(SWORD), 0, "and not in the bag (the documented invariant)")

	# Two copies: one is worn, one stays bagged, so the *literal* invariant cannot
	# hold. This is the state the shipped suite relies on
	# (`test_the_bag_and_the_slots_never_hold_the_same_copy`), recorded here because
	# ADR-015 states the invariant without the multi-copy exception.
	_bag.add(_definition(SWORD2), 2)
	_equipment.equip(SWORD2, EquipmentSlot.Id.MAIN_HAND)
	assert_true(_equipment.is_equipped(SWORD2), "one of two copies is worn")
	assert_eq(_bag.count_of(SWORD2), 1, "the spare stays in the bag")
	assert_ne(
		_bag.count_of(SWORD2), 0,
		"so `is_equipped(id) => count_of(id) == 0` is false for a duplicate stack"
	)


func test_every_refusal_leaves_the_state_byte_identical() -> void:
	_bag.add(_definition(SWORD), 1)
	_bag.add(_definition(ROCK), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)

	var refusals: Array[Dictionary] = [
		{"code": EquipmentState.CODE_UNKNOWN_ITEM, "call": func() -> StringName: return _equipment.equip(&"item.ghost", EquipmentSlot.Id.MAIN_HAND)},
		{"code": EquipmentState.CODE_NOT_EQUIPPABLE, "call": func() -> StringName: return _equipment.equip(SWORD, EquipmentSlot.Id.CHEST_ARMOR)},
		{"code": EquipmentState.CODE_NOT_EQUIPPABLE, "call": func() -> StringName: return _equipment.equip(ROCK, EquipmentSlot.Id.MAIN_HAND)},
		{"code": EquipmentState.CODE_WRONG_SLOT, "call": func() -> StringName: return _equipment.equip(SWORD, 99)},
		{"code": EquipmentState.CODE_NOT_OWNED, "call": func() -> StringName: return _equipment.equip(SWORD2, EquipmentSlot.Id.MAIN_HAND)},
		{"code": EquipmentState.CODE_SLOT_EMPTY, "call": func() -> StringName: return _equipment.unequip(EquipmentSlot.Id.CHEST_ARMOR)},
		{"code": EquipmentState.CODE_SLOT_EMPTY, "call": func() -> StringName: return _equipment.unequip(99)},
	]
	for refusal: Dictionary in refusals:
		var before := _state_snapshot()
		var call: Callable = refusal["call"]
		var code: StringName = call.call()
		assert_eq(code, refusal["code"], "the refusal code")
		assert_eq(_state_snapshot(), before, "a refusal mutates nothing (%s)" % refusal["code"])


func test_a_not_ready_state_refuses_every_operation() -> void:
	var fresh := EquipmentState.new()
	assert_false(fresh.is_ready(), "no registry and no bag: not ready")
	assert_eq(
		fresh.can_equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_READY,
		"can_equip refuses"
	)
	assert_eq(
		fresh.equip(SWORD, EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_READY,
		"equip refuses"
	)
	assert_eq(
		fresh.unequip(EquipmentSlot.Id.MAIN_HAND),
		EquipmentState.CODE_NOT_READY,
		"unequip refuses"
	)
	assert_eq(fresh.equipped_slots().size(), 0, "nothing is equipped")
	assert_eq(fresh.to_save_dict().size(), 0, "and nothing is serialised")


func test_from_save_dict_filters_every_damage_kind() -> void:
	# Unknown item id: dropped, the bag copy stays where it is.
	var bag_a := Inventory.new()
	bag_a.add(_definition(VEST), 1)
	var a := EquipmentState.from_save_dict({"main_hand": "item.ghost"}, _registry, bag_a)
	assert_eq(a.get_equipped(EquipmentSlot.Id.MAIN_HAND), &"", "unknown id dropped")
	assert_eq(bag_a.count_of(VEST), 1, "the bag is untouched")

	# Unknown slot name: dropped.
	var bag_b := Inventory.new()
	bag_b.add(_definition(VEST), 1)
	var b := EquipmentState.from_save_dict({"hat": String(VEST)}, _registry, bag_b)
	assert_eq(b.equipped_slots().size(), 0, "unknown slot dropped")
	assert_eq(bag_b.count_of(VEST), 1, "and the item stays in the bag")

	# Slot mismatch: dropped from the slot; the bagged copy (if any) stays bagged,
	# which is the ADR-015 "returned to the bag" outcome.
	var bag_c := Inventory.new()
	bag_c.add(_definition(SWORD), 1)
	var c := EquipmentState.from_save_dict({"chest_armor": String(SWORD)}, _registry, bag_c)
	assert_eq(c.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), &"", "a sword cannot fill the chest")
	assert_eq(bag_c.count_of(SWORD), 1, "and it remains available in the bag")

	# Duplicate of one bagged copy: the record wins, the copy is removed.
	var bag_d := Inventory.new()
	bag_d.add(_definition(SWORD), 1)
	var d := EquipmentState.from_save_dict({"main_hand": String(SWORD)}, _registry, bag_d)
	assert_eq(d.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD, "the record is authoritative")
	assert_eq(bag_d.count_of(SWORD), 0, "the bagged duplicate is removed")

	# Duplicate with two bagged copies: one is removed, one stays, so the literal
	# invariant cannot hold after such a hand-written load.
	var bag_e := Inventory.new()
	bag_e.add(_definition(SWORD), 2)
	var e := EquipmentState.from_save_dict({"main_hand": String(SWORD)}, _registry, bag_e)
	assert_eq(e.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD, "the record is authoritative")
	assert_eq(bag_e.count_of(SWORD), 1, "one spare copy survives the load")

	# A valid two-slot record round-trips.
	var bag_f := Inventory.new()
	bag_f.add(_definition(SWORD), 1)
	bag_f.add(_definition(VEST), 1)
	var f := EquipmentState.from_save_dict(
		{"main_hand": String(SWORD), "chest_armor": String(VEST)}, _registry, bag_f
	)
	assert_eq(f.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD, "hand restored")
	assert_eq(f.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), VEST, "chest restored")
	assert_eq(bag_f.total_item_count(), 0, "both bagged copies were consumed by the record")

	# A missing context never crashes and yields an empty state.
	var g := EquipmentState.from_save_dict({"main_hand": String(SWORD)}, null, null)
	assert_false(g.is_ready(), "a null context is not ready")
	assert_eq(g.equipped_slots().size(), 0, "and nothing is equipped")


func test_to_save_dict_uses_only_stable_slot_names() -> void:
	_bag.add(_definition(SWORD), 1)
	_bag.add(_definition(VEST), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	_equipment.equip(VEST, EquipmentSlot.Id.CHEST_ARMOR)
	var data := _equipment.to_save_dict()
	assert_eq(data.keys().size(), 2, "one entry per filled slot")
	assert_eq(data.get("main_hand"), String(SWORD), "stable hand name")
	assert_eq(data.get("chest_armor"), String(VEST), "stable chest name")
	assert_eq(data.get("sword"), null, "no display name or asset path is written")
