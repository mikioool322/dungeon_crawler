class_name NpcDefinition
extends Resource

## Static definition of a non-player character (ADR-017): identity, one greeting line and
## an optional merchant the NPC can open. Immutable at runtime.
##
## The NPC knows nothing about the player, the bag, the save or combat: `NpcInteractable`
## only announces the dialogue and the HUD decides what to show.

## Stable content id, e.g. `npc.hub.smith`.
@export var id: StringName = &""

## Shown in the dialogue header.
@export var display_name: String = ""

## One line of dialogue; branching trees are out of scope.
@export var greeting: String = ""

## Optional shop this NPC offers. Null means "talk only".
@export var merchant: MerchantDefinition = null


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name == "":
		errors.append("display_name must not be empty")
	if greeting == "":
		errors.append("greeting must not be empty")
	if merchant != null and not merchant.is_valid():
		for problem in merchant.validation_errors():
			errors.append("merchant: %s" % problem)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func has_shop() -> bool:
	return merchant != null


func _to_string() -> String:
	return "NpcDefinition(%s, shop=%s)" % [id, merchant != null]
