class_name EquipmentSlot
extends RefCounted

## Equipment slots shipped in Sprint 04 and the stable names they persist under
## (ADR-015). The enum is the single source of truth for both `ItemDefinition.slot`
## and `EquipmentState`, so content and runtime cannot drift apart.
##
## Only `MAIN_HAND` and `CHEST_ARMOR` are implemented; the enum is the extension point
## for OFF_HAND/HEAD/LEGS/BOOTS/RINGS/AMULET, which must not be added until a feature
## needs them.

enum Id { NONE = 0, MAIN_HAND = 1, CHEST_ARMOR = 2 }

## Slots an item may actually occupy (everything except NONE).
const SUPPORTED: Array[int] = [Id.MAIN_HAND, Id.CHEST_ARMOR]

## Stable persistence names, never display names.
const NAMES: Dictionary = {
	Id.MAIN_HAND: &"main_hand",
	Id.CHEST_ARMOR: &"chest_armor",
}


static func name_of(slot: int) -> StringName:
	return NAMES.get(slot, &"none")


## Parses a persisted name back to a slot; `Id.NONE` for anything unknown.
static func from_name(name: StringName) -> int:
	for slot: int in NAMES:
		if NAMES[slot] == name:
			return slot
	return Id.NONE


static func is_supported(slot: int) -> bool:
	return SUPPORTED.has(slot)


static func supported_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for slot in SUPPORTED:
		names.append(NAMES[slot])
	return names
