class_name MerchantDefinition
extends Resource

## Static definition of a merchant's stock and pricing identity (ADR-017).
##
## Invariants:
## - Immutable at runtime: prices and stock are read, never written here.
## - The price rule lives in `TradingService`; this resource only lists what is sold.
## - Stock entries reference `ItemDefinition`s that are listed in the manifest (the
##   registry validates that cross-reference).
## - Sprint 04 has unlimited stock of the listed items; a transient per-merchant counter
##   in the service is the only stock state and is never saved.

## Stable content id, e.g. `merchant.hub.smith`.
@export var id: StringName = &""

## Shown in the shop header.
@export var display_name: String = ""

## One greeting line; dialogue trees are out of scope.
@export var greeting: String = ""

## Items this merchant sells. Each entry must have `base_value >= 1` to be tradable.
@export var stock: Array[ItemDefinition] = []


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name == "":
		errors.append("display_name must not be empty")
	if stock.is_empty():
		errors.append("stock must not be empty")
	var seen: Dictionary = {}
	for item in stock:
		if item == null:
			errors.append("stock must not contain a null item")
			continue
		if item.id == &"":
			errors.append("stock contains an item without an id")
			continue
		if seen.has(item.id):
			errors.append("stock repeats '%s'" % item.id)
			continue
		seen[item.id] = true
		if not item.is_tradable():
			errors.append("stock item '%s' needs base_value >= 1 to be tradable" % item.id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "MerchantDefinition(%s, stock=%d)" % [id, stock.size()]
