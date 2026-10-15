class_name EquipmentState
extends RefCounted

## What the player currently wears (ADR-015, ownership semantics A).
##
## Ownership rule: an equipped item is *not* in the bag. `equip()` removes one copy
## from the `Inventory` and stores the stable item id in the slot; `unequip()` returns
## it to the bag. A swap returns the previous item to the bag in the same operation.
## Consequences: an equipped item cannot be sold (it is not in the bag), equipping the
## same item twice cannot stack bonuses, and no per-instance identity is needed.
##
## Invariants:
## - Only the slot map is state; the inventory and the registry are references to the
##   session's own objects, never copies.
## - Every mutation validates first and is atomic: a failure leaves both the bag and the
##   slots untouched.
## - Holds no Node and no Resource reference that is serialised: `to_save_dict()` writes
##   stable slot names and item ids only.

signal changed()

const CODE_OK := &"ok"
const CODE_UNKNOWN_ITEM := &"unknown_item"
const CODE_NOT_EQUIPPABLE := &"not_equippable"
const CODE_WRONG_SLOT := &"wrong_slot"
const CODE_NOT_OWNED := &"not_owned"
const CODE_SLOT_EMPTY := &"slot_empty"
const CODE_NOT_READY := &"not_ready"

## slot (EquipmentSlot.Id) -> item id (StringName)
var _equipped: Dictionary = {}
var _registry: ContentRegistry = null
var _inventory: Inventory = null


## Binds the session's inventory and content registry. Safe to call again.
func setup(registry: ContentRegistry, inventory: Inventory) -> void:
	_registry = registry
	_inventory = inventory


func is_ready() -> bool:
	return _registry != null and _inventory != null


func get_equipped(slot: int) -> StringName:
	return _equipped.get(slot, &"")


func equipped_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot: int in _equipped.keys():
		slots.append(slot)
	slots.sort()
	return slots


## `[{"slot": int, "item_id": StringName}]`, ordered by slot; for panels and tests.
func equipped_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in equipped_slots():
		entries.append({"slot": slot, "item_id": get_equipped(slot)})
	return entries


func is_equipped(item_id: StringName) -> bool:
	return _equipped.values().has(item_id)


## Additive modifiers per equipment slot: `{slot_name: {stat: value}}`. This is the single
## place that turns equipment into `CharacterStats` modifier buckets (ADR-015): one bucket
## per slot, so a swap replaces the bucket and the old bonus disappears automatically.
func modifiers_by_source() -> Dictionary:
	var by_source: Dictionary = {}
	for slot in equipped_slots():
		var definition := _definition_of(get_equipped(slot))
		if definition == null:
			continue
		var modifiers := definition.equipment_modifiers()
		if modifiers.is_empty():
			continue
		by_source[EquipmentSlot.name_of(slot)] = modifiers
	return by_source


## The attack profile of the equipped main-hand weapon, or null when there is none
## (the character's default profile then applies).
func weapon_attack_definition() -> AttackDefinition:
	var definition := _definition_of(get_equipped(EquipmentSlot.Id.MAIN_HAND))
	if definition == null:
		return null
	return definition.attack_definition


## May `item_id` go into `slot` right now? Returns `CODE_OK` or a refusal code.
func can_equip(item_id: StringName, slot: int) -> StringName:
	if not is_ready():
		return CODE_NOT_READY
	if not EquipmentSlot.is_supported(slot):
		return CODE_WRONG_SLOT
	var definition := _definition_of(item_id)
	if definition == null:
		return CODE_UNKNOWN_ITEM
	if definition.slot != slot:
		return CODE_NOT_EQUIPPABLE
	if _inventory.count_of(item_id) < 1:
		return CODE_NOT_OWNED
	return CODE_OK


## Moves one copy from the bag into the slot. A previously equipped item returns to the
## bag in the same call; any failure leaves both sides untouched.
func equip(item_id: StringName, slot: int) -> StringName:
	var code := can_equip(item_id, slot)
	if code != CODE_OK:
		return code

	var removed: int = _inventory.remove(item_id, 1)
	if removed != 1:
		# The bag refused (count changed under us); nothing was mutated.
		return CODE_NOT_OWNED

	var previous: StringName = get_equipped(slot)
	if previous != &"":
		var definition := _definition_of(previous)
		if definition == null:
			# The slot held an id this build no longer knows: return it nowhere, drop it.
			push_warning("EquipmentState: dropping unknown equipped item '%s'" % previous)
		else:
			_inventory.add(definition, 1)
	_equipped[slot] = item_id
	changed.emit()
	return CODE_OK


## Returns the slot's item to the bag. Any failure leaves both sides untouched.
func unequip(slot: int) -> StringName:
	if not is_ready():
		return CODE_NOT_READY
	var item_id := get_equipped(slot)
	if item_id == &"":
		return CODE_SLOT_EMPTY
	var definition := _definition_of(item_id)
	if definition == null:
		# An unusable record: drop it instead of stranding the slot forever.
		push_warning("EquipmentState: dropping unknown equipped item '%s'" % item_id)
		_equipped.erase(slot)
		changed.emit()
		return CODE_UNKNOWN_ITEM
	var added: int = _inventory.add(definition, 1)
	if added != 1:
		return CODE_NOT_READY
	_equipped.erase(slot)
	changed.emit()
	return CODE_OK


## Drops everything back into the bag (used when a load rebuilds the state).
func clear_into_inventory() -> void:
	for slot in equipped_slots():
		unequip(slot)


## JSON-compatible map of stable slot names to item ids.
func to_save_dict() -> Dictionary:
	var data: Dictionary = {}
	for slot in equipped_slots():
		data[String(EquipmentSlot.name_of(slot))] = String(get_equipped(slot))
	return data


## Tolerant rebuild (ADR-010/ADR-016): unknown slot names, unknown item ids, items that
## are not equippable into that slot and duplicates of a bagged copy are all dropped with
## a warning. Never fails, never invents an item.
static func from_save_dict(
	data: Dictionary, registry: ContentRegistry, inventory: Inventory
) -> EquipmentState:
	var state := EquipmentState.new()
	state.setup(registry, inventory)
	if registry == null or inventory == null:
		return state
	for key: Variant in data:
		var slot := EquipmentSlot.from_name(StringName(key))
		if not EquipmentSlot.is_supported(slot):
			push_warning("EquipmentState: dropping unknown slot '%s' from the save" % key)
			continue
		var item_id := StringName(str(data[key]))
		var definition := registry.find_item(item_id)
		if definition == null:
			push_warning("EquipmentState: dropping unknown equipped item '%s'" % item_id)
			continue
		if definition.slot != slot:
			push_warning(
				"EquipmentState: dropping '%s' from slot '%s' (item slot mismatch)"
				% [item_id, EquipmentSlot.name_of(slot)]
			)
			continue
		if state._equipped.values().has(item_id):
			push_warning("EquipmentState: dropping duplicate equipped item '%s'" % item_id)
			continue
		# The equipment record is authoritative: an equipped copy is not in the bag.
		if inventory.count_of(item_id) >= 1:
			inventory.remove(item_id, 1)
		state._equipped[slot] = item_id
	return state


func _definition_of(item_id: StringName) -> ItemDefinition:
	if _registry == null or item_id == &"":
		return null
	return _registry.find_item(item_id)


func _to_string() -> String:
	return "EquipmentState(%s)" % [equipped_entries()]
