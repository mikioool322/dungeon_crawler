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
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "ItemDefinition(%s, kind=%d, stackable=%s, max_stack=%d)" % [
		id, kind, stackable, max_stack
	]
