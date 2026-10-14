class_name RewardDefinition
extends Resource

## Static, editor-authored definition of one collectable reward (ADR-009).
##
## Invariants:
## - Immutable at runtime: `LootGrant.from_reward()` copies the numbers out and
##   `LootService` never writes back into the resource.
## - A reward grants an item, gold, or both: a reward that grants neither is an
##   authoring error, not a no-op pickup.
## - `item == null` is the gold-only path and then `item_count` must stay 0;
##   `item != null` requires `item_count >= 1` and a valid `ItemDefinition`.
## - Currency is never an item: gold lives only in `PlayerSessionState.gold`.

## Stable content id, e.g. `reward.grunt_drop`.
@export var id: StringName = &""

## Item granted by this reward; null means gold-only.
@export var item: ItemDefinition = null

## Copies of `item` granted. Must be 0 when `item` is null, >= 1 otherwise.
@export var item_count: int = 0

## Gold granted. Must be >= 0; a gold-only reward needs at least 1.
@export var gold: int = 0


## Returns one message per invalid field; empty means the definition is usable.
##
## Each field contributes at most one message: the "grants nothing" message only
## replaces the (already covered) gold field of a gold-only reward.
func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if gold < 0:
		errors.append("gold must be >= 0 (got %d)" % gold)
	if item == null:
		if item_count != 0:
			errors.append("item_count must be 0 when item is null (got %d)" % item_count)
		elif gold <= 0:
			errors.append("a reward must grant at least an item or gold")
	else:
		if item_count < 1:
			errors.append("item_count must be >= 1 when item is set (got %d)" % item_count)
		if not item.is_valid():
			errors.append("item must be a valid ItemDefinition (id '%s')" % item.id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "RewardDefinition(%s, item=%s x%d, gold=%d)" % [id, item, item_count, gold]
