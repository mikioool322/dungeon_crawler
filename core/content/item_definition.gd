class_name ItemDefinition
extends Resource

## Static, editor-authored definition of one item kind (ADR-009).
##
## Invariants:
## - Immutable at runtime: `Inventory` reads these fields and never writes them.
##   Stack counts live in the `Inventory` entries, never here, because a .tres is
##   shared between every instance that loads it.
## - `id` is a stable content id (`item.minor_salve`), never a display name or a path.
## - `stackable` and `max_stack` must agree: a stackable item needs `max_stack >= 2`,
##   a non-stackable item always occupies its own inventory entry, so its
##   `max_stack` is exactly 1.
## - `icon` and `description` are presentation/flavour only; no gameplay rule reads them.

## Item category. Values are persisted in .tres files as integers, so the
## declaration order is part of the content format and must not be reordered.
enum Kind { MISC, CONSUMABLE, WEAPON, KEY }

## Stable content id, e.g. `item.minor_salve`.
@export var id: StringName = &""

## Player-facing name, e.g. "Minor Salve".
@export var display_name: String = ""

## Optional flavour text; presentation only.
@export var description: String = ""

## Item category; presentation and future rules may read it, `Inventory` does not.
@export var kind: Kind = Kind.MISC

## Whether several copies share one inventory entry.
@export var stackable: bool = true

## Copies per inventory entry. Must be >= 2 for a stackable item, exactly 1 otherwise.
@export var max_stack: int = 1

## Optional presentation texture; never needed by gameplay rules.
@export var icon: Texture2D = null

## Equipment slot this item may occupy (`EquipmentSlot.Id`); `NONE` = not equippable.
@export var slot: int = EquipmentSlot.Id.NONE

## Additive equipment modifiers (ADR-015). The item is the single source of its own
## numbers: the character panel, the combat snapshot and the save round trip all read
## these fields instead of re-deriving them somewhere else.
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var max_health_bonus: int = 0
@export var movement_bonus: float = 0.0

## Weapons only: the attack profile (reach, radius, timings) this weapon swings with.
## Null means "use the character's default profile".
@export var attack_definition: AttackDefinition = null

## Merchant pricing base, in whole gold. `0` means the item cannot be traded.
@export var base_value: int = 0


## Additive modifiers this item contributes while equipped, keyed by `CharacterStats`
## stat ids. Empty for a non-equippable item.
func equipment_modifiers() -> Dictionary:
	var modifiers: Dictionary = {}
	if attack_bonus != 0:
		modifiers[CharacterStats.ATTACK_DAMAGE] = float(attack_bonus)
	if defense_bonus != 0:
		modifiers[CharacterStats.DEFENSE] = float(defense_bonus)
	if max_health_bonus != 0:
		modifiers[CharacterStats.MAX_HEALTH] = float(max_health_bonus)
	if movement_bonus != 0.0:
		modifiers[CharacterStats.MOVEMENT_SPEED] = movement_bonus
	return modifiers


func is_equippable() -> bool:
	return EquipmentSlot.is_supported(slot)


func is_tradable() -> bool:
	return base_value > 0


## Returns one message per invalid field; empty means the definition is usable.
##
## Exactly one message is produced for the `stackable`/`max_stack` pair, so the
## message count stays a per-field count for authors and tests.
func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if max_stack < 1:
		errors.append("max_stack must be >= 1 (got %d)" % max_stack)
	elif stackable and max_stack < 2:
		errors.append("a stackable item needs max_stack >= 2 (got %d)" % max_stack)
	elif not stackable and max_stack != 1:
		errors.append("a non-stackable item needs max_stack == 1 (got %d)" % max_stack)
	if slot != EquipmentSlot.Id.NONE and not EquipmentSlot.is_supported(slot):
		errors.append("slot %d is not a supported equipment slot" % slot)
	if base_value < 0:
		errors.append("base_value must be >= 0 (got %d)" % base_value)
	if not is_finite(movement_bonus):
		errors.append("movement_bonus must be finite (got %f)" % movement_bonus)
	if attack_definition != null and not attack_definition.is_valid():
		for problem in attack_definition.validation_errors():
			errors.append("attack_definition: %s" % problem)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "ItemDefinition(%s, kind=%d, stackable=%s, max_stack=%d)" % [
		id, kind, stackable, max_stack
	]
